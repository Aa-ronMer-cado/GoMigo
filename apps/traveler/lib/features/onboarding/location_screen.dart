import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/device_location.dart';

import '../../navigation/traveler_ui.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen>
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
    builder: (context, constraints) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: constraints.maxHeight * .55,
            left: 0,
            right: 0,
            bottom: 0,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: travelerSage,
                borderRadius: BorderRadius.vertical(top: Radius.circular(101)),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 30, 26, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.rotate(
                    angle: .031,
                    child: Image.asset(
                      'assets/figma/location_travelers_mystery_map_icon_png1.png',
                      width: 286,
                      height: (constraints.maxHeight * .33)
                          .clamp(130, 274)
                          .toDouble(),
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'Use your location to find a meetup',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: travelerInk,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _message ??
                          'GoMigo needs your location to find nearby Amigos and meetups.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TravelerButton(
                    _busy ? 'Checking…' : _settings?.label ?? 'Allow location',
                    _busy
                        ? null
                        : () {
                            if (_settings case final settings?) {
                              unawaited(_openSettings(settings));
                            } else {
                              unawaited(_check(requestPermission: true));
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
