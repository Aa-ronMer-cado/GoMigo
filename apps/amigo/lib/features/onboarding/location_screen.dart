import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/device_location.dart';

class AmigoLocationScreen extends StatefulWidget {
  const AmigoLocationScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<AmigoLocationScreen> createState() => _AmigoLocationScreenState();
}

class _AmigoLocationScreenState extends State<AmigoLocationScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _advanced = false;
  String? _message;
  DeviceLocationSettings? _settings;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check({bool requestPermission = false}) async {
    if (_busy || _advanced) return;
    setState(() => _busy = true);
    String message;
    DeviceLocationSettings? settings;
    try {
      await requireDeviceLocation(requestPermission: requestPermission);
      await readDevicePosition();
      if (!mounted) return;
      _advanced = true;
      widget.onContinue();
      return;
    } on DeviceLocationException catch (error) {
      message = error.message;
      settings = error.settings;
    } catch (_) {
      message = 'Could not check location. Check your settings and try again.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _message = message;
        // Android can report a permanent denial only when a request is made.
        if (requestPermission ||
            _settings != DeviceLocationSettings.app ||
            settings != null) {
          _settings = settings;
        }
      });
    }
  }

  Future<void> _openSettings(DeviceLocationSettings settings) async {
    if (await openDeviceLocationSettings(settings) || !mounted) return;
    setState(() => _message = 'Open device settings to enable location.');
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
                            'GoMigo needs your location for service areas and meetups.',
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
                        onPressed: _busy
                            ? null
                            : () {
                                if (_settings case final settings?) {
                                  unawaited(_openSettings(settings));
                                } else {
                                  unawaited(_check(requestPermission: true));
                                }
                              },
                        child: Text(
                          _busy
                              ? 'Checking…'
                              : _settings?.label ?? 'Allow location',
                        ),
                      ),
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
