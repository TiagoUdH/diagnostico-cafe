/// Configuração gerada pelo `exportar_app.ipynb` (assets/modelo/config.json).
class ClasseModelo {
  const ClasseModelo({required this.rotulo, required this.nome});

  /// Nome da pasta da classe no dataset de treino.
  final String rotulo;

  /// Nome exibido no app.
  final String nome;

  factory ClasseModelo.fromJson(Map<String, dynamic> json) => ClasseModelo(
        rotulo: json['rotulo'] as String,
        nome: json['nome'] as String,
      );
}

class MetricasModelo {
  const MetricasModelo({this.acuracia, this.f1Macro, this.nImagens, this.latenciaMs});

  final double? acuracia;
  final double? f1Macro;
  final int? nImagens;
  final double? latenciaMs;

  factory MetricasModelo.fromJson(Map<String, dynamic> json) => MetricasModelo(
        acuracia: (json['acuracia'] as num?)?.toDouble(),
        f1Macro: (json['f1_macro'] as num?)?.toDouble(),
        nImagens: (json['n_imagens'] as num?)?.toInt(),
        latenciaMs: (json['latencia_ms_cpu'] as num?)?.toDouble(),
      );
}

class ConfigModelo {
  const ConfigModelo({
    required this.modelo,
    required this.dataset,
    required this.tamanhoEntrada,
    required this.temperatura,
    required this.limiarAbstencao,
    required this.classes,
    this.metricas,
  });

  final String modelo;
  final String dataset;

  /// Lado da imagem de entrada do modelo (pixels 0-255, RGB).
  final int tamanhoEntrada;

  /// Temperatura do Temperature Scaling: probabilidade exibida = softmax(logits / T).
  final double temperatura;

  /// Abaixo desta confiança calibrada o app pede outra foto (predição seletiva).
  final double limiarAbstencao;

  final List<ClasseModelo> classes;
  final MetricasModelo? metricas;

  int get numClasses => classes.length;

  factory ConfigModelo.fromJson(Map<String, dynamic> json) => ConfigModelo(
        modelo: json['modelo'] as String? ?? 'modelo',
        dataset: json['dataset'] as String? ?? '',
        tamanhoEntrada: (json['tamanho_entrada'] as num?)?.toInt() ?? 224,
        temperatura: (json['temperatura'] as num?)?.toDouble() ?? 1.0,
        limiarAbstencao: (json['limiar_abstencao'] as num?)?.toDouble() ?? 0.7,
        classes: (json['classes'] as List)
            .map((c) => ClasseModelo.fromJson(c as Map<String, dynamic>))
            .toList(growable: false),
        metricas: json['metricas_teste'] == null
            ? null
            : MetricasModelo.fromJson(json['metricas_teste'] as Map<String, dynamic>),
      );
}
