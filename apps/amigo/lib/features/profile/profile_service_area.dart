import 'package:flutter/material.dart';
import 'package:gomigo_shared_widgets/device_location.dart';

import 'service_area.dart';

class ProfileServiceArea extends StatefulWidget {
  const ProfileServiceArea({
    super.key,
    this.savedArea,
    this.detectArea,
    required this.onChanged,
    this.enabled = true,
  });

  final String? savedArea;
  final Future<ServiceArea> Function()? detectArea;
  final ValueChanged<ServiceArea?> onChanged;
  final bool enabled;

  @override
  State<ProfileServiceArea> createState() => _ProfileServiceAreaState();
}

class _ProfileServiceAreaState extends State<ProfileServiceArea>
    with WidgetsBindingObserver {
  ServiceArea? _area;
  String? _error;
  DeviceLocationSettings? _settings;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLocation());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkLocation();
  }

  void _checkLocation() {
    if (mounted &&
        widget.detectArea == null &&
        ModalRoute.isCurrentOf(context) != false) {
      _detect(requestPermission: false);
    }
  }

  Future<void> _detect({required bool requestPermission}) async {
    if (_locating || !widget.enabled) return;
    setState(() {
      _locating = true;
      _area = null;
      _error = null;
      _settings = null;
    });
    widget.onChanged(null);
    try {
      final area =
          await (widget.detectArea?.call() ??
              detectServiceArea(requestPermission: requestPermission));
      if (!mounted) return;
      setState(() => _area = area);
      widget.onChanged(area);
    } on DeviceLocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _settings = error.settings;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not detect your service area. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _openSettings(DeviceLocationSettings settings) async {
    if (await openDeviceLocationSettings(settings) || !mounted) return;
    setState(
      () => _error = 'Open device settings to enable location for GoMigo.',
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Service area', style: TextStyle(fontWeight: FontWeight.bold)),
      if (widget.savedArea case final saved?)
        Text(_area == null ? saved : 'Saved area: $saved'),
      if (_area case final area?) Text(area.name),
      OutlinedButton.icon(
        onPressed: _locating || !widget.enabled
            ? null
            : () => _detect(requestPermission: true),
        icon: const Icon(Icons.my_location),
        label: Text(_locating ? 'Detecting location…' : 'Use Current Location'),
      ),
      const Text('Your approximate service area is visible to travelers.'),
      if (_error case final error?)
        Semantics(liveRegion: true, child: Text(error)),
      if (_settings case final settings?)
        TextButton(
          onPressed: widget.enabled ? () => _openSettings(settings) : null,
          child: Text(settings.label),
        ),
    ],
  );
}
