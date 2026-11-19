import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/gomigo_shared_widgets.dart';

class AmigoHomeScreen extends StatelessWidget {
  const AmigoHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GoMigoBrand(),
                const SizedBox(height: 16),
                Text('Amigo', style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
