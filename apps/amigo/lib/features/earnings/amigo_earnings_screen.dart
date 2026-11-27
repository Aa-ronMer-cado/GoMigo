import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../booking/booking_widgets.dart';
import 'amigo_earnings_repository.dart';

class AmigoEarningsScreen extends StatefulWidget {
  const AmigoEarningsScreen({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<AmigoEarningsScreen> createState() => _AmigoEarningsScreenState();
}

class _AmigoEarningsScreenState extends State<AmigoEarningsScreen> {
  late final _repository = AmigoEarningsRepository(widget.client);
  late Future<DemoEarnings> _earnings = _repository.load();

  Future<void> _reload() async {
    setState(() => _earnings = _repository.load());
    try {
      await _earnings;
    } catch (_) {
      // FutureBuilder displays the load error.
    }
  }

  Future<void> _open(Widget screen) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (context) => screen));
    if (changed == true && mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: bookingHeader(context, 'Earnings'),
    body: FutureBuilder(
      future: _earnings,
      builder: (context, state) {
        if (state.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final earnings = state.data;
        if (state.hasError || earnings == null) {
          return Center(
            child: BookingRetry('Could not load earnings.', onRetry: _reload),
          );
        }
        final payout = earnings.payoutMethod;
        return SafeArea(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _EarningsBalance(earnings),
                const SizedBox(height: 9),
                const Text(
                  'Demo only. A Maya sandbox payment does not transfer money to an Amigo.',
                  style: TextStyle(color: bookingMuted),
                ),
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: payout == null || earnings.available <= 0
                          ? null
                          : () => _open(
                              _WithdrawEarnings(
                                repository: _repository,
                                earnings: earnings,
                              ),
                            ),
                      style: bookingPrimaryStyle(),
                      child: const Text('Withdraw simulated earnings'),
                    ),
                    if (payout == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Set up a demo payout method to withdraw.',
                          style: TextStyle(color: bookingMuted),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => _open(
                        _PayoutSetup(repository: _repository, initial: payout),
                      ),
                      style: bookingOutlineStyle(),
                      child: Text(
                        payout == null
                            ? 'Set up demo payout'
                            : 'Wallet & payout setup',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 23),
                Text(
                  'Transaction history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (earnings.transactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Completed trips with a confirmed test payment appear here.',
                    ),
                  ),
                for (final transaction in earnings.transactions) ...[
                  const SizedBox(height: 8),
                  _TransactionTile(transaction),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _EarningsBalance extends StatelessWidget {
  const _EarningsBalance(this.earnings);

  final DemoEarnings earnings;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: bookingGradient,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Available simulated balance',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        Text(
          bookingPesos(earnings.available),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '${bookingPesos(earnings.total)} total simulated earnings',
          style: const TextStyle(color: Colors.white),
        ),
      ],
    ),
  );
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile(this.transaction);

  final DemoTransaction transaction;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    margin: EdgeInsets.zero,
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: bookingSage,
            foregroundColor: bookingInk,
            child: Icon(
              transaction.withdrawal ? Icons.north_east : Icons.south_west,
              size: 18,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.withdrawal ? 'Withdrawal' : 'Trip earnings',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${bookingDate(context, transaction.date)} · ${transaction.status == 'simulated' ? 'Simulated' : bookingStatus(transaction.status)}',
                  style: const TextStyle(fontSize: 12, color: bookingMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              bookingPesos(
                transaction.withdrawal
                    ? -transaction.amount
                    : transaction.amount,
              ),
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: bookingInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PayoutSetup extends StatefulWidget {
  const _PayoutSetup({required this.repository, required this.initial});

  final AmigoEarningsRepository repository;
  final DemoPayoutMethod? initial;

  @override
  State<_PayoutSetup> createState() => _PayoutSetupState();
}

class _PayoutSetupState extends State<_PayoutSetup> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.initial?.label);
  late String? _method = widget.initial?.method;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final method = _method;
    if (_saving || method == null || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.savePayoutMethod(
        DemoPayoutMethod(method, _label.text.trim()),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = bookingError(
            error,
            'Could not save the payout method. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: bookingHeader(context, 'Wallet & Payout Setup'),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
            children: [
              Text(
                'Payout method',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              const Text(
                'Choose a demo destination and enter a fictional label. Keep your account details private.',
                style: TextStyle(color: bookingMuted),
              ),
              const SizedBox(height: 17),
              for (final entry in DemoPayoutMethod.options.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: BookingRadioTile(
                    title: entry.value,
                    selected: entry.key == _method,
                    onTap: _saving
                        ? null
                        : () => setState(() => _method = entry.key),
                  ),
                ),
              const SizedBox(height: 9),
              TextFormField(
                controller: _label,
                enabled: !_saving,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: bookingInput(
                  'e.g. My demo wallet',
                ).copyWith(labelText: 'Fictional label'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter a fictional label.'
                    : null,
              ),
              const SizedBox(height: 11),
              if (_error case final error?) _FormNotice(error),
              if (_saving) const LinearProgressIndicator(),
              const SizedBox(height: 4),
              FilledButton(
                onPressed: _saving || _method == null ? null : _save,
                style: bookingPrimaryStyle(),
                child: const Text('Save demo payout method'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WithdrawEarnings extends StatefulWidget {
  const _WithdrawEarnings({required this.repository, required this.earnings});

  final AmigoEarningsRepository repository;
  final DemoEarnings earnings;

  @override
  State<_WithdrawEarnings> createState() => _WithdrawEarningsState();
}

class _WithdrawEarningsState extends State<_WithdrawEarnings> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  ({int amount, String id})? _pending;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _withdraw() async {
    if (_busy || !_form.currentState!.validate()) return;
    final amount = parseWithdrawalCentavos(_amount.text)!;
    final intent = _pending?.amount == amount
        ? _pending!
        : (amount: amount, id: const Uuid().v4());
    setState(() {
      _pending = intent;
      _busy = true;
      _error = null;
    });
    try {
      final transaction = await widget.repository.withdraw(
        intent.amount,
        intent.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Simulated withdrawal recorded'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/figma/booking/receipt_halo.png',
                width: 100,
                height: 95,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 9),
              Text(bookingPesos(transaction.amount)),
              const Text('No money was transferred.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = bookingError(
            error,
            'Could not confirm the withdrawal. Retry with the same amount.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payout = widget.earnings.payoutMethod!;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: bookingHeader(context, 'Withdraw Earnings'),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
              children: [
                _EarningsBalance(widget.earnings),
                const SizedBox(height: 19),
                Text(
                  'Demo destination',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${payout.name} · ${payout.label}',
                  style: const TextStyle(color: bookingMuted),
                ),
                const SizedBox(height: 19),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  enabled: !_busy,
                  decoration: bookingInput(
                    '0.00',
                  ).copyWith(labelText: 'Amount in pesos', prefixText: '₱ '),
                  validator: (input) {
                    final amount = parseWithdrawalCentavos(input ?? '');
                    if (amount == null) {
                      return 'Enter a positive amount with up to two decimals.';
                    }
                    if (amount > widget.earnings.available) {
                      return 'Enter an amount within your simulated balance.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 13),
                const Text(
                  'This withdrawal updates the demo balance only.',
                  style: TextStyle(color: bookingMuted),
                ),
                const SizedBox(height: 10),
                if (_error case final error?) _FormNotice(error),
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: _busy ? null : _withdraw,
                  style: bookingPrimaryStyle(),
                  child: const Text('Simulate withdrawal'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormNotice extends StatelessWidget {
  const _FormNotice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}
