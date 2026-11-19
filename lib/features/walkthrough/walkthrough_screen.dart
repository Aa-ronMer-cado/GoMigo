import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WalkthroughScreen extends StatefulWidget {
  const WalkthroughScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  State<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends State<WalkthroughScreen> {
  int _page = 0;

  static const _titles = [
    'Find a Local Buddy',
    'Book and Explore',
    'Travel with Confidence',
  ];
  static const _descriptions = [
    'Connect with verified local Amigos who can join you on your trip, your way',
    'Choose your preferred date, plan your activities, and explore hidden gems with you Amigo',
    'All Amigos are verified so you can enjoy a safer and more reliable experience.',
  ];
  static const _artworks = [
    'assets/figma/walkthrough_rectangle12.png',
    'assets/figma/walkthrough_book.png',
    'assets/figma/walkthrough_confidence.png',
  ];
  static const _indicators = [
    'assets/figma/walkthrough_frame16.svg',
    'assets/figma/walkthrough_dots2.svg',
    'assets/figma/walkthrough_dots3.svg',
  ];

  void _next() {
    if (_page == 2) {
      widget.onContinue();
    } else {
      setState(() => _page += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final gap = width * 0.092;
      final buttonWidth = width < 347 ? (width - gap) / 2 : 155.0;
      final buttonRowWidth = buttonWidth * 2 + gap;
      return ColoredBox(
        color: const Color(0xFFFAEFE5),
        child: Column(
          children: [
            const SizedBox(height: 120),
            SizedBox(
              width: 264,
              height: 295,
              child: Image.asset(_artworks[_page], fit: BoxFit.contain),
            ),
            const SizedBox(height: 31),
            Text(
              _titles[_page],
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF4C2E24),
                fontSize: 32,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 35),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 27),
              child: Text(
                _descriptions[_page],
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF4C2E24), fontSize: 16, height: 1.5),
              ),
            ),
            const SizedBox(height: 35),
            SizedBox(
              width: 93,
              height: 39,
              child: SvgPicture.asset(_indicators[_page]),
            ),
            const Spacer(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: (width - buttonRowWidth) / 2),
              child: Row(
                children: [
                  SizedBox(
                    width: buttonWidth,
                    child: TextButton(
                      onPressed: widget.onContinue,
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF4A2E26)),
                      child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  SizedBox(width: gap),
                  SizedBox(
                    width: buttonWidth,
                    child: OutlinedButton(
                      onPressed: _next,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFA84B32),
                        backgroundColor: const Color(0xFFF3E6DA),
                        side: const BorderSide(color: Color(0xFFA84B32), width: 1.5),
                        fixedSize: Size(buttonWidth, 52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_page == 2 ? 'Get Started' : 'Next'),
                          if (_page < 2) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 19),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 120),
          ],
        ),
      );
    });
  }
}
