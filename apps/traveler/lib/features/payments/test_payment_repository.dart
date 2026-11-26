import 'package:supabase_flutter/supabase_flutter.dart';

class TestPaymentRepository {
  TestPaymentRepository(this.client);
  final SupabaseClient client;

  Future<({String status, Uri? checkout})> checkout(
    String booking,
    String action,
  ) async {
    final response = await client.functions.invoke(
      'paymongo-checkout',
      body: {'booking_id': booking, 'action': action},
    );
    final result = response.data as Map<String, dynamic>;
    final url = Uri.tryParse(result['checkout_url'] as String? ?? '');
    return (
      status: result['status'] as String,
      checkout:
          url != null &&
              url.scheme == 'https' &&
              url.host == 'checkout.paymongo.com' &&
              url.userInfo.isEmpty
          ? url
          : null,
    );
  }
}
