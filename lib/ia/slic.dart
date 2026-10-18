import 'dart:math' as math;
import 'dart:typed_data';

/// Superpixels SLIC (Achanta et al., 2012) sobre uma imagem RGB [lado]×[lado].
///
/// O LIME dos notebooks usa o quickshift do scikit-image; o SLIC dá superpixels equivalentes (regiões de cor
/// homogênea e compactas) e é bem mais simples de implementar e rápido de rodar no celular.
///
/// Devolve o rótulo de cada pixel (0..[numSegmentos]-1), já com conectividade garantida.
({Int32List rotulos, int numSegmentos}) slic(
  Uint8List rgb,
  int lado, {
  int segmentosAlvo = 50,
  double compacidade = 10,
  int iteracoes = 10,
}) {
  final n = lado * lado;
  final lab = _rgbParaLab(rgb, n);
  final passo = math.max(1, math.sqrt(n / segmentosAlvo).round());

  // Centros numa grade regular, deslocados para o menor gradiente na vizinhança 3×3 (evita bordas)
  final centros = <List<double>>[]; // [L, a, b, x, y]
  for (var y = passo ~/ 2; y < lado; y += passo) {
    for (var x = passo ~/ 2; x < lado; x += passo) {
      var melhorX = x, melhorY = y;
      var menorGrad = double.infinity;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final cx = x + dx, cy = y + dy;
          if (cx < 1 || cy < 1 || cx >= lado - 1 || cy >= lado - 1) continue;
          final g = _gradiente(lab, lado, cx, cy);
          if (g < menorGrad) {
            menorGrad = g;
            melhorX = cx;
            melhorY = cy;
          }
        }
      }
      final i = (melhorY * lado + melhorX) * 3;
      centros.add([lab[i], lab[i + 1], lab[i + 2], melhorX.toDouble(), melhorY.toDouble()]);
    }
  }

  final rotulos = Int32List(n)..fillRange(0, n, -1);
  final distancias = Float64List(n);
  final m2 = compacidade * compacidade;
  final s2 = (passo * passo).toDouble();

  for (var it = 0; it < iteracoes; it++) {
    distancias.fillRange(0, n, double.infinity);
    for (var k = 0; k < centros.length; k++) {
      final c = centros[k];
      final x0 = math.max(0, (c[3] - passo).floor()), x1 = math.min(lado - 1, (c[3] + passo).ceil());
      final y0 = math.max(0, (c[4] - passo).floor()), y1 = math.min(lado - 1, (c[4] + passo).ceil());
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          final p = y * lado + x;
          final dl = lab[p * 3] - c[0], da = lab[p * 3 + 1] - c[1], db = lab[p * 3 + 2] - c[2];
          final dx = x - c[3], dy = y - c[4];
          final d = dl * dl + da * da + db * db + (dx * dx + dy * dy) / s2 * m2;
          if (d < distancias[p]) {
            distancias[p] = d;
            rotulos[p] = k;
          }
        }
      }
    }
    final somas = List.generate(centros.length, (_) => Float64List(6)); // L a b x y contagem
    for (var p = 0; p < n; p++) {
      final k = rotulos[p];
      if (k < 0) continue;
      final s = somas[k];
      s[0] += lab[p * 3];
      s[1] += lab[p * 3 + 1];
      s[2] += lab[p * 3 + 2];
      s[3] += p % lado;
      s[4] += p ~/ lado;
      s[5] += 1;
    }
    for (var k = 0; k < centros.length; k++) {
      final s = somas[k];
      if (s[5] == 0) continue;
      for (var j = 0; j < 5; j++) {
        centros[k][j] = s[j] / s[5];
      }
    }
  }

  return _garantirConectividade(rotulos, lado, n ~/ centros.length);
}

/// Reetiqueta em componentes conexos (4-vizinhança) e funde os fragmentos pequenos ao vizinho,
/// como no pós-processamento do SLIC original.
({Int32List rotulos, int numSegmentos}) _garantirConectividade(Int32List antigos, int lado, int tamanhoMedio) {
  final n = lado * lado;
  final minimo = math.max(1, tamanhoMedio ~/ 4);
  final novos = Int32List(n)..fillRange(0, n, -1);
  final fila = Int32List(n);
  const dx = [-1, 1, 0, 0];
  const dy = [0, 0, -1, 1];
  var proximo = 0;

  for (var inicio = 0; inicio < n; inicio++) {
    if (novos[inicio] >= 0) continue;
    // Rótulo de um vizinho já processado, para onde um fragmento pequeno será fundido
    var adjacente = -1;
    final ix = inicio % lado, iy = inicio ~/ lado;
    for (var d = 0; d < 4; d++) {
      final x = ix + dx[d], y = iy + dy[d];
      if (x >= 0 && y >= 0 && x < lado && y < lado && novos[y * lado + x] >= 0) {
        adjacente = novos[y * lado + x];
      }
    }

    novos[inicio] = proximo;
    var cabeca = 0, cauda = 0;
    fila[cauda++] = inicio;
    while (cabeca < cauda) {
      final p = fila[cabeca++];
      final px = p % lado, py = p ~/ lado;
      for (var d = 0; d < 4; d++) {
        final x = px + dx[d], y = py + dy[d];
        if (x < 0 || y < 0 || x >= lado || y >= lado) continue;
        final q = y * lado + x;
        if (novos[q] < 0 && antigos[q] == antigos[inicio]) {
          novos[q] = proximo;
          fila[cauda++] = q;
        }
      }
    }

    if (cauda < minimo && adjacente >= 0) {
      for (var i = 0; i < cauda; i++) {
        novos[fila[i]] = adjacente;
      }
    } else {
      proximo++;
    }
  }
  return (rotulos: novos, numSegmentos: proximo);
}

double _gradiente(Float64List lab, int lado, int x, int y) {
  double dist(int a, int b) {
    var s = 0.0;
    for (var c = 0; c < 3; c++) {
      final d = lab[a * 3 + c] - lab[b * 3 + c];
      s += d * d;
    }
    return s;
  }

  return dist(y * lado + x + 1, y * lado + x - 1) + dist((y + 1) * lado + x, (y - 1) * lado + x);
}

/// sRGB (D65) -> CIELAB.
Float64List _rgbParaLab(Uint8List rgb, int n) {
  double linear(int v) {
    final c = v / 255.0;
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  double f(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;

  final tabela = Float64List.fromList(List.generate(256, linear));
  final lab = Float64List(n * 3);
  for (var p = 0; p < n; p++) {
    final r = tabela[rgb[p * 3]], g = tabela[rgb[p * 3 + 1]], b = tabela[rgb[p * 3 + 2]];
    final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
    final fx = f(x), fy = f(y), fz = f(z);
    lab[p * 3] = 116 * fy - 16;
    lab[p * 3 + 1] = 500 * (fx - fy);
    lab[p * 3 + 2] = 200 * (fy - fz);
  }
  return lab;
}
