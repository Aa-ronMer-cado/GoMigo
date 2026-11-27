import 'package:supabase_flutter/supabase_flutter.dart';

class DemoPayoutMethod {
  const DemoPayoutMethod(this.method, this.label);

  DemoPayoutMethod.fromJson(Map<String, dynamic> row)
    : this(row['method'] as String, row['label'] as String);

  final String method;
  final String label;

  static const options = {
    'gcash': 'GCash',
    'bank': 'Bank transfer',
    'maya': 'Maya',
  };

  String get name => options[method] ?? method;
}

class DemoTransaction {
  DemoTransaction.fromJson(Map<String, dynamic> row, {required this.withdrawal})
    : id = row[withdrawal ? 'id' : 'booking_id'] as String,
      amount = row['amount_centavos'] as int,
      status = row['status'] as String,
      date = DateTime.parse(
        row[withdrawal ? 'created_at' : 'completed_at'] as String,
      );

  final String id;
  final int amount;
  final String status;
  final DateTime date;
  final bool withdrawal;
}

class DemoEarnings {
  DemoEarnings.fromJson(Map<String, dynamic> row)
    : available = row['available_centavos'] as int,
      payoutMethod = row['payout_method'] == null
          ? null
          : DemoPayoutMethod.fromJson(
              row['payout_method'] as Map<String, dynamic>,
            ),
      transactions = [
        for (final item in row['earnings'] as List<dynamic>)
          DemoTransaction.fromJson(
            item as Map<String, dynamic>,
            withdrawal: false,
          ),
        for (final item in row['withdrawals'] as List<dynamic>)
          DemoTransaction.fromJson(
            item as Map<String, dynamic>,
            withdrawal: true,
          ),
      ]..sort((a, b) => b.date.compareTo(a.date));

  final int available;
  final DemoPayoutMethod? payoutMethod;
  final List<DemoTransaction> transactions;

  int get total => transactions
      .where((item) => !item.withdrawal)
      .fold(0, (sum, item) => sum + item.amount);
}

class AmigoEarningsRepository {
  AmigoEarningsRepository(this.client);

  final SupabaseClient client;

  Future<DemoEarnings> load() async => DemoEarnings.fromJson(
    await client.rpc<Map<String, dynamic>>('get_demo_amigo_earnings'),
  );

  Future<DemoPayoutMethod> savePayoutMethod(DemoPayoutMethod payout) async =>
      DemoPayoutMethod.fromJson(
        await client.rpc<Map<String, dynamic>>(
          'save_demo_amigo_payout_method',
          params: {'p_method': payout.method, 'p_label': payout.label},
        ),
      );

  Future<DemoTransaction> withdraw(int amount, String requestId) async =>
      DemoTransaction.fromJson(
        await client.rpc<Map<String, dynamic>>(
          'simulate_amigo_withdrawal',
          params: {'p_amount_centavos': amount, 'p_request_id': requestId},
        ),
        withdrawal: true,
      );
}

/// Parses a Philippine peso amount for an integer centavos RPC parameter.
int? parseWithdrawalCentavos(String value) {
  final amount = value.trim();
  if (!RegExp(r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$').hasMatch(amount)) {
    return null;
  }
  final parts = amount.replaceAll(',', '').split('.');
  final pesos = int.tryParse(parts.first);
  if (pesos == null || pesos > 21474836) return null;
  final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
  final centavos = pesos * 100 + fraction;
  return centavos > 0 && centavos <= 2147483647 ? centavos : null;
}
