import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/authentication/account_repository.dart';
import '../features/authentication/login_screen.dart';
import '../features/booking/booking_detail_screen.dart';
import '../features/booking/booking_form_screen.dart';
import '../features/booking/booking_history_screen.dart';
import '../features/booking/booking_repository.dart';
import '../features/discovery/discovery_repository.dart';
import '../features/discovery/finding_migo_screen.dart';
import '../features/home/dashboard_screen.dart';
import '../features/onboarding/location_screen.dart';
import '../features/onboarding/start_screen.dart';
import '../features/onboarding/walkthrough_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/verification/verification_screen.dart';
import 'traveler_ui.dart';

class GoMigoApp extends StatefulWidget {
  const GoMigoApp({super.key, this.client});
  final SupabaseClient? client;

  @override
  State<GoMigoApp> createState() => _GoMigoAppState();
}

class _GoMigoAppState extends State<GoMigoApp> {
  StreamSubscription<AuthState>? _subscription;
  String? _user;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _user = widget.client?.auth.currentSession?.user.id;
    _subscription = widget.client?.auth.onAuthStateChange.listen(
      (event) {
        final user = event.session?.user.id;
        if (mounted && user != _user)
          setState(() {
            _user = user;
            _step = 2;
          });
      },
      onError: (Object _) {
        // Keep the current screen during a transient token refresh failure.
      },
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Widget _guest() => PopScope(
    canPop: _step == 0,
    onPopInvokedWithResult: (popped, _) {
      if (!popped && _step > 0) setState(() => _step--);
    },
    child: Scaffold(
      body: switch (_step) {
        0 => StartScreen(onContinue: () => setState(() => _step = 1)),
        1 => LocationScreen(onContinue: () => setState(() => _step = 2)),
        _ => LoginScreen(
          account: widget.client == null
              ? null
              : AccountRepository(widget.client!),
        ),
      },
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    key: ValueKey(_user),
    debugShowCheckedModeBanner: false,
    title: 'GoMigo Traveler',
    theme: goMigoTheme(),
    home: _user == null
        ? _guest()
        : _TravelerHome(client: widget.client!, user: _user!),
  );
}

class _TravelerHome extends StatefulWidget {
  const _TravelerHome({required this.client, required this.user});
  final SupabaseClient client;
  final String user;

  @override
  State<_TravelerHome> createState() => _TravelerHomeState();
}

class _TravelerHomeState extends State<_TravelerHome> {
  late final _account = AccountRepository(widget.client);
  late final _booking = BookingRepository(widget.client);
  late final _discovery = DiscoveryRepository(widget.client);
  late Future<({bool traveler, bool seen})> _state = _load();
  final _prefs = SharedPreferencesAsync();
  String get _walkthroughKey => 'traveler_walkthrough_${widget.user}';
  bool _walkthroughDone = false;
  bool _replay = false;
  int _tab = 0;
  bool _checking = false;

  Future<({bool traveler, bool seen})> _load() async {
    final profile = await _account.profile();
    var seen = false;
    try {
      seen = await _prefs.getBool(_walkthroughKey) ?? false;
    } catch (_) {
      // The walkthrough can still be completed for this session.
    }
    return (traveler: profile['role'] == 'traveler', seen: seen);
  }

  void _completeWalkthrough() {
    setState(() {
      _walkthroughDone = true;
      _replay = false;
    });
    unawaited(_prefs.setBool(_walkthroughKey, true).catchError((Object _) {}));
  }

  Future<void> _request(BuildContext source, BookingRow amigo) async {
    if (_checking) return;
    _checking = true;
    try {
      final verified = await _booking.verified();
      if (!source.mounted) return;
      final navigator = Navigator.of(source);
      if (!verified) {
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => VerificationScreen(client: widget.client),
          ),
        );
        return;
      }
      final booking = await navigator.push<BookingRow>(
        MaterialPageRoute(
          builder: (_) => BookingFormScreen(repository: _booking, amigo: amigo),
        ),
      );
      if (booking != null && navigator.mounted) {
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => BookingDetailScreen(
              repository: _booking,
              booking: booking,
              amigo: amigo,
            ),
          ),
        );
      }
    } catch (_) {
      if (source.mounted)
        notifyTraveler(
          source,
          'Could not open booking. Check your connection and try again.',
        );
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _state,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return Scaffold(
          body: TravelerError(
            'Could not load your Traveler account.',
            onRetry: () => setState(() => _state = _load()),
          ),
        );
      final state = snapshot.data;
      if (state == null)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (!state.traveler)
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('This account belongs to the Amigo app.'),
                TextButton(
                  onPressed: () async {
                    try {
                      await _account.logout();
                    } catch (_) {
                      if (context.mounted)
                        notifyTraveler(
                          context,
                          'Could not log out. Try again.',
                        );
                    }
                  },
                  child: const Text('Log Out'),
                ),
              ],
            ),
          ),
        );
      if (_replay || (!_walkthroughDone && !state.seen)) {
        return Scaffold(
          body: SafeArea(
            child: WalkthroughScreen(onContinue: _completeWalkthrough),
          ),
        );
      }
      final page = switch (_tab) {
        1 => FindingMigoScreen(
          repository: _discovery,
          request: _request,
          onBack: () => setState(() => _tab = 0),
        ),
        2 => BookingHistoryScreen(
          key: const ValueKey('history'),
          repository: _booking,
        ),
        3 => BookingHistoryScreen(
          key: const ValueKey('messages'),
          repository: _booking,
          messages: true,
        ),
        4 => ProfileScreen(
          account: _account,
          onWalkthrough: () => setState(() => _replay = true),
        ),
        _ => DashboardScreen(
          onFindMigo: () => setState(() => _tab = 1),
          onBookings: () => setState(() => _tab = 2),
        ),
      };
      return PopScope(
        canPop: _tab == 0,
        onPopInvokedWithResult: (popped, _) {
          if (!popped && _tab != 0) setState(() => _tab = 0);
        },
        child: Scaffold(
          body: page,
          bottomNavigationBar: _TravelerNavigation(
            tab: _tab,
            onSelect: (tab) => setState(() => _tab = tab),
          ),
        ),
      );
    },
  );
}

class _TravelerNavigation extends StatelessWidget {
  const _TravelerNavigation({required this.tab, required this.onSelect});
  final int tab;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Home', 'finding_home'),
      ('Find a Migo', 'finding_calendar_plus'),
      ('Booking history', 'finding_history'),
      ('Messages', ''),
      ('Profile', 'finding_user'),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: travelerCream,
        border: Border(top: BorderSide(color: travelerBorder)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (index, entry) in items.indexed)
                Semantics(
                  selected: index == tab,
                  child: IconButton(
                    tooltip: entry.$1,
                    onPressed: () => onSelect(index),
                    icon: entry.$2.isEmpty
                        ? Icon(
                            Icons.chat_bubble_outline,
                            color: index == tab ? travelerRust : travelerInk,
                          )
                        : TravelerAsset(
                            entry.$2,
                            color: index == tab ? travelerRust : travelerInk,
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
