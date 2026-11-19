import 'package:flutter/material.dart';

class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      final width = constraints.maxWidth;
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFFFAEFE5)),
          Positioned(
            top: height * 0.56,
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFC6D4AE),
                borderRadius: BorderRadius.vertical(top: Radius.circular(101)),
              ),
            ),
          ),
          Positioned(
            top: height * 0.405,
            left: (width - 286) / 2,
            child: Transform.rotate(
              angle: 0.031,
              child: Image.asset(
                'assets/figma/location_travelers_mystery_map_icon_png1.png',
                width: 286,
                height: 274,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            top: height * 0.758,
            left: 23,
            right: 23,
            child: const Text(
              'We need your location so you can\nuse the app properly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF4D2F24),
                fontSize: 21.8,
                height: 1.38,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            top: height * 0.827,
            left: 18,
            right: 18,
            child: const Text(
              'Can you please turn on your location service?',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF323232), fontSize: 15),
            ),
          ),
          Positioned(
            left: 57,
            right: 57,
            bottom: 43,
            height: 52,
            child: FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFA64E31),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: const Text('Turn on location service'),
            ),
          ),
        ],
      );
    });
  }
}
