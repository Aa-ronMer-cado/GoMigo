import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../navigation/traveler_ui.dart';

class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  bool _busy = false;
  String? _notice;

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted)
          setState(
            () => _notice =
                'Location services are off. You can continue and turn them on later.',
          );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (!mounted) return;
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        widget.onContinue();
      } else {
        setState(
          () => _notice =
              'Location permission is off. You can continue and enable it when you need the map.',
        );
      }
    } catch (_) {
      if (mounted)
        setState(
          () => _notice =
              'Location is unavailable on this device. You can continue.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  Text(
                    _notice ??
                        'You can enable location now or when you use the map.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  TravelerButton(
                    _busy ? 'Checking…' : 'Turn on location service',
                    _busy ? null : _request,
                  ),
                  TextButton(
                    onPressed: _busy ? null : widget.onContinue,
                    child: const Text('Continue without location'),
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
