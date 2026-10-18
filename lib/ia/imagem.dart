import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Foto já decodificada em duas resoluções:
/// - [entradaRgb]: [lado]×[lado], exatamente o que o modelo vê. A foto inteira é redimensionada sem recorte
///   (bilinear), como o `image_dataset_from_directory` fez no treino, então a proporção pode ser distorcida.
/// - [exibicaoRgb]: [largura]×[altura] na proporção original, usada só para desenhar na tela. Os mapas de
///   explicação são esticados de volta para esta proporção, então as regiões coincidem com a foto real.
class ImagemPreparada {
  const ImagemPreparada({
    required this.entradaRgb,
    required this.lado,
    required this.exibicaoRgb,
    required this.largura,
    required this.altura,
  });

  final Uint8List entradaRgb;
  final int lado;
  final Uint8List exibicaoRgb;
  final int largura;
  final int altura;

  /// Tensor de entrada do modelo: float32 0-255 (o pré-processamento do backbone está dentro do .tflite).
  Float32List paraEntrada() => Float32List.fromList(entradaRgb.map((v) => v.toDouble()).toList());
}

ImagemPreparada prepararImagem(Uint8List bytes, int lado, {int maxLadoExibicao = 720}) {
  final decodificada = img.decodeImage(bytes);
  if (decodificada == null) {
    throw const FormatException('Não foi possível ler a imagem (formato não suportado).');
  }
  // Fotos de celular guardam a rotação no EXIF; sem isto a folha pode chegar deitada ao modelo.
  final foto = img.bakeOrientation(decodificada);

  final entrada = img.copyResize(foto, width: lado, height: lado, interpolation: img.Interpolation.linear);

  final escala = math.min(1.0, maxLadoExibicao / math.max(foto.width, foto.height));
  final exibicao = escala < 1
      ? img.copyResize(
          foto,
          width: (foto.width * escala).round(),
          height: (foto.height * escala).round(),
          interpolation: img.Interpolation.linear,
        )
      : foto;

  return ImagemPreparada(
    entradaRgb: _paraRgb8(entrada),
    lado: lado,
    exibicaoRgb: _paraRgb8(exibicao),
    largura: exibicao.width,
    altura: exibicao.height,
  );
}

Uint8List _paraRgb8(img.Image imagem) {
  final rgb = imagem.format == img.Format.uint8 && imagem.numChannels == 3
      ? imagem
      : imagem.convert(format: img.Format.uint8, numChannels: 3);
  return Uint8List.fromList(rgb.getBytes(order: img.ChannelOrder.rgb));
}

/// Borrão gaussiano separável sobre uma imagem RGB float [lado]×[lado], com o mesmo sigma que o
/// `cv2.GaussianBlur(img, (k, k), 0)` usado como "imagem sem informação" nos notebooks.
Float32List borrarGaussiano(Float32List rgb, int lado, int tamanhoKernel) {
  final raio = tamanhoKernel ~/ 2;
  final sigma = 0.3 * ((tamanhoKernel - 1) * 0.5 - 1) + 0.8;
  final kernel = Float64List(tamanhoKernel);
  var soma = 0.0;
  for (var i = 0; i < tamanhoKernel; i++) {
    final x = i - raio;
    kernel[i] = math.exp(-(x * x) / (2 * sigma * sigma));
    soma += kernel[i];
  }
  for (var i = 0; i < tamanhoKernel; i++) {
    kernel[i] /= soma;
  }

  // Borda refletida sem repetir o pixel da borda (BORDER_REFLECT_101, padrão do OpenCV)
  int refletir(int i) {
    if (i < 0) return -i;
    if (i >= lado) return 2 * lado - 2 - i;
    return i;
  }

  final temp = Float32List(rgb.length);
  final saida = Float32List(rgb.length);
  for (var y = 0; y < lado; y++) {
    for (var x = 0; x < lado; x++) {
      for (var c = 0; c < 3; c++) {
        var s = 0.0;
        for (var k = 0; k < tamanhoKernel; k++) {
          s += kernel[k] * rgb[(y * lado + refletir(x + k - raio)) * 3 + c];
        }
        temp[(y * lado + x) * 3 + c] = s;
      }
    }
  }
  for (var y = 0; y < lado; y++) {
    for (var x = 0; x < lado; x++) {
      for (var c = 0; c < 3; c++) {
        var s = 0.0;
        for (var k = 0; k < tamanhoKernel; k++) {
          s += kernel[k] * temp[(refletir(y + k - raio) * lado + x) * 3 + c];
        }
        saida[(y * lado + x) * 3 + c] = s;
      }
    }
  }
  return saida;
}
