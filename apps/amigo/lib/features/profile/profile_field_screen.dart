import 'package:flutter/material.dart';

import '../../navigation/amigo_ui.dart';
import 'profile_fields.dart';
import 'profile_repository.dart';
import 'profile_service_area.dart';
import 'service_area.dart';

enum AmigoProfileField {
  serviceArea('Service area'),
  interests('Interests'),
  description('About you'),
  rate('Hourly rate');

  const AmigoProfileField(this.label);
  final String label;
}

class AmigoProfileFieldScreen extends StatefulWidget {
  const AmigoProfileFieldScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.field,
  });

  final AmigoProfileRepository repository;
  final Map<String, dynamic> profile;
  final AmigoProfileField field;

  @override
  State<AmigoProfileFieldScreen> createState() =>
      _AmigoProfileFieldScreenState();
}

class _AmigoProfileFieldScreenState extends State<AmigoProfileFieldScreen> {
  final _form = GlobalKey<FormState>();
  late final _interests = profileInterests(widget.profile);
  late final _text = TextEditingController(
    text: switch (widget.field) {
      AmigoProfileField.description => widget.profile['description'] as String?,
      AmigoProfileField.rate => profileRate(widget.profile['rate_centavos']),
      _ => null,
    },
  );
  ServiceArea? _area;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final area = _area;
    if (widget.field == AmigoProfileField.serviceArea && area == null) return;
    final changes = switch (widget.field) {
      AmigoProfileField.serviceArea => {
        'area': area!.name,
        'discovery_latitude': area.point.latitude,
        'discovery_longitude': area.point.longitude,
      },
      AmigoProfileField.interests => {'interests': _interests.toList()},
      AmigoProfileField.description => {'description': _text.text.trim()},
      AmigoProfileField.rate => {
        'rate_centavos': profileRateCentavos(_text.text),
      },
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.repository.update(changes);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save your changes. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: amigoHeader(
        'Edit ${widget.field.label.toLowerCase()}',
        leading: _saving ? const SizedBox.shrink() : const AmigoBackButton(),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            switch (widget.field) {
              AmigoProfileField.serviceArea => ProfileServiceArea(
                savedArea: widget.profile['area'] as String?,
                enabled: !_saving,
                onChanged: (area) => setState(() => _area = area),
              ),
              AmigoProfileField.interests => ProfileInterestChips(
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
              AmigoProfileField.description => ProfileTextField(
                controller: _text,
                label: widget.field.label,
                validate: validateProfileDescription,
                enabled: !_saving,
                lines: 5,
                hint: 'At least 30 words',
              ),
              AmigoProfileField.rate => ProfileTextField(
                controller: _text,
                label: profileRateLabel,
                validate: validateProfileRate,
                enabled: !_saving,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
            },
            const SizedBox(height: 20),
            if (_saving) const LinearProgressIndicator(),
            if (_error case final error?)
              Semantics(liveRegion: true, child: Text(error)),
            FilledButton(
              style: profileSaveStyle(),
              onPressed:
                  _saving ||
                      (widget.field == AmigoProfileField.serviceArea &&
                          _area == null)
                  ? null
                  : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}
