import 'package:supabase_flutter/supabase_flutter.dart';

class AccountRepository {
  AccountRepository(this.client);

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
        'display_name': name,
        if (phone != null && phone.isNotEmpty) 'contact_phone': phone,
      },
    );
    return response.session != null;
  }

  Future<Map<String, dynamic>> profile() => client
      .from('profiles')
      .select()
      .eq('id', client.auth.currentUser!.id)
      .single();

  Future<void> updateName(String name) async {
    await client
        .from('profiles')
        .update({'display_name': name})
        .eq('id', client.auth.currentUser!.id);
  }

  Future<void> logout() => client.auth.signOut();
}
