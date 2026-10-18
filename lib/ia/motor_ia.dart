import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config_modelo.dart';
import 'executor_modelo.dart';
import 'explicacoes.dart';
import 'explicacoes.dart' as xai;
import 'imagem.dart';
import 'matematica.dart';
import 'visualizacao.dart';

/// Resultado da classificação de uma foto. Só contém dados simples, para poder ir e voltar dos isolates.
class Analise {
  const Analise({
    required this.imagem,
    required this.pngOriginal,
    required this.logits,
    required this.probabilidades,
    required this.gradcams,
    required this.gradeAltura,
    required this.gradeLargura,
    required this.tempoMs,
  });

  final ImagemPreparada imagem;
  final Uint8List pngOriginal;
  final Float32List logits;

  /// Probabilidades CALIBRADAS: softmax(logits / temperatura).
  final Float32List probabilidades;
  final Float32List gradcams;
  final int gradeAltura;
  final int gradeLargura;
  final int tempoMs;

  int get classePredita => argmax(probabilidades);
  double get confianca => probabilidades[classePredita];

  MapaExplicacao gradCam(int classe) => gradCamDaClasse(gradcams, classe, gradeAltura, gradeLargura);
}

/// Ponto de entrada da IA no app. A inferência e os métodos de explicação (dezenas a centenas de inferências)
/// rodam num isolate separado para a interface não travar.
class MotorIA {
  MotorIA._(this.config, this._bytesModelo);

  static const caminhoModelo = 'assets/modelo/modelo.tflite';
  static const caminhoConfig = 'assets/modelo/config.json';

  final ConfigModelo config;
  final Uint8List _bytesModelo;

  static Future<MotorIA> carregar() async {
    final ConfigModelo config;
    final ByteData dados;
    try {
      config = ConfigModelo.fromJson(jsonDecode(await rootBundle.loadString(caminhoConfig)) as Map<String, dynamic>);
      dados = await rootBundle.load(caminhoModelo);
    } on FlutterError {
      throw StateError(
        'Arquivos do modelo não encontrados em assets/modelo/. Rode o notebook exportar_app.ipynb e copie '
        'modelo.tflite e config.json para app/assets/modelo/.',
      );
    }
    final bytes = dados.buffer.asUint8List(dados.offsetInBytes, dados.lengthInBytes);
    final motor = MotorIA._(config, bytes);
    // Valida o modelo já na abertura do app (formato das saídas × número de classes do config.json)
    await motor._emSegundoPlano((_) {
      final m = ExecutorModelo(bytes);
      final n = m.numClasses;
      m.fechar();
      if (n != config.numClasses) {
        throw StateError('modelo.tflite tem $n classes, mas config.json lista ${config.numClasses}.');
      }
      return null;
    });
    return motor;
  }

  Future<Analise> analisar(Uint8List bytesFoto) {
    final bytesModelo = _bytesModelo;
    final lado = config.tamanhoEntrada;
    final temperatura = config.temperatura;
    return _emSegundoPlano((_) {
      final inicio = DateTime.now();
      final imagem = prepararImagem(bytesFoto, lado);
      final modelo = ExecutorModelo(bytesModelo);
      try {
        final saida = modelo.inferir(imagem.paraEntrada());
        final tempoMs = DateTime.now().difference(inicio).inMilliseconds;
        return Analise(
          imagem: imagem,
          pngOriginal: codificarPng(imagem.exibicaoRgb, imagem.largura, imagem.altura),
          logits: saida.logits,
          probabilidades: softmax(saida.logits, temperatura: temperatura),
          gradcams: saida.gradcams,
          gradeAltura: modelo.gradeAltura,
          gradeLargura: modelo.gradeLargura,
          tempoMs: tempoMs,
        );
      } finally {
        modelo.fechar();
      }
    });
  }

  Future<ResultadoOclusao> oclusao(Analise analise, int classe, {Progresso? progresso}) {
    final bytesModelo = _bytesModelo;
    final entrada = analise.imagem.paraEntrada();
    return _emSegundoPlano((p) => _comModelo(bytesModelo, (m) => xai.oclusao(m, entrada, classe, progresso: p)),
        progresso: progresso);
  }

  Future<ResultadoFidelidade> fidelidade(Analise analise, int classe, {Progresso? progresso}) {
    final bytesModelo = _bytesModelo;
    final entrada = analise.imagem.paraEntrada();
    final mapa = analise.gradCam(classe);
    return _emSegundoPlano(
        (p) => _comModelo(bytesModelo, (m) => insercaoRemocao(m, entrada, mapa, classe, progresso: p)),
        progresso: progresso);
  }

  Future<ResultadoLime> lime(Analise analise, int classe, {int numAmostras = 300, Progresso? progresso}) {
    final bytesModelo = _bytesModelo;
    final rgb = analise.imagem.entradaRgb;
    return _emSegundoPlano(
        (p) => _comModelo(bytesModelo, (m) => xai.lime(m, rgb, classe, numAmostras: numAmostras, progresso: p)),
        progresso: progresso);
  }

  Future<Uint8List> renderizarMapa(Analise analise, MapaExplicacao mapa) {
    final im = analise.imagem;
    return Isolate.run(() => sobreporMapa(im.exibicaoRgb, im.largura, im.altura, mapa));
  }

  Future<Uint8List> renderizarLime(Analise analise, ResultadoLime resultado) {
    final im = analise.imagem;
    return Isolate.run(() => desenharLime(im.exibicaoRgb, im.largura, im.altura, resultado));
  }

  /// Roda [tarefa] num isolate novo, repassando o progresso (0-1) para [progresso] na thread da interface.
  Future<T> _emSegundoPlano<T>(T Function(Progresso progresso) tarefa, {Progresso? progresso}) async {
    final porta = ReceivePort();
    final resultado = Completer<T>();
    porta.listen((mensagem) {
      if (mensagem is double) {
        progresso?.call(mensagem);
      } else if (mensagem is _Resposta) {
        porta.close();
        if (mensagem.erro == null) {
          resultado.complete(mensagem.valor as T);
        } else {
          resultado.completeError(Exception(mensagem.erro));
        }
      } else if (mensagem == null && !resultado.isCompleted) {
        // Isolate terminou sem responder (ex.: falha nativa no TFLite)
        porta.close();
        resultado.completeError(Exception('O processamento foi interrompido inesperadamente.'));
      }
    });
    await Isolate.spawn(_executarPedido, _Pedido(porta.sendPort, tarefa), onExit: porta.sendPort);
    return resultado.future;
  }
}

R _comModelo<R>(Uint8List bytesModelo, R Function(ExecutorModelo modelo) uso) {
  final modelo = ExecutorModelo(bytesModelo);
  try {
    return uso(modelo);
  } finally {
    modelo.fechar();
  }
}

class _Pedido {
  const _Pedido(this.porta, this.tarefa);

  final SendPort porta;
  final Object? Function(Progresso progresso) tarefa;
}

class _Resposta {
  const _Resposta(this.valor, this.erro);

  final Object? valor;
  final String? erro;
}

void _executarPedido(_Pedido pedido) {
  var ultimo = -1.0;
  void progresso(double fracao) {
    // No máximo ~100 mensagens por tarefa
    if (fracao - ultimo >= 0.01 || fracao >= 1) {
      ultimo = fracao;
      pedido.porta.send(fracao);
    }
  }

  try {
    pedido.porta.send(_Resposta(pedido.tarefa(progresso), null));
  } catch (e) {
    pedido.porta.send(_Resposta(null, e is StateError ? e.message : e.toString()));
  }
}
