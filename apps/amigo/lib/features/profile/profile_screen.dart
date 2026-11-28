import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gomigo_shared_widgets/device_location.dart';
import 'package:gomigo_shared_widgets/password_settings.dart';

import '../../navigation/amigo_ui.dart';
import '../authentication/account_repository.dart';
import '../verification/verification_repository.dart';
import '../verification/verification_screen.dart';
import 'profile_field_screen.dart';
import 'profile_fields.dart';
import 'profile_photo_screen.dart';
import 'profile_repository.dart';

const _art = 'assets/figma/account/';

class AmigoProfileScreen extends StatefulWidget {
  const AmigoProfileScreen({
    super.key,
    required this.account,
    this.onProfileChanged,
    this.onEarnings,
    this.onReviews,
  });

  final AmigoAccountRepository account;
  final VoidCallback? onProfileChanged;
  final VoidCallback? onEarnings;
  final VoidCallback? onReviews;

  @override
  State<AmigoProfileScreen> createState() => _AmigoProfileScreenState();
}

typedef _Profile = ({
  Map<String, dynamic> account,
  Map<String, dynamic>? amigo,
});

class _AmigoProfileScreenState extends State<AmigoProfileScreen> {
  late final _repository = AmigoProfileRepository(widget.account.client);
  late Future<_Profile> _profile = _load();
  bool _signingOut = false;
  bool _pickingPhoto = false;

  Future<_Profile> _load() async {
    final account = widget.account.profile();
    final profile = _repository.profile();
    final values = await Future.wait([account, profile]);
    return (account: values[0]!, amigo: values[1]);
  }

  Future<void> _logout() async {
    setState(() => _signingOut = true);
    try {
      await widget.account.logout();
    } catch (_) {
      if (mounted) amigoNotice(context, 'Could not log out. Try again.');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  void _open(Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  void _refresh() {
    final profile = _load();
    setState(() {
      _profile = profile;
    });
  }

  Future<void> _edit(_Profile data, AmigoProfileField field) async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => AmigoProfileFieldScreen(
          repository: _repository,
          profile: data.amigo!,
          field: field,
        ),
      ),
    );
    if (saved == null || !mounted) return;
    _showSavedProfile(data, saved);
  }

  Future<void> _changePhoto(_Profile data) async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final photo = await pickAmigoProfilePhoto();
      if (!mounted || photo == null) return;
      final saved = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) =>
              AmigoProfilePhotoScreen(repository: _repository, photo: photo),
        ),
      );
      if (saved == null || !mounted) return;
      _showSavedProfile(data, saved);
    } on FormatException catch (error) {
      if (mounted) amigoNotice(context, error.message);
    } catch (_) {
      if (mounted) {
        amigoNotice(context, 'Could not open your photos. Try again.');
      }
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _showSavedProfile(_Profile previous, Map<String, dynamic> saved) {
    setState(() {
      _profile = Future.value((account: previous.account, amigo: saved));
    });
    widget.onProfileChanged?.call();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Profile>(
    future: _profile,
    builder: (context, snapshot) {
      final data = snapshot.data;
      if (snapshot.hasError || data == null) {
        return Scaffold(
          appBar: amigoHeader('Profile'),
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Could not load your profile.'),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Try again'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        );
      }
      return _overview(data);
    },
  );

  Widget _overview(_Profile data) {
    final amigo = data.amigo;
    final name = data.account['display_name'] as String;
    final user = widget.account.client.auth.currentUser;
    final email = user?.email;
    final phone = user?.userMetadata?['contact_phone'];
    final photo = _repository.photoUrl(amigo);
    final verified = amigo?['verified'] == true;
    final choosePhoto = amigo == null || _pickingPhoto
        ? null
        : () => _changePhoto(data);
    return Scaffold(
      appBar: amigoHeader('Profile'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Semantics(
                  label: 'Choose profile photo',
                  button: true,
                  enabled: choosePhoto != null,
                  child: Material(
                    color: amigoSage,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: choosePhoto,
                      child: SizedBox.square(
                        dimension: 146,
                        child: photo == null
                            ? _Initial(name)
                            : Image.network(
                                photo,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _Initial(name),
                              ),
                      ),
                    ),
                  ),
                ),
                IconButton.filled(
                  onPressed: choosePhoto,
                  tooltip: 'Edit profile photo',
                  style: IconButton.styleFrom(backgroundColor: amigoCream),
                  icon: _ProfileIcon('edit', size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: amigoInk,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            verified ? 'Verified Amigo · Demo' : 'Amigo',
            textAlign: TextAlign.center,
            style: const TextStyle(color: amigoInk),
          ),
          const SizedBox(height: 20),
          _section('Personal information', [
            ListTile(
              leading: _ProfileIcon('account'),
              title: Text(name),
              subtitle: const Text('Full Name'),
            ),
            if (email != null)
              ListTile(
                leading: const Icon(
                  Icons.email_outlined,
                  color: Color(0xFF557753),
                ),
                title: Text(email),
                subtitle: const Text('Email address'),
              ),
            if (phone is String && phone.isNotEmpty)
              ListTile(
                leading: _ProfileIcon('phone'),
                title: Text(phone),
                subtitle: const Text('Mobile Number'),
              ),
            _tile('id', 'ID verification', () {
              _open(
                AmigoVerificationScreen(
                  repository: AmigoVerificationRepository(
                    widget.account.client,
                  ),
                ),
              );
            }),
          ]),
          const SizedBox(height: 15),
          _section('Amigo profile', [
            if (amigo != null) ...[
              _fieldTile(
                data,
                AmigoProfileField.serviceArea,
                Icons.location_on_outlined,
                amigo['area'] as String?,
              ),
              _fieldTile(
                data,
                AmigoProfileField.interests,
                Icons.interests_outlined,
                profileInterests(amigo).join(', '),
              ),
              _fieldTile(
                data,
                AmigoProfileField.description,
                Icons.notes_outlined,
                amigo['description'] as String?,
              ),
              _fieldTile(
                data,
                AmigoProfileField.rate,
                Icons.payments_outlined,
                '₱${profileRate(amigo['rate_centavos'])} per hour',
              ),
            ],
            if (amigo != null)
              ListTile(
                leading: const Icon(
                  Icons.star_outline,
                  color: Color(0xFF557753),
                ),
                title: const Text('Ratings and reviews'),
                trailing: _ProfileIcon('chevron', size: 10),
                onTap:
                    widget.onReviews ??
                    () => _open(
                      _ReviewsScreen(
                        repository: _repository,
                        amigoId: amigo['id'] as String,
                      ),
                    ),
              ),
            if (widget.onEarnings != null)
              ListTile(
                leading: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Color(0xFF557753),
                ),
                title: const Text('Earnings and payouts'),
                trailing: _ProfileIcon('chevron', size: 10),
                onTap: widget.onEarnings,
              ),
          ]),
          const SizedBox(height: 15),
          _section('Account settings', [
            _tile('help', 'Help & Support', () => _open(const _HelpScreen())),
            _tile(
              'settings',
              'Settings',
              () => _open(_SettingsScreen(account: widget.account)),
            ),
            _tile(
              'logout',
              _signingOut ? 'Logging out…' : 'Log Out',
              _signingOut ? null : _logout,
              chevron: false,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _fieldTile(
    _Profile data,
    AmigoProfileField field,
    IconData icon,
    String? value,
  ) => ListTile(
    leading: Icon(icon, color: const Color(0xFF557753)),
    title: Text(field.label),
    subtitle: value == null || value.isEmpty
        ? null
        : Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: _ProfileIcon('chevron', size: 10),
    onTap: () => _edit(data, field),
  );

  Widget _tile(
    String icon,
    String label,
    VoidCallback? onTap, {
    bool chevron = true,
  }) => ListTile(
    leading: _ProfileIcon(icon),
    title: Text(label),
    trailing: chevron ? _ProfileIcon('chevron', size: 10) : null,
    onTap: onTap,
  );

  Widget _section(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 3, bottom: 6),
        child: Text(
          title,
          style: const TextStyle(color: amigoInk, fontWeight: FontWeight.w800),
        ),
      ),
      Material(
        color: amigoCream,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: amigoBorder),
          borderRadius: BorderRadius.circular(17),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: rows),
      ),
    ],
  );
}

class _Initial extends StatelessWidget {
  const _Initial(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      name.characters.firstOrNull?.toUpperCase() ?? 'A',
      style: const TextStyle(
        color: amigoInk,
        fontSize: 49,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon(this.asset, {this.size = 22});
  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    '${_art}profile_$asset.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      asset == 'logout' ? amigoRust : const Color(0xFF557753),
      BlendMode.srcIn,
    ),
  );
}

class _ReviewsScreen extends StatefulWidget {
  const _ReviewsScreen({required this.repository, required this.amigoId});
  final AmigoProfileRepository repository;
  final String amigoId;

  @override
  State<_ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<_ReviewsScreen> {
  late var _reviews = widget.repository.receivedReviews(widget.amigoId);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: amigoHeader('Ratings and reviews'),
    body: FutureBuilder(
      future: _reviews,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your reviews.'),
                TextButton(
                  onPressed: () => setState(
                    () => _reviews = widget.repository.receivedReviews(
                      widget.amigoId,
                    ),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            ),
          );
        }
        final reviews = snapshot.data;
        if (reviews == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (reviews.isEmpty) {
          return const Center(child: Text('No traveler reviews yet.'));
        }
        final average =
            reviews.fold<int>(
              0,
              (total, review) => total + (review['rating'] as int),
            ) /
            reviews.length;
        final count = reviews.length;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              '${average.toStringAsFixed(1)} out of 5 · $count ${count == 1 ? 'review' : 'reviews'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final review in reviews)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.star_outline, color: amigoRust),
                  title: Text('${review['rating']} out of 5'),
                  subtitle: switch (review['body']) {
                    final String body => Text(body),
                    _ => null,
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({required this.account});

  final AmigoAccountRepository account;

  Future<void> _locationSettings(BuildContext context) async {
    if (await openDeviceLocationSettings(DeviceLocationSettings.app)) return;
    if (context.mounted) {
      amigoNotice(
        context,
        'Manage location access in your device or browser permissions.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: amigoHeader('Settings'),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: PasswordSettingsTile(auth: account.client.auth)),
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Location permission'),
            subtitle: const Text(
              'Manage access for meetup maps and trip recording.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _locationSettings(context),
          ),
        ),
      ],
    ),
  );
}

class _HelpScreen extends StatelessWidget {
  const _HelpScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: amigoHeader('Help & Support'),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ExpansionTile(
          title: Text('How do I receive booking requests?'),
          children: [
            _HelpAnswer(
              'Complete your Amigo profile and ID review, then turn on availability on Home.',
            ),
          ],
        ),
        ExpansionTile(
          title: Text('When does GoMigo share my location?'),
          children: [
            _HelpAnswer(
              'You choose to share from the meetup map. You can stop at any time, and the app stops sharing when you leave the map.',
            ),
          ],
        ),
        ExpansionTile(
          title: Text('How do I get help with this demo?'),
          children: [
            _HelpAnswer(
              'Contact the organizer who provided your test account, and include the booking reference if the issue is about a trip.',
            ),
          ],
        ),
      ],
    ),
  );
}

class _HelpAnswer extends StatelessWidget {
  const _HelpAnswer(this.answer);
  final String answer;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Text(answer),
  );
}
