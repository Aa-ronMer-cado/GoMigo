import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traveler/features/payments/test_payment_repository.dart';

class _TestClient extends Fake implements SupabaseClient {
  @override
  final _TestFunctions functions = _TestFunctions();
}

class _TestFunctions extends Fake implements FunctionsClient {
  String? checkoutUrl;
  bool legacyMaya = false;
  final calls = <String>[];

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Object? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
    Future<void>? abortSignal,
  }) async {
    calls.add(functionName);
    expect(
      functionName,
      legacyMaya && functionName == 'maya-checkout'
          ? 'maya-checkout'
          : 'xendit-checkout',
    );
    expect(method, HttpMethod.post);
    expect(body, {'booking_id': 'demo-booking', 'action': 'open'});
    return FunctionResponse(
      status: 200,
      data: {
        'provider': legacyMaya ? 'maya' : 'xendit',
        'status': 'pending',
        'checkout_url': checkoutUrl,
      },
    );
  }
}

void main() {
  test('opens only HTTPS test checkout links', () async {
    final client = _TestClient();
    final repository = TestPaymentRepository(client);
    const host = 'checkout-staging.xendit.co';
    client.functions.checkoutUrl = 'https://$host/v2/checkout?demo=1';

    final checkout = await repository.checkout('demo-booking', 'open');
    expect(checkout.status, 'pending');
    expect(checkout.checkout, Uri.parse(client.functions.checkoutUrl!));

    client.functions.checkoutUrl = 'https://dev.xen.to/test-checkout';
    expect(
      (await repository.checkout('demo-booking', 'open')).checkout,
      Uri.parse(client.functions.checkoutUrl!),
    );

    for (final url in [
      'http://$host/checkout',
      'https://checkout.xendit.co/checkout',
      'https://$host.example.invalid/checkout',
      'https://user@$host/checkout',
      'https://$host:8080/checkout',
    ]) {
      client.functions.checkoutUrl = url;
      expect(
        (await repository.checkout('demo-booking', 'open')).checkout,
        null,
      );
    }
  });

  test(
    'keeps existing Maya test checkouts available for reconciliation',
    () async {
      final client = _TestClient();
      client.functions.legacyMaya = true;
      client.functions.checkoutUrl =
          'https://payments-web-sandbox.maya.ph/checkout/fixture';
      final checkout = await TestPaymentRepository(
        client,
      ).checkout('demo-booking', 'open');
      expect(checkout.checkout, Uri.parse(client.functions.checkoutUrl!));
      expect(client.functions.calls, ['xendit-checkout', 'maya-checkout']);
    },
  );
}
