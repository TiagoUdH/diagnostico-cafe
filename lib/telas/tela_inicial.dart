import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ia/motor_ia.dart';
import 'tela_resultado.dart';

class TelaInicial extends StatefulWidget {
  const TelaInicial({super.key, required this.motor});

  final MotorIA motor;

  @override
  State<TelaInicial> createState() => _TelaInicialState();
}

class _TelaInicialState extends State<TelaInicial> {
  final _seletor = ImagePicker();
  bool _analisando = false;

  Future<void> _escolher(ImageSource origem) async {
    final XFile? arquivo;
    try {
      // 1600 px é mais que suficiente (o modelo usa 224×224) e deixa a decodificação bem mais rápida
      arquivo = await _seletor.pickImage(source: origem, maxWidth: 1600, maxHeight: 1600, imageQuality: 95);
    } catch (e) {
      _mostrarErro('Não foi possível abrir a ${origem == ImageSource.camera ? 'câmera' : 'galeria'}: $e');
      return;
    }
    if (arquivo == null || !mounted) return;

    setState(() => _analisando = true);
    try {
      final analise = await widget.motor.analisar(await arquivo.readAsBytes());
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelaResultado(motor: widget.motor, analise: analise)),
      );
    } catch (e) {
      _mostrarErro('Falha ao analisar a imagem: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _analisando = false);
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final config = widget.motor.config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico Café'),
        actions: [
          IconButton(
            tooltip: 'Sobre o modelo',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _mostrarSobre(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.eco, size: 72, color: tema.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Identifique doenças na folha do café',
              textAlign: TextAlign.center,
              style: tema.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Classes reconhecidas: ${config.classes.map((c) => c.nome).join(', ')}.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodyMedium?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            if (_analisando)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Analisando a folha...'),
                ],
              )
            else ...[
              FilledButton.icon(
                onPressed: () => _escolher(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Tirar foto'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _escolher(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Escolher da galeria'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
            ],
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dicas para uma boa foto', style: tema.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const _Dica(Icons.crop_free, 'Uma folha por foto, ocupando a maior parte da imagem.'),
                    const _Dica(Icons.wb_sunny_outlined, 'Luz natural e uniforme, sem sombras fortes.'),
                    const _Dica(Icons.center_focus_strong, 'Foto nítida, com a face da folha que tem os sintomas.'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Funciona sem internet: o modelo roda no próprio celular. É uma ferramenta de apoio e não '
              'substitui a avaliação de um engenheiro agrônomo.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall?.copyWith(color: tema.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarSobre(BuildContext context) {
    final config = widget.motor.config;
    final m = config.metricas;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sobre o modelo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Arquitetura: ${config.modelo}'),
            Text('Treinado no dataset: ${config.dataset}'),
            if (m?.acuracia != null) Text('Acurácia no teste: ${(m!.acuracia! * 100).toStringAsFixed(1)}%'),
            if (m?.f1Macro != null) Text('F1-Macro no teste: ${m!.f1Macro!.toStringAsFixed(3)}'),
            if (m?.nImagens != null) Text('Imagens de teste: ${m!.nImagens}'),
            const SizedBox(height: 8),
            Text('Confiança calibrada (Temperature Scaling, T = ${config.temperatura.toStringAsFixed(2)}).'),
            Text('Abaixo de ${(config.limiarAbstencao * 100).round()}% de confiança o app pede outra foto.'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
      ),
    );
  }
}

class _Dica extends StatelessWidget {
  const _Dica(this.icone, this.texto);

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}
