import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/gomigo_shared_widgets.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onContinue,
      child: const ColoredBox(
        color: Color(0xFFFAEFE5),
        child: Center(child: GoMigoBrand()),
      ),
    );
  }
}
