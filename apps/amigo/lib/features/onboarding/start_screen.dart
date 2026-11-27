import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gomigo_shared_widgets/gomigo_shared_widgets.dart';

class AmigoStartScreen extends StatefulWidget {
  const AmigoStartScreen({super.key, required this.onContinue});
  final VoidCallback onContinue;

  @override
  State<AmigoStartScreen> createState() => _AmigoStartScreenState();
}

class _AmigoStartScreenState extends State<AmigoStartScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _brand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3220),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _brand.stop();
    } else if (!_brand.isAnimating) {
      _brand.repeat();
    }
  }

  @override
  void dispose() {
    _brand.dispose();
    super.dispose();
  }

  Widget _motion(
    int index,
    double begin,
    double finish, {
    bool wordmark = false,
  }) => AnimatedBuilder(
    animation: _brand,
    child: SvgPicture.asset('assets/figma/account/start_motion_$index.svg'),
    builder: (context, child) {
      final progress = const Cubic(
        0,
        0,
        .58,
        1,
      ).transform(((_brand.value - begin) / (finish - begin)).clamp(0.0, 1.0));
      return Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, (wordmark ? 12 : 13) * (1 - progress)),
          child: Transform.scale(
            scale: 1 - (wordmark ? .04 : .18) * (1 - progress),
            child: child,
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    // Insets and timing are relative to the two Figma logo frames.
    const pieces = [
      (.3878, .5248, .0009, .0, .09938, .20497),
      (.5058, .0, .0, .3943, .14907, .25466),
      (.0796, .5263, .5062, .0, .0, .10559),
      (.1241, .0661, .5313, .3997, .04969, .15528),
      (.3871, .1955, .3994, .5871, .19876, .30435),
      (.0, .45, .9099, .4471, .24845, .35404),
      (.2754, .014, .6537, .9073, .34783, .45342),
      (.0422, .2917, .8708, .6276, .29814, .40373),
      (.1349, .1353, .787, .7932, .39752, .50311),
    ];
    const width = 238.0;
    const height = 242.385;
    return Material(
      color: const Color(0xFFFAEFE5),
      child: Semantics(
        label: 'Continue to GoMigo',
        button: true,
        onTap: widget.onContinue,
        child: InkWell(
          onTap: widget.onContinue,
          excludeFromSemantics: true,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: MediaQuery.disableAnimationsOf(context)
                  ? const GoMigoBrand()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: width,
                          height: height,
                          child: Stack(
                            children: [
                              for (final (
                                    i,
                                    (top, right, bottom, left, begin, finish),
                                  )
                                  in pieces.indexed)
                                Positioned(
                                  top: top * height,
                                  right: right * width,
                                  bottom: bottom * height,
                                  left: left * width,
                                  child: _motion(i, begin, finish),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 31.045),
                        SizedBox(
                          width: 282,
                          height: 76.802,
                          child: _motion(9, .51242, .65217, wordmark: true),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
