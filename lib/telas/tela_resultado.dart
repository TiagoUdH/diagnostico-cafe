import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../ia/explicacoes.dart';
import '../ia/motor_ia.dart';
import '../widgets/grafico_fidelidade.dart';

enum Visao {
  original('Foto'),
  gradcam('Grad-CAM'),
  oclusao('Oclusão'),
  lime('LIME');

  const Visao(this.rotulo);

  final String rotulo;
}

class TelaResultado extends StatefulWidget {
  const TelaResultado({super.key, required this.motor, required this.analise});

  final MotorIA motor;
  final Analise analise;

  @override
  State<TelaResultado> createState() => _TelaResultadoState();
}

class _TelaResultadoState extends State<TelaResultado> {
  late int _classe = widget.analise.classePredita;
  Visao _visao = Visao.gradcam;

  // Resultados já calculados, por classe (trocar de classe e voltar não recalcula)
  final _pngGradCam = <int, Uint8List>{};
  final _oclusao = <int, ResultadoOclusao>{};
  final _pngOclusao = <int, Uint8List>{};
  final _lime = <int, ResultadoLime>{};
  final _pngLime = <int, Uint8List>{};
  final _fidelidade = <int, ResultadoFidelidade>{};

  String? _calculando; // descrição da tarefa em andamento
  double _progresso = 0;

  MotorIA get _motor => widget.motor;
  Analise get _analise => widget.analise;

  @override
  void initState() {
    super.initState();
    _garantirGradCam();
  }

  Future<void> _garantirGradCam() async {
    final classe = _classe;
    if (_pngGradCam.containsKey(classe)) return;
    final png = await _motor.renderizarMapa(_analise, _analise.gradCam(classe));
    if (mounted) setState(() => _pngGradCam[classe] = png);
  }

  Future<void> _executar(String descricao, Future<void> Function(Progresso progresso) tarefa) async {
    if (_calculando != null) return;
    setState(() {
      _calculando = descricao;
      _progresso = 0;
    });
    try {
      await tarefa((p) {
        if (mounted) setState(() => _progresso = p);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha em "$descricao": ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) setState(() => _calculando = null);
    }
  }

  Future<void> _calcularOclusao() {
    final classe = _classe;
    return _executar('Oclusão', (p) async {
      final r = await _motor.oclusao(_analise, classe, progresso: p);
      final png = await _motor.renderizarMapa(_analise, r.mapa);
      if (mounted) {
        setState(() {
          _oclusao[classe] = r;
          _pngOclusao[classe] = png;
        });
      }
    });
  }

  Future<void> _calcularLime() {
    final classe = _classe;
    return _executar('LIME', (p) async {
      final r = await _motor.lime(_analise, classe, progresso: p);
      final png = await _motor.renderizarLime(_analise, r);
      if (mounted) {
        setState(() {
          _lime[classe] = r;
          _pngLime[classe] = png;
        });
      }
    });
  }

  Future<void> _calcularFidelidade() {
    final classe = _classe;
    return _executar('Fidelidade do Grad-CAM', (p) async {
      final r = await _motor.fidelidade(_analise, classe, progresso: p);
      if (mounted) setState(() => _fidelidade[classe] = r);
    });
  }

  void _selecionarClasse(int classe) {
    setState(() => _classe = classe);
    _garantirGradCam();
  }

  @override
  Widget build(BuildContext context) {
    final config = _motor.config;
    final predita = _analise.classePredita;
    final confianca = _analise.confianca;
    final abaixoDoLimiar = confianca < config.limiarAbstencao;
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Resultado')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _CartaoDiagnostico(
              nome: config.classes[predita].nome,
              confianca: confianca,
              abaixoDoLimiar: abaixoDoLimiar,
              limiar: config.limiarAbstencao,
              tempoMs: _analise.tempoMs,
            ),
            const SizedBox(height: 16),
            SegmentedButton<Visao>(
              segments: [
                // Só texto: com ícones, 4 segmentos não cabem em telas de 360 dp
                for (final v in Visao.values) ButtonSegment(value: v, label: Text(v.rotulo)),
              ],
              selected: {_visao},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _visao = s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 12),
            _buildImagem(context),
            const SizedBox(height: 8),
            _buildPainelVisao(context),
            const SizedBox(height: 20),
            Text('Probabilidade por classe', style: tema.textTheme.titleMedium),
            Text(
              'Toque numa classe para ver as explicações dela.',
              style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final i in _ordemClasses())
              _BarraClasse(
                nome: config.classes[i].nome,
                probabilidade: _analise.probabilidades[i],
                selecionada: i == _classe,
                predita: i == predita,
                onTap: _calculando == null ? () => _selecionarClasse(i) : null,
              ),
            const SizedBox(height: 20),
            const _SobreMetodos(),
          ],
        ),
      ),
    );
  }

  List<int> _ordemClasses() => List.generate(_analise.probabilidades.length, (i) => i)
    ..sort((a, b) => _analise.probabilidades[b].compareTo(_analise.probabilidades[a]));

  Widget _buildImagem(BuildContext context) {
    final png = switch (_visao) {
      Visao.original => _analise.pngOriginal,
      Visao.gradcam => _pngGradCam[_classe],
      Visao.oclusao => _pngOclusao[_classe],
      Visao.lime => _pngLime[_classe],
    };
    final nomeClasse = _motor.config.classes[_classe].nome;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: _analise.imagem.largura / _analise.imagem.altura,
            child: Image.memory(png ?? _analise.pngOriginal, fit: BoxFit.cover, gaplessPlayback: true),
          ),
          if (_visao != Visao.original)
            Positioned(
              left: 8,
              top: 8,
              child: Chip(
                label: Text('${_visao.rotulo} · $nomeClasse'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (_visao != Visao.original && png == null && _calculando == null)
            Positioned.fill(child: Container(color: Colors.black26)),
        ],
      ),
    );
  }

  Widget _buildPainelVisao(BuildContext context) {
    final tema = Theme.of(context);
    final legendaCalor = Row(
      children: [
        const Text('pouco'),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              gradient: const LinearGradient(
                colors: [Color(0xFF00007F), Color(0xFF0000FF), Color(0xFF00FFFF), Color(0xFFFFFF00), Color(0xFFFF0000), Color(0xFF7F0000)],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Text('muito relevante'),
      ],
    );

    Widget progresso() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              LinearProgressIndicator(value: _progresso),
              const SizedBox(height: 6),
              Text('Calculando $_calculando... ${(_progresso * 100).round()}%'),
            ],
          ),
        );

    switch (_visao) {
      case Visao.original:
        return const SizedBox.shrink();
      case Visao.gradcam:
        final fid = _fidelidade[_classe];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            legendaCalor,
            const SizedBox(height: 12),
            if (_calculando == 'Fidelidade do Grad-CAM')
              progresso()
            else if (fid == null)
              OutlinedButton.icon(
                onPressed: _calculando == null ? _calcularFidelidade : null,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Medir fidelidade (Inserção/Remoção)'),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fidelidade do Grad-CAM', style: tema.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      SizedBox(height: 160, child: GraficoFidelidade(resultado: fid)),
                      const SizedBox(height: 8),
                      Text('AUC Inserção: ${fid.aucInsercao.toStringAsFixed(3)} (maior é melhor)\n'
                          'AUC Remoção: ${fid.aucRemocao.toStringAsFixed(3)} (menor é melhor)\n'
                          'Score (Ins − Rem): ${fid.score.toStringAsFixed(3)}'),
                    ],
                  ),
                ),
              ),
          ],
        );
      case Visao.oclusao:
        final r = _oclusao[_classe];
        if (_calculando == 'Oclusão') return progresso();
        if (r == null) {
          return _BotaoCalcular(
            texto: 'Calcular Oclusão (65 inferências)',
            onPressed: _calculando == null ? _calcularOclusao : null,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            legendaCalor,
            const SizedBox(height: 8),
            Text('Cobrir a região mais quente reduz a probabilidade em '
                '${(r.maiorQueda * 100).toStringAsFixed(1)} pontos percentuais '
                '(de ${(r.probabilidadeOriginal * 100).toStringAsFixed(1)}%).'),
          ],
        );
      case Visao.lime:
        final r = _lime[_classe];
        if (_calculando == 'LIME') return progresso();
        if (r == null) {
          return _BotaoCalcular(
            texto: 'Calcular LIME (300 inferências)',
            onPressed: _calculando == null ? _calcularLime : null,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                _Quadrado(Color(0xFF2ECC40)),
                Text(' a favor da classe   '),
                _Quadrado(Color(0xFFE74C3C)),
                Text(' contra'),
              ],
            ),
            const SizedBox(height: 6),
            Text('${r.numSegmentos} superpixels · ajuste local R² = ${r.r2.toStringAsFixed(2)}',
                style: tema.textTheme.bodySmall),
          ],
        );
    }
  }
}

class _CartaoDiagnostico extends StatelessWidget {
  const _CartaoDiagnostico({
    required this.nome,
    required this.confianca,
    required this.abaixoDoLimiar,
    required this.limiar,
    required this.tempoMs,
  });

  final String nome;
  final double confianca;
  final bool abaixoDoLimiar;
  final double limiar;
  final int tempoMs;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    return Card(
      color: abaixoDoLimiar ? cores.errorContainer : cores.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(abaixoDoLimiar ? 'Diagnóstico incerto' : 'Diagnóstico', style: tema.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(nome, style: tema.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Confiança: ${(confianca * 100).toStringAsFixed(1)}%  ·  $tempoMs ms'),
            if (abaixoDoLimiar) ...[
              const SizedBox(height: 8),
              Text(
                'A confiança ficou abaixo de ${(limiar * 100).round()}%. Tire outra foto com a folha centralizada, '
                'bem iluminada e em foco antes de confiar neste resultado.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarraClasse extends StatelessWidget {
  const _BarraClasse({
    required this.nome,
    required this.probabilidade,
    required this.selecionada,
    required this.predita,
    required this.onTap,
  });

  final String nome;
  final double probabilidade;
  final bool selecionada;
  final bool predita;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selecionada ? cores.primary : Colors.transparent, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    nome,
                    style: TextStyle(fontWeight: predita ? FontWeight.w600 : FontWeight.normal),
                  ),
                ),
                Text('${(probabilidade * 100).toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: probabilidade, minHeight: 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotaoCalcular extends StatelessWidget {
  const _BotaoCalcular({required this.texto, required this.onPressed});

  final String texto;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(onPressed: onPressed, icon: const Icon(Icons.play_arrow), label: Text(texto));
  }
}

class _Quadrado extends StatelessWidget {
  const _Quadrado(this.cor);

  final Color cor;

  @override
  Widget build(BuildContext context) =>
      Container(width: 14, height: 14, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3)));
}

class _SobreMetodos extends StatelessWidget {
  const _SobreMetodos();

  @override
  Widget build(BuildContext context) {
    return const Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(Icons.help_outline),
        title: Text('Como ler as explicações'),
        childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Grad-CAM — usa os gradientes da última camada convolucional para mostrar onde o modelo '
            '"olhou" para decidir. Calculado junto com a classificação, sem custo extra.\n\n'
            'Fidelidade (Inserção/Remoção) — testa se o Grad-CAM é confiável: revela/apaga a foto na ordem '
            'do mapa e mede a probabilidade. Um mapa fiel faz a probabilidade subir rápido na inserção e cair '
            'rápido na remoção.\n\n'
            'Oclusão — cobre uma região de cada vez com a própria foto borrada; regiões quentes são as que, '
            'cobertas, mais derrubam a confiança. Não depende de gradientes.\n\n'
            'LIME — divide a folha em superpixels, apaga combinações aleatórias deles e ajusta um modelo linear '
            'local: verde ajuda a classe escolhida, vermelho pesa contra.\n\n'
            'Integrated Gradients (usado no TCC) não está no app: precisa de gradientes através de todo o '
            'backbone, que o TFLite não calcula no celular.',
          ),
        ],
      ),
    );
  }
}
