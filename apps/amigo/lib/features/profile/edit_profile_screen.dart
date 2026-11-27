import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/device_location.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../navigation/amigo_ui.dart';
import '../verification/verification_repository.dart';
import 'profile_repository.dart';
import 'service_area.dart';

const _interestOptions = [
  'Food & Dining',
  'Nature & Adventure',
  'Shopping',
  'Photography',
  'Nightlife',
  'Local Culture',
  'Arts & Museums',
  'Outdoor Activities',
  'Local Experiences',
];

class AmigoEditProfileScreen extends StatefulWidget {
  const AmigoEditProfileScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.name,
    required this.gender,
    this.detectArea = detectServiceArea,
    this.creating = false,
    required this.onSaved,
    this.onLogout,
  });
  final AmigoProfileRepository repository;
  final Map<String, dynamic>? profile;
  final String name;
  final String gender;
  final Future<ServiceArea> Function() detectArea;
  final bool creating;
  final VoidCallback onSaved;
  final VoidCallback? onLogout;

  @override
  State<AmigoEditProfileScreen> createState() => _AmigoEditProfileScreenState();
}

class _AmigoEditProfileScreenState extends State<AmigoEditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _serviceArea = GlobalKey();
  late final _description = _text('description');
  late final _interests = (widget.profile?['interests'] as List? ?? [])
      .whereType<String>()
      .toSet();
  late final _rate = TextEditingController(
    text: switch (widget.profile?['rate_centavos']) {
      final num cents => (cents / 100).toStringAsFixed(2),
      _ => '',
    },
  );
  late ServiceArea? _area = widget.creating ? null : _existingArea();
  bool _locating = false;
  String? _locationError;
  late var _photoPath = widget.profile?['photo_path'] as String?;
  Uint8List? _photo;
  String? _mime;
  bool _picking = false;
  bool _saving = false;
  String? _error;

  bool get _busy => _picking || _saving || _locating;

  TextEditingController _text(String key, [String fallback = '']) =>
      TextEditingController(text: widget.profile?[key] as String? ?? fallback);

  ServiceArea? _existingArea() {
    final lat = widget.profile?['discovery_latitude'] as num?;
    final lng = widget.profile?['discovery_longitude'] as num?;
    final name = widget.profile?['area'] as String?;
    if (lat == null || lng == null || name == null || name.isEmpty) return null;
    return (name: name, point: LatLng(lat.toDouble(), lng.toDouble()));
  }

  @override
  void dispose() {
    _description.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 88,
      );
      if (file == null) return;
      if (await file.length() > AmigoProfileRepository.maxPhotoBytes) {
        throw const FormatException('Choose a JPG or PNG photo of up to 8 MB.');
      }
      final bytes = await file.readAsBytes();
      final mime = AmigoVerificationRepository.imageType(bytes);
      if (mime == null) {
        throw const FormatException('Choose a JPG or PNG photo.');
      }
      if (mounted) {
        setState(() {
          _photo = bytes;
          _mime = mime;
        });
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not open the photo. Check your photo permission.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _detectArea() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final area = await widget.detectArea();
      if (mounted) setState(() => _area = area);
    } on DeviceLocationException catch (error) {
      if (mounted) setState(() => _locationError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _locationError = 'Could not detect your service area. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
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
      setState(
        () => _locationError =
            'Use your current location to set your service area.',
      );
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
      if (_photo case final bytes?) {
        final path = await widget.repository.uploadPhoto(bytes, _mime!);
        if (!mounted) return;
        _photoPath = path;
        // Preserve the uploaded path for a retry if saving the row fails.
        _photo = null;
        _mime = null;
      }
      await widget.repository.save(
        description: _description.text.trim(),
        area: area.name,
        interests: _interests.toList(),
        rateCentavos: _toCentavos(_rate.text)!,
        photoPath: _photoPath,
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
  Widget build(BuildContext context) {
    final photoUrl = _photoPath == null
        ? widget.repository.photoUrl(widget.profile)
        : widget.repository.photoUrl({'photo_path': _photoPath});
    return Scaffold(
      appBar: amigoHeader(
        widget.creating || widget.profile == null
            ? 'Create your Amigo profile'
            : 'Edit profile',
        leading: widget.creating && !_busy ? const AmigoBackButton() : null,
      ),
      body: Form(
        key: _form,
        // Keep fields mounted so validation includes fields outside the viewport.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.creating && widget.profile != null) ...[
                Center(
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: amigoSage,
                    foregroundColor: amigoInk,
                    child: ClipOval(
                      child: SizedBox.square(
                        dimension: 88,
                        child: _photo != null
                            ? Image.memory(
                                _photo!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _avatar(),
                              )
                            : photoUrl == null
                            ? _avatar()
                            : Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _avatar(),
                              ),
                      ),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _pickPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    _picking
                        ? 'Opening photos…'
                        : 'Choose public profile photo',
                  ),
                ),
              ],
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
              Text(
                'Service area',
                key: _serviceArea,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (_area case final area?) Text(area.name),
              OutlinedButton.icon(
                onPressed: _busy ? null : _detectArea,
                icon: const Icon(Icons.my_location),
                label: Text(
                  _locating ? 'Detecting location…' : 'Use Current Location',
                ),
              ),
              const Text(
                'Your approximate service area is visible to travelers.',
              ),
              if (_locationError case final error?)
                Semantics(liveRegion: true, child: Text(error)),
              const SizedBox(height: 13),
              const Text(
                'Interests',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final interest in {..._interestOptions, ..._interests})
                    FilterChip(
                      label: Text(interest),
                      selected: _interests.contains(interest),
                      selectedColor: amigoSage,
                      onSelected: _busy
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                _interests.add(interest);
                              } else {
                                _interests.remove(interest);
                              }
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 13),
              _field(
                _description,
                'About you',
                _validateAbout,
                lines: 4,
                hint: 'At least 30 words',
              ),
              _field(
                _rate,
                'Hourly rate (₱)',
                (value) {
                  final cents = _toCentavos(value ?? '');
                  return cents == null || cents < 20000 || cents > 150000
                      ? 'Enter ₱200 to ₱1,500, with up to two decimal places.'
                      : null;
                },
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              if (_saving) const LinearProgressIndicator(),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Semantics(liveRegion: true, child: Text(error)),
                ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: amigoRust,
                  minimumSize: const Size(0, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _busy ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save profile'),
              ),
              if (widget.onLogout != null)
                TextButton(
                  onPressed: _busy ? null : widget.onLogout,
                  child: const Text('Log out'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar() => const Icon(Icons.person_outline, size: 44);

  InputDecoration _input(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: amigoCream,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: amigoBorder),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String? Function(String?) validate, {
    String? hint,
    int lines = 1,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      keyboardType: keyboard,
      textCapitalization: keyboard == null
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      maxLines: lines,
      decoration: _input(label, hint: hint),
      validator: validate,
    ),
  );

  String? _validateAbout(String? value) {
    final description = value?.trim() ?? '';
    if (description.isEmpty || description.split(RegExp(r'\s+')).length < 30) {
      return 'Write at least 30 words.';
    }
    return description.characters.length > 1500
        ? 'Use at most 1,500 characters.'
        : null;
  }

  int? _toCentavos(String value) {
    final input = value.trim();
    if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(input)) return null;
    final parts = input.split('.');
    return int.parse(parts.first) * 100 +
        (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
  }
}
