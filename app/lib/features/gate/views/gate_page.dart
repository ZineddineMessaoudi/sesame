import 'package:flutter/material.dart';

/// Écran principal (provisoire) : sera branché sur le `GateViewModel` à l'étape 3.
class GatePage extends StatelessWidget {
  const GatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sésame')),
      body: const Center(child: Text('État du portail : bientôt disponible')),
    );
  }
}
