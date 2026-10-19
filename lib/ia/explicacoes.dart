import 'dart:math' as math;
import 'dart:typed_data';

import 'executor_modelo.dart';
import 'imagem.dart';
import 'matematica.dart';
import 'slic.dart';

typedef Progresso = void Function(double fracao);

/// Mapa de relevância em [0, 1] numa grade [altura]×[largura] sobre a imagem de entrada do modelo.
class MapaExplicacao {
  const MapaExplicacao(this.valores, this.altura, this.largura);

  final Float32List valores;
  final int altura;
  final int largura;

  /// Divide pelo máximo, como o Grad-CAM dos notebooks (`heatmap / max(heatmap)`).
  factory MapaExplicacao.normalizado(Float32List bruto, int altura, int largura) {
    var maximo = 0.0;
    for (final v in bruto) {
      maximo = math.max(maximo, v);
    }
    final valores = Float32List(bruto.length);
    if (maximo > 0) {
      for (var i = 0; i < bruto.length; i++) {
        valores[i] = math.max(0.0, bruto[i]) / maximo;
      }
    }
    return MapaExplicacao(valores, altura, largura);
  }
}

/// Recorta o Grad-CAM de [classe] da saída `[n, h, w]` do modelo.
MapaExplicacao gradCamDaClasse(Float32List gradcams, int classe, int altura, int largura) {
  final tamanho = altura * largura;
  return MapaExplicacao.normalizado(
    Float32List.sublistView(gradcams, classe * tamanho, (classe + 1) * tamanho),
    altura,
    largura,
  );
}

/// Kernel do borrão que serve de ponto de partida da Inserção (mesmo BLUR_KSIZE dos notebooks).
const tamanhoBorrao = 31;

/// Cinza médio que cobre cada região na Oclusão (o quadrado cinza de Zeiler & Fergus, 2014). Um borrão não
/// serve aqui: ele preserva cor e manchas grandes, e para ferrugem/cercosporiose a confiança nem caía.
const cinzaOclusao = 127.5;

// ── Sensibilidade à Oclusão (Zeiler & Fergus, 2014) ───────────────────────────────────────────────────────

class ResultadoOclusao {
  const ResultadoOclusao(this.mapa, this.probabilidadeOriginal, this.maiorQueda);

  final MapaExplicacao mapa;
  final double probabilidadeOriginal;

  /// Maior queda de probabilidade ao cobrir uma única região (0-1).
  final double maiorQueda;
}

/// Cobre uma região de cada vez com um quadrado cinza e mede quanto a probabilidade da
/// [classe] cai. Só usa inferências -- funciona com qualquer modelo, inclusive quantizado.
ResultadoOclusao oclusao(
  ExecutorModelo modelo,
  Float32List entrada,
  int classe, {
  int grade = 8,
  Progresso? progresso,
}) {
  final lado = modelo.lado;
  final cinza = Float32List(entrada.length)..fillRange(0, entrada.length, cinzaOclusao);
  final pOriginal = modelo.probabilidades(entrada)[classe];
  final quedas = Float32List(grade * grade);
  final tamanhoCelula = lado / grade;
  final perturbada = Float32List(entrada.length);

  for (var cy = 0; cy < grade; cy++) {
    for (var cx = 0; cx < grade; cx++) {
      perturbada.setAll(0, entrada);
      _copiarRegiao(perturbada, cinza, lado, (cx * tamanhoCelula).round(), (cy * tamanhoCelula).round(),
          ((cx + 1) * tamanhoCelula).round(), ((cy + 1) * tamanhoCelula).round());
      final p = modelo.probabilidades(perturbada)[classe];
      quedas[cy * grade + cx] = math.max(0, pOriginal - p);
      progresso?.call((cy * grade + cx + 1) / (grade * grade));
    }
  }
  var maior = 0.0;
  for (final q in quedas) {
    maior = math.max(maior, q);
  }
  return ResultadoOclusao(MapaExplicacao.normalizado(quedas, grade, grade), pOriginal, maior);
}

// ── Fidelidade do Grad-CAM: Inserção / Remoção (Petsiuk et al., 2018) ───────────────────────────────────

class ResultadoFidelidade {
  const ResultadoFidelidade(this.curvaInsercao, this.curvaRemocao);

  final List<double> curvaInsercao;
  final List<double> curvaRemocao;

  double get aucInsercao => aucTrapezio(curvaInsercao);
  double get aucRemocao => aucTrapezio(curvaRemocao);

  /// Inserção − Remoção: quanto maior, mais o mapa aponta para o que o modelo realmente usa.
  double get score => aucInsercao - aucRemocao;
}

/// Mesmo procedimento de `curva_insercao_delecao` do mobilenet.ipynb, com os substratos do RISE original:
/// revela (inserção, a partir da foto borrada) ou pinta de PRETO (remoção, a partir da original) as células do
/// [mapa] da mais para a menos importante.
ResultadoFidelidade insercaoRemocao(
  ExecutorModelo modelo,
  Float32List entrada,
  MapaExplicacao mapa,
  int classe, {
  Progresso? progresso,
}) {
  final lado = modelo.lado;
  final borrada = borrarGaussiano(entrada, lado, tamanhoBorrao);
  final ordem = List.generate(mapa.valores.length, (i) => i)
    ..sort((a, b) => mapa.valores[b].compareTo(mapa.valores[a]));
  final alturaBloco = lado ~/ mapa.altura, larguraBloco = lado ~/ mapa.largura;
  final total = 2 * (ordem.length + 1);
  var feitos = 0;

  List<double> curva(Float32List base, Float32List fonte) {
    final atual = Float32List.fromList(base);
    final probs = <double>[modelo.probabilidades(atual)[classe]];
    progresso?.call(++feitos / total);
    for (final idx in ordem) {
      final r = idx ~/ mapa.largura, c = idx % mapa.largura;
      _copiarRegiao(atual, fonte, lado, c * larguraBloco, r * alturaBloco,
          math.min((c + 1) * larguraBloco, lado), math.min((r + 1) * alturaBloco, lado));
      probs.add(modelo.probabilidades(atual)[classe]);
      progresso?.call(++feitos / total);
    }
    return probs;
  }

  return ResultadoFidelidade(curva(borrada, entrada), curva(entrada, Float32List(entrada.length)));
}

// ── LIME por superpixels (Ribeiro et al., 2016) ──────────────────────────────────────────────────────────

class ResultadoLime {
  const ResultadoLime({
    required this.segmentos,
    required this.numSegmentos,
    required this.pesos,
    required this.r2,
    required this.lado,
  });

  /// Superpixel de cada pixel da imagem de entrada ([lado]×[lado]).
  final Int32List segmentos;
  final int numSegmentos;

  /// Peso do modelo linear local por superpixel: > 0 favorece a classe, < 0 é contra.
  final Float64List pesos;
  final double r2;
  final int lado;
}

/// Reimplementação do `lime_image.LimeImageExplainer.explain_instance` dos notebooks: amostras que
/// "apagam" (hide_color=0) superpixels ao acaso, kernel exponencial sobre a distância de cosseno
/// (kernel_width=0,25) e regressão Ridge(alpha=1) ponderada sobre a probabilidade da [classe].
ResultadoLime lime(
  ExecutorModelo modelo,
  Uint8List rgb,
  int classe, {
  int numAmostras = 300,
  int semente = 42,
  Progresso? progresso,
}) {
  final lado = modelo.lado;
  final seg = slic(rgb, lado);
  final d = seg.numSegmentos;
  final aleatorio = math.Random(semente);

  final x = Float64List(numAmostras * d);
  final y = Float64List(numAmostras);
  final pesos = Float64List(numAmostras);
  final perturbada = Float32List(lado * lado * 3);
  const larguraKernel = 0.25;

  for (var a = 0; a < numAmostras; a++) {
    // 1ª amostra = imagem original completa, como no LIME
    var ativos = 0;
    for (var j = 0; j < d; j++) {
      final v = a == 0 || aleatorio.nextBool() ? 1.0 : 0.0;
      x[a * d + j] = v;
      if (v == 1) ativos++;
    }
    for (var p = 0; p < lado * lado; p++) {
      final ligado = x[a * d + seg.rotulos[p]] == 1;
      for (var c = 0; c < 3; c++) {
        perturbada[p * 3 + c] = ligado ? rgb[p * 3 + c].toDouble() : 0;
      }
    }
    y[a] = modelo.probabilidades(perturbada)[classe];

    // Distância de cosseno entre a amostra (binária) e a imagem original (todos os superpixels ligados)
    final distancia = ativos == 0 ? 1.0 : 1 - ativos / (math.sqrt(ativos) * math.sqrt(d));
    pesos[a] = math.sqrt(math.exp(-(distancia * distancia) / (larguraKernel * larguraKernel)));
    progresso?.call((a + 1) / numAmostras);
  }

  final ajuste = ridgePonderada(x, y, pesos, numAmostras, d);
  return ResultadoLime(
      segmentos: seg.rotulos, numSegmentos: d, pesos: ajuste.coeficientes, r2: ajuste.r2, lado: lado);
}

void _copiarRegiao(Float32List destino, Float32List fonte, int lado, int x0, int y0, int x1, int y1) {
  for (var y = y0; y < y1; y++) {
    final inicio = (y * lado + x0) * 3, fim = (y * lado + x1) * 3;
    destino.setRange(inicio, fim, fonte, inicio);
  }
}
