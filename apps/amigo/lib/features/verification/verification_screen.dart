import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../navigation/amigo_ui.dart';
import 'verification_repository.dart';

const _art = 'assets/figma/account/';
const _noticeColor = Color(0xFFF2E6D8);

class AmigoVerificationScreen extends StatefulWidget {
  const AmigoVerificationScreen({
    super.key,
    required this.repository,
    this.onApproved,
    this.initialSubmission,
    this.onLogout,
  });

  final AmigoVerificationRepository repository;
  final VoidCallback? onApproved;
  final Map<String, dynamic>? initialSubmission;
  final VoidCallback? onLogout;

  @override
  State<AmigoVerificationScreen> createState() =>
      _AmigoVerificationScreenState();
}

class _AmigoVerificationScreenState extends State<AmigoVerificationScreen> {
  late var _submissions = widget.repository.submissions();
  String _id = const Uuid().v4();
  Uint8List? _front;
  Uint8List? _back;
  bool _busy = false;
  String? _error;

  Future<void> _capture({
    required bool front,
    bool continueToBack = true,
  }) async {
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => _CaptureId(front: front, image: front ? _front : _back),
      ),
    );
    if (bytes == null || !mounted) return;
    setState(() {
      if (front) {
        _front = bytes;
      } else {
        _back = bytes;
      }
      _id = const Uuid().v4();
      _error = null;
    });
    if (front && _back == null && continueToBack) {
      await _capture(front: false, continueToBack: false);
    }
  }

  void _refresh() => setState(() {
    _submissions = widget.repository.submissions();
  });

  Future<void> _submit() async {
    final front = _front;
    final back = _back;
    if (_busy || front == null || back == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.submit(_id, front, back);
      if (mounted) {
        setState(() {
          _front = null;
          _back = null;
          _id = const Uuid().v4();
        });
        _refresh();
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not submit your test ID. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _side({required bool front}) {
    final selected = (front ? _front : _back) != null;
    return Expanded(
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: amigoCream,
          foregroundColor: amigoInk,
          minimumSize: const Size(0, 108),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: amigoBorder),
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        onPressed: _busy ? null : () => _capture(front: front),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected)
              const Icon(Icons.check_circle_outline, size: 28)
            else
              SvgPicture.asset(
                '${_art}id_${front ? 'front' : 'back'}_camera.svg',
              ),
            const SizedBox(height: 8),
            Text(
              front ? 'Front of ID' : 'Back of ID',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            if (selected) const Text('Image selected'),
          ],
        ),
      ),
    );
  }

  Widget _content(Map<String, dynamic>? latest) {
    final status = latest?['status'] as String?;
    final approved = status == 'approved';
    final detailsReady =
        latest?['reviewed_display_name'] != null &&
        latest?['reviewed_gender'] != null;
    final pending = status == 'pending';
    final stage = approved
        ? 2
        : pending
        ? 1
        : 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
      children: [
        _VerificationSteps(stage: stage),
        const SizedBox(height: 36),
        if (pending || approved) ...[
          Image.asset(
            '${_art}id_${approved ? 'approved' : 'pending'}.png',
            height: 276,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: 30),
          Text(
            approved ? 'Verification Complete' : 'Validating your information…',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            approved
                ? 'Your test ID has been approved.'
                : 'An authorized reviewer will check your test ID.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 38),
          if (pending) ...[
            const _VerificationNote(
              asset: 'id_waiting_clock.svg',
              text: 'Verification in progress',
              detail: 'Your submission is waiting for review.',
            ),
            TextButton(
              onPressed: _refresh,
              child: const Text('Refresh status'),
            ),
          ] else if (widget.onApproved != null && detailsReady)
            _VerificationButton('Done', widget.onApproved)
          else if (widget.onApproved != null) ...[
            const Text(
              'Your ID was approved. Your reviewer still needs to confirm your profile details.',
            ),
            TextButton(
              onPressed: _refresh,
              child: const Text('Refresh status'),
            ),
          ],
        ] else ...[
          if (status == 'rejected') ...[
            _VerificationNote(
              text: 'Test ID rejected',
              detail:
                  latest?['rejection_reason'] as String? ??
                  'Submit new photos when you’re ready.',
            ),
            const SizedBox(height: 14),
          ],
          const _VerificationNote(
            text: 'Photo ID',
            detail: 'Use a fictional or authorized test ID for this demo.',
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _side(front: true),
              const SizedBox(width: 10),
              _side(front: false),
            ],
          ),
          const SizedBox(height: 16),
          const _VerificationNote(
            text: 'Use good light and keep all corners visible',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_error!)),
          ],
          if (_front != null && _back != null) ...[
            const SizedBox(height: 16),
            _VerificationButton(
              _busy ? 'Submitting…' : 'Submit test ID',
              _busy ? null : _submit,
            ),
          ],
        ],
      ],
    );
  }

  Widget _status() {
    final approved = widget.initialSubmission;
    if (approved?['status'] == 'approved' &&
        approved?['reviewed_display_name'] != null &&
        approved?['reviewed_gender'] != null) {
      return _content(approved);
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _submissions,
      initialData: widget.initialSubmission == null
          ? null
          : [widget.initialSubmission!],
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load verification status.'),
                TextButton(onPressed: _refresh, child: const Text('Try again')),
              ],
            ),
          );
        }
        final rows = snapshot.data;
        if (rows == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return _content(rows.firstOrNull);
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _heading(context, 'Verifying Your Details'),
    body: _status(),
    bottomNavigationBar: widget.onLogout == null
        ? null
        : SafeArea(
            child: TextButton(
              onPressed: _busy ? null : widget.onLogout,
              child: const Text('Log Out'),
            ),
          ),
  );
}

AppBar _heading(BuildContext context, String title) => AppBar(
  backgroundColor: amigoCream,
  foregroundColor: amigoInk,
  elevation: 0,
  centerTitle: true,
  leading: Navigator.canPop(context)
      ? IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: SvgPicture.asset('${_art}id_back.svg'),
          onPressed: () => Navigator.maybePop(context),
        )
      : null,
  title: Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
  ),
);

class _CaptureId extends StatefulWidget {
  const _CaptureId({required this.front, required this.image});
  final bool front;
  final Uint8List? image;

  @override
  State<_CaptureId> createState() => _CaptureIdState();
}

class _CaptureIdState extends State<_CaptureId> {
  late var _image = widget.image;
  bool _busy = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2100,
        imageQuality: 88,
      );
      if (file == null) return;
      if (await file.length() > AmigoVerificationRepository.maxImageBytes) {
        throw const FormatException('Choose a JPG or PNG image of up to 8 MB.');
      }
      final bytes = await file.readAsBytes();
      if (AmigoVerificationRepository.imageType(bytes) == null) {
        throw const FormatException('Choose a JPG or PNG image.');
      }
      if (mounted) setState(() => _image = bytes);
    } on FormatException catch (exception) {
      if (mounted) setState(() => _error = exception.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open the image. Check your camera or photo permission.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = widget.front ? 'front' : 'back';
    final camera =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      appBar: _heading(
        context,
        'Capture ${widget.front ? 'Front' : 'Back'} of ID',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
        children: [
          const _VerificationSteps(stage: 0),
          const SizedBox(height: 36),
          FilledButton(
            onPressed: _busy
                ? null
                : () =>
                      _pick(camera ? ImageSource.camera : ImageSource.gallery),
            style: FilledButton.styleFrom(
              backgroundColor: amigoCream,
              foregroundColor: amigoInk,
              minimumSize: const Size(0, 202),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _image == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset('${_art}id_capture_camera.svg'),
                      const SizedBox(height: 10),
                      Text(
                        camera
                            ? 'Align the $side of your ID'
                            : 'Choose a photo of the $side of your ID',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.memory(
                      _image!,
                      height: 186,
                      fit: BoxFit.contain,
                      semanticLabel: 'Selected $side of ID',
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          const _VerificationNote(
            text: 'Make sure the text is sharp and readable',
          ),
          if (camera) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: amigoInk,
                minimumSize: const Size(0, 44),
                side: const BorderSide(color: amigoBorder),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                children: [
                  Expanded(child: Text('Upload a photo instead')),
                  Icon(Icons.chevron_right),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_error!)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 0, 24, 22),
        child: Align(
          alignment: Alignment.centerRight,
          heightFactor: 1,
          child: OutlinedButton(
            onPressed: _busy || _image == null
                ? null
                : () => Navigator.pop(context, _image),
            style: OutlinedButton.styleFrom(
              backgroundColor: _noticeColor,
              foregroundColor: amigoRust,
              minimumSize: const Size(154, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.front ? 'Next' : 'Finish',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (widget.front) ...[
                  const SizedBox(width: 10),
                  SvgPicture.asset('${_art}id_next.svg'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerificationSteps extends StatelessWidget {
  const _VerificationSteps({required this.stage});
  final int stage;

  Widget _dot(int index) {
    if (index > stage) {
      return SvgPicture.asset('${_art}id_step_inactive.svg');
    }
    final filled = index < stage;
    return Stack(
      alignment: Alignment.center,
      children: [
        SvgPicture.asset(
          '${_art}id_step_${filled ? 'complete' : 'current'}_background.svg',
        ),
        SvgPicture.asset(
          '${_art}id_step_${filled ? 'complete' : 'current'}.svg',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Stack(
      children: [
        Positioned(
          top: 12,
          left: 52,
          right: 52,
          child: SizedBox(
            height: 1,
            child: Row(
              children: [
                Expanded(
                  child: ColoredBox(
                    color: stage >= 1 ? amigoRust : amigoBorder,
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: stage >= 2 ? amigoRust : amigoBorder,
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, text) in ['Upload', 'Validating', 'Done'].indexed)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      selected: i == stage,
                      label: text,
                      child: _dot(i),
                    ),
                    const SizedBox(height: 4),
                    ExcludeSemantics(
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: i == stage
                              ? FontWeight.w900
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _VerificationNote extends StatelessWidget {
  const _VerificationNote({
    required this.text,
    this.detail,
    this.asset = 'id_clock.svg',
  });
  final String text;
  final String? detail;
  final String asset;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: _noticeColor,
      border: Border.all(color: amigoBorder),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        SvgPicture.asset('$_art$asset'),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
              if (detail != null) Text(detail!),
            ],
          ),
        ),
      ],
    ),
  );
}

class _VerificationButton extends StatelessWidget {
  const _VerificationButton(this.label, this.onPressed);
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: amigoRust,
      minimumSize: const Size(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    child: Text(label),
  );
}
