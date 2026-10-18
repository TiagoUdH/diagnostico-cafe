import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'matematica.dart';

/// Envolve o interpretador TFLite do modelo exportado pelo `exportar_app.ipynb`.
///
/// O modelo tem UMA entrada `[1, lado, lado, 3]` (float32, 0-255) e DUAS saídas, identificadas pelo formato
/// (a ordem dos índices muda conforme a versão do conversor):
/// - logits `[1, n]`;
/// - Grad-CAM de todas as classes `[n, h, w]` (ReLU já aplicada, ainda não normalizado).
///
/// Não é enviável entre isolates: cada isolate de trabalho cria o seu a partir dos bytes do modelo.
class ExecutorModelo {
  ExecutorModelo._(this._interpretador, this._idxLogits, this._idxCam, this.lado, this.numClasses,
      this.gradeAltura, this.gradeLargura)
      : _logits = Float32List(numClasses),
        _cams = Float32List(numClasses * gradeAltura * gradeLargura);

  factory ExecutorModelo(Uint8List bytesModelo, {int threads = 4}) {
    final interpretador = Interpreter.fromBuffer(bytesModelo, options: InterpreterOptions()..threads = threads);
    final formaEntrada = interpretador.getInputTensors().first.shape;
    final saidas = interpretador.getOutputTensors();
    final idxLogits = saidas.indexWhere((t) => t.shape.length == 2);
    final idxCam = saidas.indexWhere((t) => t.shape.length == 3);
    if (formaEntrada.length != 4 || idxLogits < 0 || idxCam < 0) {
      interpretador.close();
      throw StateError(
        'modelo.tflite inesperado (entrada $formaEntrada, saídas ${saidas.map((t) => t.shape).toList()}). '
        'Gere-o com o notebook exportar_app.ipynb.',
      );
    }
    final formaCam = saidas[idxCam].shape;
    return ExecutorModelo._(
        interpretador, idxLogits, idxCam, formaEntrada[1], formaCam[0], formaCam[1], formaCam[2]);
  }

  final Interpreter _interpretador;
  final int _idxLogits;
  final int _idxCam;
  final int lado;
  final int numClasses;
  final int gradeAltura;
  final int gradeLargura;
  final Float32List _logits;
  final Float32List _cams;

  /// Roda o modelo e devolve cópias de (logits, Grad-CAMs).
  ({Float32List logits, Float32List gradcams}) inferir(Float32List entrada) {
    _rodar(entrada);
    return (logits: Float32List.fromList(_logits), gradcams: Float32List.fromList(_cams));
  }

  /// Probabilidades SEM calibração (softmax com T=1) -- é o que os métodos de explicação perturbam, como o
  /// `model.predict` dos notebooks.
  Float32List probabilidades(Float32List entrada) {
    _rodar(entrada);
    return softmax(_logits);
  }

  void _rodar(Float32List entrada) {
    _interpretador.runForMultipleInputs(
      [entrada.buffer],
      {_idxLogits: _logits.buffer, _idxCam: _cams.buffer},
    );
  }

  void fechar() => _interpretador.close();
}
