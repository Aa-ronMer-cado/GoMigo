import 'package:flutter/material.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';

import '../features/home/amigo_home_screen.dart';

class GoMigoAmigoApp extends StatelessWidget {
  const GoMigoAmigoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GoMigo Amigo',
      theme: goMigoTheme(),
      home: const AmigoHomeScreen(),
    );
  }
}
