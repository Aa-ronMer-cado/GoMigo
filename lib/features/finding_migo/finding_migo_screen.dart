import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class FindingMigoScreen extends StatefulWidget {
  const FindingMigoScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<FindingMigoScreen> createState() => _FindingMigoScreenState();
}

class _FindingMigoScreenState extends State<FindingMigoScreen> {
  String _activity = 'Coffee & conversation';
  String _area = 'Coffee & conversation';

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFAEFE5),
      child: Column(
        children: [
          SizedBox(
            height: 53,
            child: Container(
              color: const Color(0xFFC6D4AE),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: widget.onBack,
                    child: SizedBox(
                      width: 22,
                      height: 26,
                      child: SvgPicture.asset('assets/figma/finding_chevron_backward.svg'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Find a Migo',
                    style: TextStyle(color: Color(0xFF4A2E26), fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'What do you want to do today?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF4A2E26), fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(child: _FilterButton(value: _activity, onTap: () => setState(() => _activity = _activity == 'Coffee & conversation' ? 'Food & hidden gems' : 'Coffee & conversation'))),
                const SizedBox(width: 20),
                Expanded(child: _FilterButton(value: _area, onTap: () => setState(() => _area = _area == 'Coffee & conversation' ? 'Near me' : 'Coffee & conversation'))),
              ],
            ),
          ),
          const SizedBox(height: 41),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 17, 50),
              children: const [
                _MigoCard(
                  name: 'Katricia A.',
                  photo: 'assets/figma/finding_rectangle16.png',
                  languages: 'EN, FR, ES',
                ),
                SizedBox(height: 10),
                _MigoCard(
                  name: 'Jeo Ong',
                  photo: 'assets/figma/finding_rectangle17.png',
                  languages: 'EN, PH',
                  heart: 'assets/figma/finding_heart1.svg',
                  languageIcon: 'assets/figma/finding_language1.svg',
                  star: 'assets/figma/finding_star_filled1.svg',
                ),
                SizedBox(height: 10),
                _MigoCard(
                  name: 'Katricia A.',
                  photo: 'assets/figma/finding_rectangle18.png',
                  languages: 'EN, FR, ES',
                ),
                SizedBox(height: 10),
                _MigoCard(
                  name: 'Maya R.',
                  photo: 'assets/figma/finding_rectangle16.png',
                  languages: 'EN, PH',
                ),
              ],
            ),
          ),
          const _FindingNavigation(),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 41,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F0),
          border: Border.all(color: const Color(0xFFD9C7B6)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF4A2E26), fontSize: 11.5)),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 16, height: 16, child: SvgPicture.asset('assets/figma/finding_chevron_down.svg')),
          ],
        ),
      ),
    );
  }
}

class _MigoCard extends StatefulWidget {
  const _MigoCard({
    required this.name,
    required this.photo,
    required this.languages,
    this.heart = 'assets/figma/finding_heart.svg',
    this.languageIcon = 'assets/figma/finding_language.svg',
    this.star = 'assets/figma/finding_star_filled.svg',
  });

  final String name;
  final String photo;
  final String languages;
  final String heart;
  final String languageIcon;
  final String star;

  @override
  State<_MigoCard> createState() => _MigoCardState();
}

class _MigoCardState extends State<_MigoCard> {
  bool _favorite = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 164,
      decoration: BoxDecoration(
        color: const Color(0xFFFDF6EF),
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, -2))],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 26, top: 22, right: 24, bottom: 22),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(widget.photo, width: 122, height: 118, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 0,
                    right: 30,
                    child: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF4C2E24), fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  Positioned(
                    top: 36,
                    left: 0,
                    child: Row(
                      children: [
                        SizedBox(width: 14, height: 14, child: SvgPicture.asset(widget.star)),
                        const SizedBox(width: 5),
                        const Text('4.9', style: TextStyle(color: Color(0xFF4C2E24), fontSize: 12, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 5),
                        const Text('(67)', style: TextStyle(color: Color(0xFF6F5D53), fontSize: 8.7)),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 58,
                    left: 0,
                    child: Text('Food • Hidden Gems', style: const TextStyle(color: Color(0xFF4C2E24), fontSize: 8.8)),
                  ),
                  Positioned(
                    top: 73,
                    left: 0,
                    child: Row(
                      children: [
                        SizedBox(width: 13, height: 13, child: SvgPicture.asset(widget.languageIcon)),
                        const SizedBox(width: 5),
                        Text(widget.languages, style: const TextStyle(color: Color(0xFF4C2E24), fontSize: 8.8)),
                      ],
                    ),
                  ),
                  const Positioned(
                    left: 0,
                    bottom: 1,
                    child: Text('₱ 250/hr', style: TextStyle(color: Color(0xFF4C2E24), fontSize: 15.5, fontWeight: FontWeight.w800)),
                  ),
                  Positioned(
                    right: 0,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _favorite = !_favorite),
                      child: _favorite
                          ? const Icon(Icons.favorite, color: Color(0xFF4A2E26), size: 22)
                          : SizedBox(width: 22, height: 22, child: SvgPicture.asset(widget.heart)),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: 74,
                      height: 30,
                      child: FilledButton(
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Viewing ${widget.name}'))),
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: const Color(0xFFA84B32),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                        child: const Text('View Profile'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindingNavigation extends StatelessWidget {
  const _FindingNavigation();

  @override
  Widget build(BuildContext context) {
    const border = Color(0xFFD9C7B6);
    return Container(
      height: 108,
      decoration: const BoxDecoration(
        color: Color(0xFFFFF8F0),
        border: Border(top: BorderSide(color: border)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 23),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _NavAsset('assets/figma/finding_home.svg'),
          _NavAsset('assets/figma/finding_calendar_plus.svg', selected: true),
          _NavAsset('assets/figma/finding_history.svg'),
          const Icon(Icons.chat_bubble_outline, size: 23, color: Color(0xFF332D29)),
          _NavAsset('assets/figma/finding_user.svg'),
        ],
      ),
    );
  }
}

class _NavAsset extends StatelessWidget {
  const _NavAsset(this.path, {this.selected = false});

  final String path;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = SvgPicture.asset(path, width: 24, height: 24);
    return selected
        ? ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFFA84B32), BlendMode.srcIn), child: icon)
        : icon;
  }
}
