import 'dart:typed_data';

import 'package:diagnostico_cafe/ia/explicacoes.dart';
import 'package:diagnostico_cafe/ia/imagem.dart';
import 'package:diagnostico_cafe/ia/matematica.dart';
import 'package:diagnostico_cafe/ia/slic.dart';
import 'package:diagnostico_cafe/ia/visualizacao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('softmax com temperatura', () {
    final p = softmax(Float32List.fromList([2, 1, 0]));
    expect(p.reduce((a, b) => a + b), closeTo(1, 1e-6));
    expect(p[0], closeTo(0.6652, 1e-4));
    final pQuente = softmax(Float32List.fromList([2, 1, 0]), temperatura: 2);
    expect(pQuente[0], lessThan(p[0])); // T > 1 suaviza a confiança
    expect(argmax(p), 0);
  });

  test('AUC pela regra do trapézio', () {
    expect(aucTrapezio([0, 1]), closeTo(0.5, 1e-12));
    expect(aucTrapezio([1, 1, 1]), closeTo(1, 1e-12));
  });

  test('Ridge ponderada igual ao sklearn Ridge(alpha=1).fit(X, y, sample_weight=w)', () {
    // Valores de referência gerados com scikit-learn 1.5.0
    final x = Float64List.fromList([
      0, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1, 1, 1, //
      1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1,
    ]);
    final y = Float64List.fromList([
      0.9616571937, 0.7247899408, 0.5412268555, 0.2768912040, 0.1606520088, 0.9699254132, //
      0.5160685855, 0.1158656125, 0.6234897555, 0.7766831143, 0.6130033011, 0.9172977048,
    ]);
    final w = Float64List.fromList([
      0.1395928767, 0.6285892633, 0.5593358829, 0.1623495791, 0.7413281691, 0.9526328385, //
      0.6929410181, 0.3600974477, 0.9398815210, 0.6094958815, 0.6108888845, 0.8530302077,
    ]);
    final r = ridgePonderada(x, y, w, 12, 4);
    const esperado = [-0.0019707579, -0.0177122442, 0.1390055780, 0.1871261141];
    for (var j = 0; j < 4; j++) {
      expect(r.coeficientes[j], closeTo(esperado[j], 1e-8));
    }
    expect(r.intercepto, closeTo(0.5016750109, 1e-8));
  });

  test('Borrão gaussiano igual ao cv2.GaussianBlur(img, (31, 31), 0)', () {
    const lado = 20;
    final rgb = Float32List(lado * lado * 3);
    for (var y = 0; y < lado; y++) {
      for (var x = 0; x < lado; x++) {
        for (var c = 0; c < 3; c++) {
          rgb[(y * lado + x) * 3 + c] = ((x * 37 + y * 91 + c * 53 + x * y * 7) % 256).toDouble();
        }
      }
    }
    final b = borrarGaussiano(rgb, lado, 31);
    double em(int y, int x, int c) => b[(y * lado + x) * 3 + c];
    // Valores de referência gerados com opencv-python-headless 4.10
    expect(em(0, 0, 0), closeTo(127.7958, 1e-2));
    expect(em(5, 7, 1), closeTo(129.6393, 1e-2));
    expect(em(19, 19, 2), closeTo(123.5342, 1e-2));
    expect(em(10, 3, 0), closeTo(125.6844, 1e-2));
  });

  test('SLIC separa regiões de cores diferentes em superpixels conexos', () {
    const lado = 64;
    final rgb = Uint8List(lado * lado * 3);
    for (var y = 0; y < lado; y++) {
      for (var x = 0; x < lado; x++) {
        final i = (y * lado + x) * 3;
        // metade esquerda verde, metade direita marrom
        if (x < lado / 2) {
          rgb[i + 1] = 160;
        } else {
          rgb[i] = 120;
          rgb[i + 1] = 70;
          rgb[i + 2] = 20;
        }
      }
    }
    final r = slic(rgb, lado, segmentosAlvo: 16);
    expect(r.numSegmentos, inInclusiveRange(4, 40));
    expect(r.rotulos.every((v) => v >= 0 && v < r.numSegmentos), isTrue);
    // Nenhum superpixel atravessa a fronteira das duas cores
    for (var s = 0; s < r.numSegmentos; s++) {
      final xs = <int>{};
      for (var p = 0; p < lado * lado; p++) {
        if (r.rotulos[p] == s) xs.add(p % lado < lado ~/ 2 ? 0 : 1);
      }
      expect(xs.length, 1, reason: 'superpixel $s mistura as duas metades');
    }
  });

  test('Grad-CAM normalizado pelo máximo e recortado por classe', () {
    // 2 classes, grade 1×2
    final cams = Float32List.fromList([1, 3, 0, 0]);
    final m = gradCamDaClasse(cams, 0, 1, 2);
    expect(m.valores, [closeTo(1 / 3, 1e-6), closeTo(1, 1e-6)]);
    expect(gradCamDaClasse(cams, 1, 1, 2).valores, [0, 0]); // mapa nulo não divide por zero
  });

  test('Overlay e LIME geram PNG válido', () {
    const w = 30, h = 20;
    final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 128);
    final png = sobreporMapa(rgb, w, h, MapaExplicacao(Float32List.fromList([0, 1, 0.5, 0.2]), 2, 2));
    expect(png.sublist(1, 4), 'PNG'.codeUnits);

    final lime = ResultadoLime(
      segmentos: Int32List.fromList(List.generate(16, (i) => i % 4 < 2 ? 0 : 1)),
      numSegmentos: 2,
      pesos: Float64List.fromList([0.3, -0.2]),
      r2: 0.5,
      lado: 4,
    );
    expect(desenharLime(rgb, w, h, lime).sublist(1, 4), 'PNG'.codeUnits);
  });
}
