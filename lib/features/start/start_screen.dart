import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onContinue,
      child: const ColoredBox(
        color: Color(0xFFFAEFE5),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 238,
                height: 242.385,
                child: _BrandMark(),
              ),
              SizedBox(height: 31),
              SizedBox(
                width: 282,
                height: 76.802,
                child: _BrandWordmark(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/figma/start_frame1.svg',
        fit: BoxFit.fill,
      );
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/figma/start_frame2.svg',
        fit: BoxFit.fill,
      );
}
