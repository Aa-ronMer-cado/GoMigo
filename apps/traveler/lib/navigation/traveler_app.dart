import 'package:flutter/material.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';

import '../features/authentication/login_screen.dart';
import '../features/discovery/finding_migo_screen.dart';
import '../features/home/dashboard_screen.dart';
import '../features/onboarding/location_screen.dart';
import '../features/onboarding/start_screen.dart';
import '../features/onboarding/walkthrough_screen.dart';

class GoMigoApp extends StatefulWidget {
  const GoMigoApp({super.key});

  @override
  State<GoMigoApp> createState() => _GoMigoAppState();
}

class _GoMigoAppState extends State<GoMigoApp> {
  int _step = 0;

  Widget _screen() {
    switch (_step) {
      case 0:
        return StartScreen(onContinue: () => setState(() => _step = 1));
      case 1:
        return LocationScreen(onContinue: () => setState(() => _step = 2));
      case 2:
        return LoginScreen(onContinue: () => setState(() => _step = 3));
      case 3:
        return WalkthroughScreen(onContinue: () => setState(() => _step = 4));
      case 4:
        return DashboardScreen(onFindMigo: () => setState(() => _step = 5));
      default:
        return FindingMigoScreen(onBack: () => setState(() => _step = 4));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GoMigo Traveler',
      theme: goMigoTheme(),
      home: Scaffold(body: _screen()),
    );
  }
}
