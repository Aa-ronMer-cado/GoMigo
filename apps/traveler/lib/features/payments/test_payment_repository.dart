import 'package:supabase_flutter/supabase_flutter.dart';

const _testCheckoutHosts = {
  'checkout-staging.xendit.co',
  'dev.xen.to',
  'payments-web-sandbox.maya.ph',
  'payments-web-sandbox.paymaya.com',
};

class TestPaymentRepository {
  TestPaymentRepository(this.client);
  final SupabaseClient client;

  Future<({String status, Uri? checkout})> checkout(
    String booking,
    String action,
  ) async {
    var response = await client.functions.invoke(
      'xendit-checkout',
      body: {'booking_id': booking, 'action': action},
    );
    var result = response.data as Map<String, dynamic>;
    if (result['provider'] == 'maya') {
      response = await client.functions.invoke(
        'maya-checkout',
        body: {'booking_id': booking, 'action': action},
      );
      result = response.data as Map<String, dynamic>;
    }
    final url = Uri.tryParse(result['checkout_url'] as String? ?? '');
    return (
      status: result['status'] as String,
      checkout:
          url != null &&
              url.scheme == 'https' &&
              _testCheckoutHosts.contains(url.host) &&
              url.port == 443 &&
              url.userInfo.isEmpty
          ? url
          : null,
    );
  }
}
