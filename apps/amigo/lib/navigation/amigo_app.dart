import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gomigo_design_system/gomigo_design_system.dart';
import 'package:gomigo_shared_widgets/meetup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/authentication/account_repository.dart';
import '../features/authentication/login_screen.dart';
import '../features/booking/amigo_booking_detail_screen.dart';
import '../features/booking/amigo_booking_history_screen.dart';
import '../features/booking/amigo_booking_repository.dart';
import '../features/chat/chat_repository.dart';
import '../features/chat/chat_screen.dart';
import '../features/earnings/amigo_earnings_screen.dart';
import '../features/home/amigo_home_screen.dart';
import '../features/onboarding/location_screen.dart';
import '../features/onboarding/start_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/profile_repository.dart';
import '../features/profile/profile_screen.dart';
import '../features/session/session_controls.dart';
import '../features/session/session_repository.dart';
import '../features/session/trip_review_screen.dart';
import '../features/verification/verification_repository.dart';
import '../features/verification/verification_screen.dart';
import 'amigo_ui.dart';

class GoMigoAmigoApp extends StatefulWidget {
  const GoMigoAmigoApp({super.key, this.client});
  final SupabaseClient? client;

  @override
  State<GoMigoAmigoApp> createState() => _GoMigoAmigoAppState();
}

class _GoMigoAmigoAppState extends State<GoMigoAmigoApp> {
  StreamSubscription<AuthState>? _auth;
  String? _userId;
  String? _accountNotice;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _userId = widget.client?.auth.currentSession?.user.id;
    _auth = widget.client?.auth.onAuthStateChange.listen(
      (event) {
        final id = event.session?.user.id;
        if (mounted && id != _userId) {
          setState(() {
            _userId = id;
            if (id != null) _accountNotice = null;
            _step = 2;
          });
        }
      },
      onError: (Object _) {
        // Keep the active screen during a temporary auth refresh failure.
      },
    );
  }

  @override
  void dispose() {
    unawaited(_auth?.cancel());
    super.dispose();
  }

  Future<void> _rejectAccount(String user) async {
    final auth = widget.client!.auth;
    if (!mounted || auth.currentUser?.id != user) return;
    _accountNotice = 'Sign in with an Amigo account.';
    await auth.signOut();
  }

  Widget _guest(SupabaseClient? client) => PopScope(
    canPop: _step == 0,
    onPopInvokedWithResult: (popped, _) {
      if (!popped && _step > 0) setState(() => _step--);
    },
    child: Scaffold(
      body: switch (_step) {
        0 => AmigoStartScreen(onContinue: () => setState(() => _step = 1)),
        1 => AmigoLocationScreen(onContinue: () => setState(() => _step = 2)),
        _ => AmigoLoginScreen(
          accountNotice: _accountNotice,
          account: client == null ? null : AmigoAccountRepository(client),
        ),
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final user = _userId;
    return MaterialApp(
      key: ValueKey(user),
      debugShowCheckedModeBanner: false,
      title: 'GoMigo Amigo',
      theme: goMigoTheme(),
      home: client == null || user == null
          ? _guest(client)
          : _AmigoAccess(
              client: client,
              user: user,
              onWrongAccount: _rejectAccount,
            ),
    );
  }
}

typedef _Access = ({
  bool isAmigo,
  Map<String, dynamic>? approval,
  Map<String, dynamic>? profile,
});

class _AmigoAccess extends StatefulWidget {
  const _AmigoAccess({
    required this.client,
    required this.user,
    required this.onWrongAccount,
  });
  final SupabaseClient client;
  final String user;
  final Future<void> Function(String user) onWrongAccount;

  @override
  State<_AmigoAccess> createState() => _AmigoAccessState();
}

class _AmigoAccessState extends State<_AmigoAccess> {
  late final _account = AmigoAccountRepository(widget.client);
  late final _verification = AmigoVerificationRepository(widget.client);
  late final _profiles = AmigoProfileRepository(widget.client);
  late Future<_Access> _access = _load().timeout(const Duration(seconds: 15));
  bool _finishedVerification = false;

  Future<_Access> _load() async {
    final account = await _account.profile();
    if (account['role'] != 'amigo') {
      try {
        await widget.onWrongAccount(widget.user);
      } catch (_) {
        // The denied screen lets the user retry sign-out.
      }
      return (isAmigo: false, approval: null, profile: null);
    }
    final approval = await _verification.approved();
    final profile = approval == null ? null : await _profiles.profile();
    return (isAmigo: true, approval: approval, profile: profile);
  }

  void _reload() {
    if (!mounted) return;
    final access = _load().timeout(const Duration(seconds: 15));
    setState(() {
      _access = access;
    });
  }

  Future<void> _logout() async {
    try {
      await _account.logout();
    } catch (_) {
      if (mounted) amigoNotice(context, 'Could not sign out. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _access,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final access = snapshot.data;
      if (snapshot.hasError || access == null) {
        return _message('Could not load your Amigo account.', retry: true);
      }
      if (!access.isAmigo) {
        return _message('Sign in with an Amigo account.');
      }
      final profile = access.profile;
      final approval = access.approval;
      final name = approval?['reviewed_display_name'] as String?;
      final gender = approval?['reviewed_gender'] as String?;
      final needsSetup =
          profile == null ||
          (name != null && profile['onboarding_completed_at'] == null);
      if (approval == null ||
          (needsSetup &&
              (!_finishedVerification || name == null || gender == null))) {
        return AmigoVerificationScreen(
          repository: _verification,
          initialSubmission: approval,
          onApproved: () {
            _finishedVerification = true;
            _reload();
          },
          onLogout: _logout,
        );
      }
      if (needsSetup) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (popped, _) {
            if (!popped) setState(() => _finishedVerification = false);
          },
          child: AmigoEditProfileScreen(
            repository: _profiles,
            profile: profile,
            name: name!,
            gender: gender!,
            creating: true,
            onSaved: _reload,
            onLogout: _logout,
          ),
        );
      }
      return _AmigoWorkspace(
        account: _account,
        amigoId: profile['id'] as String,
        amigoName: profile['display_name'] as String,
      );
    },
  );

  Widget _message(String message, {bool retry = false}) => Scaffold(
    appBar: amigoHeader('GoMigo Amigo'),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (retry)
              TextButton(onPressed: _reload, child: const Text('Try again')),
            TextButton(onPressed: _logout, child: const Text('Sign out')),
          ],
        ),
      ),
    ),
  );
}

class _AmigoWorkspace extends StatefulWidget {
  const _AmigoWorkspace({
    required this.account,
    required this.amigoId,
    required this.amigoName,
  });
  final AmigoAccountRepository account;
  final String amigoId;
  final String amigoName;

  @override
  State<_AmigoWorkspace> createState() => _AmigoWorkspaceState();
}

class _AmigoWorkspaceState extends State<_AmigoWorkspace> {
  SupabaseClient get _client => widget.account.client;
  late final _bookings = AmigoBookingRepository(_client, widget.amigoId);
  late var _name = widget.amigoName;
  int _tab = 0;

  void _tabTo(int tab) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _tab = tab);
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _details(AmigoBooking booking) => _open(
    AmigoBookingDetailScreen(
      repository: _bookings,
      booking: booking,
      onOpenChat: _chat,
      onOpenMap: _meetup,
      onOpenSession: (booking) => _meetup(booking, showSessionFirst: true),
      onOpenReview: _review,
    ),
  );

  void _chat(AmigoBooking booking) => _open(
    AmigoChatScreen(
      repository: AmigoChatRepository(_client, booking.id, widget.amigoId),
      travelerName: booking.travelerName,
      navigation: _navigation(),
    ),
  );

  void _review(AmigoBooking booking) => _open(
    AmigoTripReviewScreen(
      repository: AmigoSessionRepository(_client, booking.id),
      travelerName: booking.travelerName,
      startsAt: booking.startsAt,
      endsAt: booking.endsAt,
      navigation: _navigation(),
    ),
  );

  void _meetup(AmigoBooking booking, {bool showSessionFirst = false}) {
    final session = AmigoSessionRepository(_client, booking.id);
    _open(
      BookingMeetupScreen(
        client: _client,
        booking: booking.row,
        companionName: booking.travelerName,
        avatar: const TravelerAvatar(radius: 24),
        header: (title) => amigoHeader(title, leading: const AmigoBackButton()),
        amigoView: true,
        showSessionFirst: showSessionFirst,
        navigation: _navigation(),
        onChat: () => _chat(booking),
        tripControls: (row, trip, refresh) => AmigoSessionControls(
          repository: session,
          booking: row,
          session: trip,
          onReview: () => _review(booking.withRow(row)),
          onChanged: refresh,
        ),
      ),
    );
  }

  void _messages() => _open(
    AmigoBookingHistoryScreen(
      repository: _bookings,
      messagesOnly: true,
      onOpenBooking: _chat,
    ),
  );

  Future<void> _refreshName() async {
    try {
      final profile = await AmigoProfileRepository(_client).profile();
      if (!mounted) return;
      if (profile?['display_name'] case final String name) {
        setState(() => _name = name);
      }
    } catch (_) {
      // The profile editor already displays the saved result and any error.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: switch (_tab) {
      0 => AmigoHomeScreen(
        repository: _bookings,
        amigoName: _name,
        onOpenBooking: _details,
        onViewAll: () => _tabTo(1),
        onOpenEarnings: () => _tabTo(3),
        onOpenMessages: _messages,
        onOpenNotifications: () => _tabTo(1),
      ),
      1 => AmigoBookingHistoryScreen(
        key: const ValueKey('requests'),
        repository: _bookings,
        pendingOnly: true,
        onOpenBooking: _details,
      ),
      2 => AmigoBookingHistoryScreen(
        key: const ValueKey('history'),
        repository: _bookings,
        onOpenBooking: _details,
        onOpenMap: _meetup,
      ),
      3 => AmigoEarningsScreen(client: _client),
      _ => AmigoProfileScreen(
        account: widget.account,
        onProfileChanged: _refreshName,
        onEarnings: () => _tabTo(3),
      ),
    },
    bottomNavigationBar: _navigation(),
  );

  Widget _navigation() {
    const items = [
      ('home', 'Home'),
      ('requests', 'Requests'),
      ('history', 'History'),
      ('earnings', 'Earnings'),
      ('profile', 'Profile'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: amigoCream,
        border: Border.all(color: amigoBorder),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        currentIndex: _tab,
        onTap: _tabTo,
        selectedItemColor: amigoRust,
        unselectedItemColor: const Color(0xFF2F2F2F),
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: [
          for (final (index, (icon, label)) in items.indexed)
            BottomNavigationBarItem(
              label: label,
              tooltip: label,
              icon: SvgPicture.asset(
                'assets/figma/booking/nav_$icon.svg',
                colorFilter: ColorFilter.mode(
                  index == _tab ? amigoRust : const Color(0xFF2F2F2F),
                  BlendMode.srcIn,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
