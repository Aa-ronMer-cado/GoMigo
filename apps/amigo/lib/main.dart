import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';

import 'navigation/amigo_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(goMigoSystemUiOverlayStyle);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const GoMigoAmigoApp());
}
