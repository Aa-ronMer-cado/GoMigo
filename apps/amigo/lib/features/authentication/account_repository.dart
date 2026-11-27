import 'package:supabase_flutter/supabase_flutter.dart';

class AmigoAccountRepository {
  const AmigoAccountRepository(this.client);

  final SupabaseClient client;

  Future<bool> authenticate({
    required String email,
    required String password,
    String? name,
    String? phone,
  }) async {
    if (name == null) {
      await client.auth.signInWithPassword(email: email, password: password);
      return true;
    }
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'gomigo_role': 'amigo',
        'display_name': name,
        if (phone != null && phone.isNotEmpty) 'contact_phone': phone,
      },
    );
    return response.session != null;
  }

  Future<Map<String, dynamic>> profile() => client
      .from('profiles')
      .select('display_name,role')
      .eq('id', client.auth.currentUser!.id)
      .single();

  Future<void> logout() => client.auth.signOut();
}
