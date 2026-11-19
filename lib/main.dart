import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/dashboard/dashboard_screen.dart';
import 'features/finding_migo/finding_migo_screen.dart';
import 'features/location/location_screen.dart';
import 'features/login/login_screen.dart';
import 'features/start/start_screen.dart';
import 'features/walkthrough/walkthrough_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFFFFF8F0),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const GoMigoApp());
}

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
      title: 'GoMigo',
      theme: ThemeData(
        useMaterial3: false,
        fontFamily: 'Nunito Sans',
        scaffoldBackgroundColor: const Color(0xFFFAEFE5),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA64E31)),
      ),
      home: Scaffold(body: _screen()),
    );
  }
}
