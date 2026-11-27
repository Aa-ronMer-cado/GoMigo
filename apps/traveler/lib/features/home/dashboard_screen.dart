import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../navigation/traveler_ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.onFindMigo,
    required this.onBookings,
  });
  final VoidCallback onFindMigo;
  final VoidCallback onBookings;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: travelerSage,
      elevation: 0,
      title: const Row(
        children: [
          TravelerAsset('dashboard_frame1', size: 37.43, height: 38.12),
          SizedBox(width: 9),
          TravelerAsset('dashboard_frame2', size: 84.71, height: 23.07),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Booking updates',
          onPressed: onBookings,
          icon: const Icon(Icons.notifications_none, color: travelerInk),
        ),
      ],
    ),
    body: SingleChildScrollView(
      child: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 410,
            child: _DestinationCollage(),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 112),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'Good plans.\nGreat company.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    height: 1.26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 21),
                child: Text(
                  'Find things to do and people to share them with.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/figma/dashboard_friends_exploring.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                      const Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xCB4F6B4B)],
                              stops: [.27, 1],
                            ),
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 239),
                        child: const Padding(
                          padding: EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'A LITTLE EXPLORING',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'A lot of connection.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(54, 42, 54, 30),
                child: TravelerButton('Find a Migo', onFindMigo),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _DestinationCollage extends StatefulWidget {
  const _DestinationCollage();
  @override
  State<_DestinationCollage> createState() => _DestinationCollageState();
}

class _DestinationCollageState extends State<_DestinationCollage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = constraints.maxWidth / 402;
      const tiles = [
        ('north', -60.0, -83.0),
        ('west', -59.0, 167.0),
        ('east', 83.0, -120.0),
        ('west', 224.0, -155.0),
        ('center', 85.0, 132.0),
        ('south', 228.0, 95.0),
        ('west', 369.0, 61.0),
      ];
      return ClipRect(
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFFA5A88C)),
              ),
              for (final (asset, left, top) in tiles)
                Positioned(
                  left: left * s,
                  top: top * s,
                  width: 159 * s,
                  height: 250 * s,
                  child: AnimatedBuilder(
                    animation: _controller,
                    child: Transform.rotate(
                      angle: -.24,
                      child: Image.asset(
                        'assets/figma/dashboard_map_$asset.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    builder: (context, child) {
                      final progress = _controller.value;
                      final offset =
                          14 *
                          const Cubic(.5, 0, .5, 1).transform(
                            progress <= .5 ? progress * 2 : (1 - progress) * 2,
                          );
                      return Transform.translate(
                        offset: Offset(offset * s, -offset * s),
                        child: child,
                      );
                    },
                  ),
                ),
              const Positioned.fill(
                child: ColoredBox(color: Color(0x660A2623)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
