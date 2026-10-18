import 'package:flutter/material.dart';

import 'ia/motor_ia.dart';
import 'telas/tela_inicial.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppDiagnosticoCafe());
}

class AppDiagnosticoCafe extends StatefulWidget {
  const AppDiagnosticoCafe({super.key});

  @override
  State<AppDiagnosticoCafe> createState() => _AppDiagnosticoCafeState();
}

class _AppDiagnosticoCafeState extends State<AppDiagnosticoCafe> {
  late final Future<MotorIA> _motor = MotorIA.carregar();

  @override
  Widget build(BuildContext context) {
    const semente = Color(0xFF2E7D32);
    return MaterialApp(
      title: 'Diagnóstico Café',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: semente), useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: semente, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: FutureBuilder<MotorIA>(
        future: _motor,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _TelaErro(mensagem: '${snapshot.error}');
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return TelaInicial(motor: snapshot.data!);
        },
      ),
    );
  }
}

class _TelaErro extends StatelessWidget {
  const _TelaErro({required this.mensagem});

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Não foi possível carregar o modelo', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(mensagem.replaceFirst('Exception: ', ''), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
