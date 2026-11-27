import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../navigation/traveler_ui.dart';
import '../authentication/account_repository.dart';
import '../verification/verification_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.account,
    required this.onWalkthrough,
  });
  final AccountRepository account;
  final VoidCallback onWalkthrough;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> _profile = widget.account.profile();
  bool _signingOut = false;

  void _open(Widget Function() page) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page()));

  Future<void> _edit(String name) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _EditName(name),
    );
    if (result == null || result == name) return;
    try {
      await widget.account.updateName(result);
      if (mounted) setState(() => _profile = widget.account.profile());
    } catch (_) {
      if (mounted)
        notifyTraveler(context, 'Could not save your name. Try again.');
    }
  }

  Future<void> _logout() async {
    setState(() => _signingOut = true);
    try {
      await widget.account.logout();
    } catch (_) {
      if (mounted) notifyTraveler(context, 'Could not log out. Try again.');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Widget _tile(
    String asset,
    String title,
    VoidCallback? onTap, {
    bool chevron = true,
  }) => ListTile(
    leading: TravelerAsset(
      asset,
      size: 21,
      color: asset == 'profile_logout' ? travelerRust : const Color(0xFF557753),
    ),
    title: Text(title),
    trailing: chevron ? const TravelerAsset('profile_chevron', size: 10) : null,
    onTap: onTap,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader('Profile'),
    body: FutureBuilder(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return TravelerError(
            'Could not load your profile.',
            onRetry: () => setState(() => _profile = widget.account.profile()),
          );
        final info = snapshot.data;
        if (info == null)
          return const Center(child: CircularProgressIndicator());
        final user = widget.account.client.auth.currentUser!;
        final name = info['display_name'] as String;
        final phone = user.userMetadata?['contact_phone'] as String?;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 76,
                    backgroundColor: travelerSage,
                    foregroundColor: travelerInk,
                    child: Text(
                      name.characters.firstOrNull?.toUpperCase() ?? 'T',
                      style: const TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit name',
                    onPressed: () => _edit(name),
                    icon: const TravelerAsset('profile_edit'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Center(child: Text('Traveler account')),
            const SizedBox(height: 18),
            const Text('Personal information'),
            const SizedBox(height: 8),
            TravelerCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    title: Text(name),
                    subtitle: const Text('Name'),
                    leading: const TravelerAsset('profile_id'),
                  ),
                  if (user.email != null)
                    ListTile(
                      title: Text(user.email!),
                      subtitle: const Text('Email address'),
                      leading: const Icon(Icons.email_outlined),
                    ),
                  if (phone != null && phone.isNotEmpty)
                    ListTile(
                      title: Text(phone),
                      subtitle: const Text('Mobile number'),
                      leading: const Icon(Icons.phone_outlined),
                    ),
                  _tile(
                    'profile_id',
                    'ID verification',
                    () => _open(
                      () => VerificationScreen(client: widget.account.client),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TravelerCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const TravelerAsset('profile_card', size: 21),
                title: const Text('Manage Payment Methods'),
                trailing: const TravelerAsset('profile_add', size: 16),
                onTap: () => _open(() => const _PaymentMethods()),
              ),
            ),
            const SizedBox(height: 15),
            const Text('Account settings'),
            const SizedBox(height: 8),
            TravelerCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _tile(
                    'profile_help',
                    'Help & Support',
                    () => _open(() => const _SupportScreen()),
                  ),
                  _tile(
                    'profile_settings',
                    'Settings',
                    () => _open(
                      () =>
                          _SettingsScreen(onWalkthrough: widget.onWalkthrough),
                    ),
                  ),
                  _tile(
                    'profile_logout',
                    _signingOut ? 'Logging out…' : 'Log Out',
                    _signingOut ? null : _logout,
                    chevron: false,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _EditName extends StatefulWidget {
  const _EditName(this.name);
  final String name;
  @override
  State<_EditName> createState() => _EditNameState();
}

class _EditNameState extends State<_EditName> {
  late final _controller = TextEditingController(text: widget.name);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit name'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      onChanged: (_) => setState(() {}),
      decoration: travelerField('Name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({required this.onWalkthrough});
  final VoidCallback onWalkthrough;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader('Settings'),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TravelerCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                title: const Text('Location permission'),
                subtitle: const Text(
                  'You choose when to share or record your location on the meetup map.',
                ),
                trailing: const TravelerAsset('profile_chevron', size: 10),
                onTap: () async {
                  var opened = false;
                  if (!kIsWeb) {
                    try {
                      opened = await Geolocator.openAppSettings();
                    } catch (_) {}
                  }
                  if (!opened && context.mounted) {
                    notifyTraveler(
                      context,
                      'Manage location permission in your device or browser settings.',
                    );
                  }
                },
              ),
              ListTile(
                title: const Text('Replay walkthrough'),
                onTap: () {
                  Navigator.pop(context);
                  onWalkthrough();
                },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SupportScreen extends StatelessWidget {
  const _SupportScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader('Help & Support'),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        TravelerCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ExpansionTile(
                title: Text('How do I get verified?'),
                children: [
                  ListTile(
                    title: Text(
                      'Open Profile, choose ID verification, and submit both sides of a fictional or authorized test ID. Check that screen for the reviewer’s decision.',
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                title: Text('How do I cancel a booking?'),
                children: [
                  ListTile(
                    title: Text(
                      'Open the booking from History. Cancel an open test checkout before cancelling the booking. Paid demo bookings cannot be cancelled from the app.',
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                title: Text('Who can see my location?'),
                children: [
                  ListTile(
                    title: Text(
                      'Only the participants of your booking can see a shared location. Turn it off in the meetup map at any time.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PaymentMethods extends StatelessWidget {
  const _PaymentMethods();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader('Manage Payment Methods'),
    body: ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text('Test payments', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        const Text(
          'Open an accepted booking to try a payment in Xendit Test Mode.',
        ),
        const SizedBox(height: 18),
        const TravelerCard(
          child: ListTile(
            leading: TravelerAsset('profile_card'),
            title: Text('Test card'),
            subtitle: Text(
              'Enter test card details directly on the hosted checkout page.',
            ),
          ),
        ),
      ],
    ),
  );
}
