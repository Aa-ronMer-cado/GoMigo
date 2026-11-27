import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../navigation/traveler_ui.dart';

class WalkthroughScreen extends StatefulWidget {
  const WalkthroughScreen({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends State<WalkthroughScreen> {
  int _page = 0;

  static const _slides = [
    (
      'Find a Local Buddy',
      'Connect with verified local Amigos who can join you on your trip, your way.',
      'walkthrough_rectangle12.png',
      'walkthrough_frame16.svg',
    ),
    (
      'Book and Explore',
      'Choose your date, make your own plans, and explore with your Amigo.',
      'walkthrough_book.png',
      'walkthrough_dots2.svg',
    ),
    (
      'Travel with Confidence',
      'Check your Amigo’s profile and reviews before booking.',
      'walkthrough_confidence.png',
      'walkthrough_dots3.svg',
    ),
  ];

  void _next() {
    if (_page == _slides.length - 1) {
      widget.onContinue();
    } else {
      setState(() => _page += 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, description, art, indicator) = _slides[_page];
    final last = _page == _slides.length - 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            (constraints.maxHeight * .137).clamp(35, 120).toDouble(),
            22,
            24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 362),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/figma/$art',
                    width: 264,
                    height: 295,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(height: 31),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: travelerInk,
                      fontSize: 32,
                      height: 1.25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: travelerInk,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Center(
                    child: SvgPicture.asset(
                      'assets/figma/$indicator',
                      width: 93,
                      height: 39,
                    ),
                  ),
                  const SizedBox(height: 34),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: widget.onContinue,
                          style: TextButton.styleFrom(
                            foregroundColor: travelerInk,
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _next,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: travelerRust,
                            backgroundColor: const Color(0xFFF3E6DA),
                            side: const BorderSide(
                              color: travelerRust,
                              width: 1.5,
                            ),
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              Text(last ? 'Get Started' : 'Next'),
                              if (!last)
                                const Icon(Icons.arrow_forward, size: 19),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
