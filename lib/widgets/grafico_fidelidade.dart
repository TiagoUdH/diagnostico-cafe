import 'package:flutter/material.dart';

import '../ia/explicacoes.dart';

/// Curvas de Inserção e Remoção (probabilidade da classe × fração da imagem revelada/apagada).
class GraficoFidelidade extends StatelessWidget {
  const GraficoFidelidade({super.key, required this.resultado});

  final ResultadoFidelidade resultado;

  static const corInsercao = Color(0xFF2E7D32);
  static const corRemocao = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _PintorCurvas(resultado, cores.outlineVariant, cores.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Legenda(corInsercao, 'Inserção'),
            SizedBox(width: 16),
            _Legenda(corRemocao, 'Remoção'),
          ],
        ),
      ],
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda(this.cor, this.texto);

  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 16, height: 3, color: cor),
          const SizedBox(width: 6),
          Text(texto, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _PintorCurvas extends CustomPainter {
  _PintorCurvas(this.resultado, this.corGrade, this.corTexto);

  final ResultadoFidelidade resultado;
  final Color corGrade;
  final Color corTexto;

  @override
  void paint(Canvas canvas, Size size) {
    const margemEsq = 28.0, margemInf = 16.0;
    final area = Rect.fromLTWH(margemEsq, 4, size.width - margemEsq - 4, size.height - margemInf - 4);
    final grade = Paint()
      ..color = corGrade
      ..strokeWidth = 1;
    for (final v in [0.0, 0.5, 1.0]) {
      final y = area.bottom - v * area.height;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), grade);
      _texto(canvas, v.toStringAsFixed(1), Offset(0, y - 6));
    }
    _texto(canvas, '0%', Offset(area.left, area.bottom + 2));
    _texto(canvas, '100%', Offset(area.right - 28, area.bottom + 2));

    void curva(List<double> ys, Color cor) {
      if (ys.length < 2) return;
      final caminho = Path();
      for (var i = 0; i < ys.length; i++) {
        final p = Offset(area.left + i / (ys.length - 1) * area.width, area.bottom - ys[i].clamp(0, 1) * area.height);
        i == 0 ? caminho.moveTo(p.dx, p.dy) : caminho.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        caminho,
        Paint()
          ..color = cor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    curva(resultado.curvaInsercao, GraficoFidelidade.corInsercao);
    curva(resultado.curvaRemocao, GraficoFidelidade.corRemocao);
  }

  void _texto(Canvas canvas, String s, Offset o) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: 10, color: corTexto)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(_PintorCurvas old) => old.resultado != resultado;
}
