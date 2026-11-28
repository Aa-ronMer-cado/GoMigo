import 'package:flutter/material.dart';

import '../../navigation/amigo_ui.dart';
import 'profile_fields.dart';
import 'profile_repository.dart';
import 'profile_service_area.dart';
import 'service_area.dart';

class AmigoEditProfileScreen extends StatefulWidget {
  const AmigoEditProfileScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.name,
    required this.gender,
    this.detectArea,
    this.creating = false,
    required this.onSaved,
    this.onLogout,
  });

  final AmigoProfileRepository repository;
  final Map<String, dynamic>? profile;
  final String name;
  final String gender;
  final Future<ServiceArea> Function()? detectArea;
  final bool creating;
  final VoidCallback onSaved;
  final VoidCallback? onLogout;

  @override
  State<AmigoEditProfileScreen> createState() => _AmigoEditProfileScreenState();
}

class _AmigoEditProfileScreenState extends State<AmigoEditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _serviceArea = GlobalKey();
  late final _description = TextEditingController(
    text: widget.profile?['description'] as String?,
  );
  late final _interests = profileInterests(widget.profile);
  late final _rate = TextEditingController(
    text: profileRate(widget.profile?['rate_centavos']),
  );
  ServiceArea? _area;
  bool _areaRequired = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        duration: const Duration(milliseconds: 180),
        alignment: .2,
      );
      return;
    }
    final area = _area;
    if (area == null) {
      setState(() => _areaRequired = true);
      await Scrollable.ensureVisible(
        _serviceArea.currentContext!,
        duration: const Duration(milliseconds: 180),
        alignment: .2,
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.save(
        description: _description.text.trim(),
        area: area.name,
        interests: _interests.toList(),
        rateCentavos: profileRateCentavos(_rate.text)!,
        photoPath: widget.profile?['photo_path'] as String?,
        latitude: area.point.latitude,
        longitude: area.point.longitude,
      );
      if (mounted) {
        amigoNotice(context, 'Profile saved.');
        widget.onSaved();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save your profile. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: amigoHeader(
      'Create your Amigo profile',
      leading: widget.creating && !_saving ? const AmigoBackButton() : null,
    ),
    body: Form(
      key: _form,
      // Keep fields mounted so validation includes fields outside the viewport.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Full name'),
              subtitle: Text(widget.name),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gender'),
              subtitle: Text(switch (widget.gender) {
                'woman' => 'Woman',
                'man' => 'Man',
                'nonbinary' => 'Nonbinary',
                _ => 'Prefer not to say',
              }),
            ),
            ProfileServiceArea(
              key: _serviceArea,
              enabled: !_saving,
              detectArea: widget.detectArea,
              onChanged: (area) => setState(() {
                _area = area;
                if (area != null) _areaRequired = false;
              }),
            ),
            if (_areaRequired)
              Semantics(
                liveRegion: true,
                child: const Text(
                  'Use your current location to set your service area.',
                ),
              ),
            const SizedBox(height: 13),
            const Text(
              'Interests',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ProfileInterestChips(
              interests: _interests,
              onSelected: _saving
                  ? null
                  : (interest, selected) => setState(() {
                      if (selected) {
                        _interests.add(interest);
                      } else {
                        _interests.remove(interest);
                      }
                    }),
            ),
            const SizedBox(height: 13),
            ProfileTextField(
              controller: _description,
              label: 'About you',
              validate: validateProfileDescription,
              enabled: !_saving,
              lines: 4,
              hint: 'At least 30 words',
            ),
            ProfileTextField(
              controller: _rate,
              label: profileRateLabel,
              validate: validateProfileRate,
              enabled: !_saving,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
            if (_saving) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Semantics(liveRegion: true, child: Text(error)),
              ),
            FilledButton(
              style: profileSaveStyle(),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save profile'),
            ),
            if (widget.onLogout != null)
              TextButton(
                onPressed: _saving ? null : widget.onLogout,
                child: const Text('Log out'),
              ),
          ],
        ),
      ),
    ),
  );
}
