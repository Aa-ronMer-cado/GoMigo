import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ThemeData goMigoTheme() => ThemeData(
      useMaterial3: false,
      fontFamily: 'Nunito Sans',
      scaffoldBackgroundColor: const Color(0xFFFAEFE5),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA64E31)),
    );

const goMigoSystemUiOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  systemNavigationBarColor: Color(0xFFFFF8F0),
  systemNavigationBarIconBrightness: Brightness.dark,
);
