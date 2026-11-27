import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/device_location.dart';

class AmigoLocationScreen extends StatefulWidget {
  const AmigoLocationScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<AmigoLocationScreen> createState() => _AmigoLocationScreenState();
}

class _AmigoLocationScreenState extends State<AmigoLocationScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _request() async {
    setState(() => _busy = true);
    String message;
    try {
      await requireDeviceLocation();
      if (mounted) widget.onContinue();
      return;
    } on DeviceLocationException catch (error) {
      message = error.message;
    } catch (_) {
      message = 'This device could not enable location. You can continue.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: constraints.maxHeight * .56,
          left: 0,
          right: 0,
          bottom: 0,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFFC6D4AE),
              borderRadius: BorderRadius.vertical(top: Radius.circular(101)),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  children: [
                    Transform.rotate(
                      angle: .031,
                      child: Image.asset(
                        'assets/figma/account/location_map.png',
                        height: (constraints.maxHeight * .33)
                            .clamp(130, 274)
                            .toDouble(),
                        width: 286,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const SizedBox(height: 35),
                    const Text(
                      'Use your location to find a meetup',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF4A2E26),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _message ??
                            'Enable location now or when you use the map.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 288,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFA1472E),
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _busy ? null : _request,
                        child: Text(
                          _busy ? 'Checking…' : 'Turn on location service',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : widget.onContinue,
                      child: const Text('Continue without location'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
