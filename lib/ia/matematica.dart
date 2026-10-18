import 'dart:math' as math;
import 'dart:typed_data';

/// softmax(logits / temperatura), numericamente estável.
Float32List softmax(Float32List logits, {double temperatura = 1.0}) {
  var maximo = double.negativeInfinity;
  for (final v in logits) {
    maximo = math.max(maximo, v / temperatura);
  }
  final saida = Float32List(logits.length);
  var soma = 0.0;
  for (var i = 0; i < logits.length; i++) {
    final e = math.exp(logits[i] / temperatura - maximo);
    saida[i] = e;
    soma += e;
  }
  for (var i = 0; i < saida.length; i++) {
    saida[i] /= soma;
  }
  return saida;
}

int argmax(List<double> valores) {
  var melhor = 0;
  for (var i = 1; i < valores.length; i++) {
    if (valores[i] > valores[melhor]) melhor = i;
  }
  return melhor;
}

/// Área sob a curva pela regra do trapézio, com x igualmente espaçado em [0, 1].
double aucTrapezio(List<double> y) {
  if (y.length < 2) return 0;
  final passo = 1 / (y.length - 1);
  var area = 0.0;
  for (var i = 1; i < y.length; i++) {
    area += (y[i - 1] + y[i]) / 2 * passo;
  }
  return area;
}

/// Regressão Ridge ponderada com intercepto (equivale a sklearn Ridge(alpha, fit_intercept=True)
/// com sample_weight, usado pelo LIME). [x] tem [n] linhas e [d] colunas (row-major).
({Float64List coeficientes, double intercepto, double r2}) ridgePonderada(
  Float64List x,
  Float64List y,
  Float64List pesos,
  int n,
  int d, {
  double alpha = 1.0,
}) {
  var somaPesos = 0.0;
  var mediaY = 0.0;
  final mediaX = Float64List(d);
  for (var i = 0; i < n; i++) {
    somaPesos += pesos[i];
    mediaY += pesos[i] * y[i];
    for (var j = 0; j < d; j++) {
      mediaX[j] += pesos[i] * x[i * d + j];
    }
  }
  mediaY /= somaPesos;
  for (var j = 0; j < d; j++) {
    mediaX[j] /= somaPesos;
  }

  // Sistema (Xcᵀ W Xc + αI) β = Xcᵀ W yc, montado como matriz aumentada d × (d+1)
  final a = Float64List(d * (d + 1));
  for (var i = 0; i < n; i++) {
    final w = pesos[i];
    final yc = y[i] - mediaY;
    for (var j = 0; j < d; j++) {
      final xj = x[i * d + j] - mediaX[j];
      if (xj == 0) continue;
      final wx = w * xj;
      for (var k = j; k < d; k++) {
        a[j * (d + 1) + k] += wx * (x[i * d + k] - mediaX[k]);
      }
      a[j * (d + 1) + d] += wx * yc;
    }
  }
  for (var j = 0; j < d; j++) {
    for (var k = 0; k < j; k++) {
      a[j * (d + 1) + k] = a[k * (d + 1) + j];
    }
    a[j * (d + 1) + j] += alpha;
  }
  final beta = _resolverSistema(a, d);

  var intercepto = mediaY;
  for (var j = 0; j < d; j++) {
    intercepto -= beta[j] * mediaX[j];
  }

  // R² ponderado (o "score" que o LIME reporta)
  var ssRes = 0.0;
  var ssTot = 0.0;
  for (var i = 0; i < n; i++) {
    var pred = intercepto;
    for (var j = 0; j < d; j++) {
      pred += beta[j] * x[i * d + j];
    }
    ssRes += pesos[i] * (y[i] - pred) * (y[i] - pred);
    ssTot += pesos[i] * (y[i] - mediaY) * (y[i] - mediaY);
  }
  return (coeficientes: beta, intercepto: intercepto, r2: ssTot == 0 ? 0.0 : 1 - ssRes / ssTot);
}

/// Eliminação de Gauss com pivoteamento parcial sobre a matriz aumentada d × (d+1).
Float64List _resolverSistema(Float64List a, int d) {
  final larg = d + 1;
  for (var col = 0; col < d; col++) {
    var pivo = col;
    for (var lin = col + 1; lin < d; lin++) {
      if (a[lin * larg + col].abs() > a[pivo * larg + col].abs()) pivo = lin;
    }
    if (pivo != col) {
      for (var k = 0; k < larg; k++) {
        final t = a[col * larg + k];
        a[col * larg + k] = a[pivo * larg + k];
        a[pivo * larg + k] = t;
      }
    }
    final p = a[col * larg + col];
    if (p.abs() < 1e-12) continue;
    for (var lin = col + 1; lin < d; lin++) {
      final f = a[lin * larg + col] / p;
      if (f == 0) continue;
      for (var k = col; k < larg; k++) {
        a[lin * larg + k] -= f * a[col * larg + k];
      }
    }
  }
  final x = Float64List(d);
  for (var lin = d - 1; lin >= 0; lin--) {
    var s = a[lin * larg + d];
    for (var k = lin + 1; k < d; k++) {
      s -= a[lin * larg + k] * x[k];
    }
    final p = a[lin * larg + lin];
    x[lin] = p.abs() < 1e-12 ? 0 : s / p;
  }
  return x;
}
