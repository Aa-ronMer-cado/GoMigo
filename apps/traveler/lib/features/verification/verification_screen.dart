import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../navigation/traveler_ui.dart';
import 'verification_repository.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key, required this.client});
  final SupabaseClient client;

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final _repository = VerificationRepository(widget.client);
  late Stream<List<Map<String, dynamic>>> _submissions;
  final _picker = ImagePicker();
  final _sides = <String, Uint8List>{};
  String _submission = const Uuid().v4();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _submissions = _repository.submissions();
  }

  Future<void> _pick(String side) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (kIsWeb ||
                defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS)
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Choose an image'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 2100,
        imageQuality: 88,
      );
      if (image == null) return;
      if (await image.length() > 8 * 1024 * 1024) {
        throw const FormatException('Choose a JPG or PNG image of up to 8 MB.');
      }
      final bytes = await image.readAsBytes();
      if (verificationImageType(bytes) == null) {
        throw const FormatException('Choose a JPG or PNG image.');
      }
      if (mounted)
        setState(() {
          _sides[side] = bytes;
          _submission = const Uuid().v4();
          _error = null;
        });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Could not open that image. Check camera or photo permissions and try again.',
        );
    }
  }

  Future<void> _submit() async {
    if (_sides.length != 2) {
      setState(() => _error = 'Add both the front and back of your test ID.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final entry in _sides.entries) {
        await _repository.upload(_submission, entry.key, entry.value);
      }
      await _repository.submit(_submission);
      if (mounted)
        setState(() {
          _sides.clear();
          _submission = const Uuid().v4();
          _submissions = _repository.submissions();
        });
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The test ID could not be submitted. Check your connection and try again.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _photo(String side, String label) => Expanded(
    child: TravelerCard(
      padding: EdgeInsets.zero,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 108),
          foregroundColor: travelerInk,
        ),
        onPressed: _busy ? null : () => _pick(side),
        child: Column(
          children: [
            if (_sides.containsKey(side))
              const Icon(Icons.check_circle_outline, size: 34)
            else
              TravelerAsset('verification_$side', size: 34),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            if (_sides.containsKey(side)) const Text('Image selected'),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: travelerHeader('Verifying Your Details', color: travelerCream),
    body: StreamBuilder(
      stream: _submissions,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return TravelerError(
            'Could not load verification status.',
            onRetry: () =>
                setState(() => _submissions = _repository.submissions()),
          );
        final list = snapshot.data;
        if (list == null)
          return const Center(child: CircularProgressIndicator());
        final latest = list.firstOrNull;
        final status = latest?['status'] as String?;
        final step = switch (status) {
          'pending' => 1,
          'approved' => 2,
          _ => 0,
        };
        return ListView(
          padding: const EdgeInsets.all(15),
          children: [
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final (index, label) in [
                  'Upload',
                  'Validating',
                  'Done',
                ].indexed)
                  Column(
                    children: [
                      CircleAvatar(
                        backgroundColor: index == step
                            ? travelerRust
                            : travelerSage,
                        foregroundColor: index == step
                            ? Colors.white
                            : travelerInk,
                        radius: 17,
                        child: Text('${index + 1}'),
                      ),
                      const SizedBox(height: 5),
                      Text(label),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 32),
            if (status != null) ...[
              Image.asset(
                'assets/figma/verification_$status.png',
                height: 184,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 18),
              TravelerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (status) {
                        'approved' => 'Test ID approved',
                        'rejected' => 'Test ID rejected',
                        _ => 'Test ID awaiting review',
                      },
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: travelerInk,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      (latest?['rejection_reason'] as String?) ??
                          switch (status) {
                            'approved' => 'You can now request a demo booking.',
                            'rejected' => 'Submit both sides again when ready.',
                            _ =>
                              'An authorized reviewer will review your submission.',
                          },
                    ),
                    if (status == 'pending')
                      TextButton(
                        onPressed: () => setState(
                          () => _submissions = _repository.submissions(),
                        ),
                        child: const Text('Refresh status'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (status == null || status == 'rejected') ...[
              const Text(
                'Use a fictional or authorized test ID for this demo.',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _photo('front', 'Front of ID'),
                  const SizedBox(width: 10),
                  _photo('back', 'Back of ID'),
                ],
              ),
              const SizedBox(height: 16),
              const TravelerCard(
                child: Row(
                  children: [
                    TravelerAsset('verification_clock', size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Use good light and keep all corners visible.',
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: travelerRust),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              TravelerButton(
                _busy ? 'Uploading…' : 'Submit test ID',
                _busy ? null : _submit,
              ),
            ],
          ],
        );
      },
    ),
  );
}
