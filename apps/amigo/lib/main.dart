import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'navigation/amigo_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(goMigoSystemUiOverlayStyle);
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  SupabaseClient? client;
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      final supabase = await Supabase.initialize(
        url: url,
        publishableKey: key,
        authOptions: FlutterAuthClientOptions(
          localStorage: SharedPreferencesLocalStorage(
            persistSessionKey: 'gomigo-amigo-${Uri.parse(url).host}-session',
          ),
        ),
      );
      client = supabase.client;
    } catch (_) {
      // The login screen reports that account services are unavailable.
    }
  }
  runApp(GoMigoAmigoApp(client: client));
}
