import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'explicacoes.dart';

Uint8List codificarPng(Uint8List rgb, int largura, int altura) {
  final imagem = img.Image.fromBytes(width: largura, height: altura, bytes: rgb.buffer, numChannels: 3);
  return img.encodePng(imagem, level: 1);
}

/// Colormap "jet" do matplotlib (o mesmo usado nos overlays de Grad-CAM dos notebooks).
(double, double, double) corJet(double v) {
  double canal(double centro) => (1.5 - (4 * v - centro).abs()).clamp(0.0, 1.0);
  return (canal(3), canal(2), canal(1));
}

/// Sobrepõe o [mapa] (esticado com interpolação bilinear) à foto: `jet * alpha + foto * (1 - alpha)`.
Uint8List sobreporMapa(Uint8List rgb, int largura, int altura, MapaExplicacao mapa, {double alpha = 0.45}) {
  final saida = Uint8List(rgb.length);
  for (var y = 0; y < altura; y++) {
    final my = ((y + 0.5) * mapa.altura / altura - 0.5).clamp(0.0, mapa.altura - 1.0);
    final y0 = my.floor(), y1 = math.min(y0 + 1, mapa.altura - 1);
    final fy = my - y0;
    for (var x = 0; x < largura; x++) {
      final mx = ((x + 0.5) * mapa.largura / largura - 0.5).clamp(0.0, mapa.largura - 1.0);
      final x0 = mx.floor(), x1 = math.min(x0 + 1, mapa.largura - 1);
      final fx = mx - x0;
      double m(int r, int c) => mapa.valores[r * mapa.largura + c];
      final v = (m(y0, x0) * (1 - fx) + m(y0, x1) * fx) * (1 - fy) + (m(y1, x0) * (1 - fx) + m(y1, x1) * fx) * fy;
      final (r, g, b) = corJet(v);
      final i = (y * largura + x) * 3;
      saida[i] = (r * 255 * alpha + rgb[i] * (1 - alpha)).round();
      saida[i + 1] = (g * 255 * alpha + rgb[i + 1] * (1 - alpha)).round();
      saida[i + 2] = (b * 255 * alpha + rgb[i + 2] * (1 - alpha)).round();
    }
  }
  return codificarPng(saida, largura, altura);
}

/// Superpixels que mais favorecem a classe em verde e os que mais pesam contra em vermelho, com o contorno
/// de todos os superpixels -- equivalente ao `mark_boundaries` + `get_image_and_mask` dos notebooks.
Uint8List desenharLime(
  Uint8List rgb,
  int largura,
  int altura,
  ResultadoLime lime, {
  int numPositivos = 6,
  int numNegativos = 4,
}) {
  final ordem = List.generate(lime.numSegmentos, (i) => i)
    ..sort((a, b) => lime.pesos[b].compareTo(lime.pesos[a]));
  final cor = Int8List(lime.numSegmentos); // 1 = a favor, -1 = contra
  for (final s in ordem.take(numPositivos)) {
    if (lime.pesos[s] > 0) cor[s] = 1;
  }
  for (final s in ordem.reversed.take(numNegativos)) {
    if (lime.pesos[s] < 0) cor[s] = -1;
  }

  int segmento(int x, int y) {
    final sx = math.min(lime.lado - 1, x * lime.lado ~/ largura);
    final sy = math.min(lime.lado - 1, y * lime.lado ~/ altura);
    return lime.segmentos[sy * lime.lado + sx];
  }

  final saida = Uint8List(rgb.length);
  for (var y = 0; y < altura; y++) {
    for (var x = 0; x < largura; x++) {
      final s = segmento(x, y);
      final i = (y * largura + x) * 3;
      final borda = (x + 1 < largura && segmento(x + 1, y) != s) || (y + 1 < altura && segmento(x, y + 1) != s);
      if (borda) {
        saida[i] = 255;
        saida[i + 1] = 235;
        saida[i + 2] = 59;
        continue;
      }
      final (r, g, b) = switch (cor[s]) {
        1 => (46, 204, 64),
        -1 => (231, 76, 60),
        _ => (-1, -1, -1),
      };
      if (r < 0) {
        saida[i] = (rgb[i] * 0.55).round();
        saida[i + 1] = (rgb[i + 1] * 0.55).round();
        saida[i + 2] = (rgb[i + 2] * 0.55).round();
      } else {
        saida[i] = (rgb[i] * 0.5 + r * 0.5).round();
        saida[i + 1] = (rgb[i + 1] * 0.5 + g * 0.5).round();
        saida[i + 2] = (rgb[i + 2] * 0.5 + b * 0.5).round();
      }
    }
  }
  return codificarPng(saida, largura, altura);
}
