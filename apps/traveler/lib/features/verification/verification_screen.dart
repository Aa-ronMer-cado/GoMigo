import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/verification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key, required this.client});
  final SupabaseClient client;

  @override
  Widget build(BuildContext context) => IdVerificationScreen(
    repository: IdVerificationRepository(client),
    onApproved: () => Navigator.maybePop(context),
  );
}
