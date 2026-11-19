import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onFindMigo});

  final VoidCallback onFindMigo;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final height = constraints.maxHeight;
      return Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _DashboardMapPainter()),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 58,
            child: Container(
              color: const Color(0xFFC6D4AE),
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                      width: 38,
                      height: 38,
                      child: SvgPicture.asset(
                          'assets/figma/dashboard_frame1.svg')),
                  const SizedBox(width: 9),
                  SizedBox(
                      width: 85,
                      height: 24,
                      child: SvgPicture.asset(
                          'assets/figma/dashboard_frame2.svg')),
                  const Spacer(),
                  const Icon(Icons.notifications_none,
                      color: Color(0xFF4A2E26), size: 24),
                ],
              ),
            ),
          ),
          Positioned(
            top: height * 0.196,
            left: 10,
            right: 10,
            child: const Text(
              'Good plans.\nGreat company.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF4C2E24),
                fontSize: 42,
                height: 1.28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            top: height * 0.337,
            left: 16,
            right: 16,
            child: const Text(
              'Find things to do and people to share them with.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF4A2E26), fontSize: 15),
            ),
          ),
          Positioned(
            top: height * 0.412,
            left: 22,
            right: 16,
            height: height * 0.274,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/figma/dashboard_friends_exploring.png',
                      fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB66E8968)],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDFA),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                              width: 16,
                              height: 16,
                              child: SvgPicture.asset(
                                  'assets/figma/dashboard_users.svg')),
                          const SizedBox(width: 7),
                          const Text('12 Migos nearby',
                              style: TextStyle(
                                  color: Color(0xFF4E3025),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 20,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('A LITTLE EXPLORING',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 3),
                        Text('A lot of connection.',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 55,
            right: 55,
            top: height * 0.735,
            height: 52,
            child: FilledButton(
              onPressed: onFindMigo,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFA84B32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              child: const Text('Find a Migo'),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 111,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFFFF8F0),
                border: Border(top: BorderSide(color: Color(0xFFD9C7B6))),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _NavIcon(
                      path: 'assets/figma/dashboard_home.svg', selected: true),
                  _NavIcon(path: 'assets/figma/dashboard_calendar_plus.svg'),
                  _NavIcon(path: 'assets/figma/dashboard_history.svg'),
                  const Icon(Icons.chat_bubble_outline,
                      size: 23, color: Color(0xFF332D29)),
                  _NavIcon(path: 'assets/figma/dashboard_user.svg'),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.path, this.selected = false});

  final String path;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = SvgPicture.asset(path, width: 26, height: 26);
    return SizedBox(
      width: 26,
      height: 26,
      child: selected
          ? ColorFiltered(
              colorFilter:
                  const ColorFilter.mode(Color(0xFFA84B32), BlendMode.srcIn),
              child: icon,
            )
          : icon,
    );
  }
}

class _DashboardMapPainter extends CustomPainter {
  const _DashboardMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFD9D9D9), BlendMode.src);
    final road = Paint()
      ..color = const Color(0xFFFAEFE5)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;
    for (var i = -2; i < 8; i++) {
      final x = i * 110.0;
      canvas.drawLine(
          Offset(x, 0), Offset(x + size.height * 0.32, size.height), road);
    }
    for (var i = -1; i < 4; i++) {
      final y = i * 240.0 + 80;
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 100), road);
    }
  }

  @override
  bool shouldRepaint(covariant _DashboardMapPainter oldDelegate) => false;
}
