import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../navigation/amigo_ui.dart';
import '../verification/verification_repository.dart';
import 'profile_fields.dart';
import 'profile_repository.dart';

typedef AmigoProfilePhoto = ({Uint8List bytes, String mime});

Future<AmigoProfilePhoto?> pickAmigoProfilePhoto() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 88,
  );
  if (file == null) return null;
  if (await file.length() > AmigoProfileRepository.maxPhotoBytes) {
    throw const FormatException(
      'Choose a JPG, PNG, or WebP photo of up to 8 MB.',
    );
  }
  final bytes = await file.readAsBytes();
  final mime =
      AmigoVerificationRepository.imageType(bytes) ??
      (bytes.length >= 12 &&
              String.fromCharCodes(bytes, 0, 4) == 'RIFF' &&
              String.fromCharCodes(bytes, 8, 12) == 'WEBP'
          ? 'image/webp'
          : null);
  if (mime == null) {
    throw const FormatException('Choose a JPG, PNG, or WebP photo.');
  }
  return (bytes: bytes, mime: mime);
}

class AmigoProfilePhotoScreen extends StatefulWidget {
  const AmigoProfilePhotoScreen({
    super.key,
    required this.repository,
    required this.photo,
  });

  final AmigoProfileRepository repository;
  final AmigoProfilePhoto photo;

  @override
  State<AmigoProfilePhotoScreen> createState() =>
      _AmigoProfilePhotoScreenState();
}

class _AmigoProfilePhotoScreenState extends State<AmigoProfilePhotoScreen> {
  late final _path = widget.repository.newPhotoPath(widget.photo.mime);
  bool _uploaded = false;
  bool _saving = false;
  bool _previewReady = false;
  bool _previewFailed = false;
  String? _error;

  Future<void> _save() async {
    if (_saving || !_previewReady || _previewFailed) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_uploaded) {
        await widget.repository.uploadPhoto(
          _path,
          widget.photo.bytes,
          widget.photo.mime,
        );
        _uploaded = true;
      }
      final updated = await widget.repository.update({'photo_path': _path});
      if (mounted) Navigator.of(context).pop(updated);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _uploaded
            ? 'The photo uploaded, but the profile could not be saved. Try again.'
            : 'Could not upload your photo. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: amigoHeader(
        'Edit profile photo',
        leading: _saving ? const SizedBox.shrink() : const AmigoBackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Center(
            child: ClipOval(
              child: Image.memory(
                widget.photo.bytes,
                width: 146,
                height: 146,
                fit: BoxFit.cover,
                semanticLabel: 'Selected profile photo',
                frameBuilder: (context, child, frame, sync) {
                  if (!_previewReady && (frame != null || sync)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_previewReady) {
                        setState(() => _previewReady = true);
                      }
                    });
                  }
                  return child;
                },
                errorBuilder: (context, error, stackTrace) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_previewFailed) {
                      setState(() => _previewFailed = true);
                    }
                  });
                  return const CircleAvatar(
                    radius: 73,
                    backgroundColor: amigoSage,
                    foregroundColor: amigoInk,
                    child: Icon(Icons.broken_image_outlined, size: 36),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Travelers can see your profile photo.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          if (_saving) const LinearProgressIndicator(),
          if (_previewFailed || _error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _previewFailed
                    ? 'Could not open this photo. Choose another image.'
                    : _error!,
              ),
            ),
          FilledButton(
            style: profileSaveStyle(),
            onPressed: _saving || !_previewReady || _previewFailed
                ? null
                : _save,
            child: Text(_saving ? 'Saving…' : 'Save photo'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
