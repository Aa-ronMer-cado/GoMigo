import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class GoMigoBrand extends StatelessWidget {
  const GoMigoBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 238,
          height: 242.385,
          child: SvgPicture.asset(
            'assets/figma/start_frame1.svg',
            package: 'gomigo_shared_widgets',
            fit: BoxFit.fill,
          ),
        ),
        const SizedBox(height: 31),
        SizedBox(
          width: 282,
          height: 76.802,
          child: SvgPicture.asset(
            'assets/figma/start_frame2.svg',
            package: 'gomigo_shared_widgets',
            fit: BoxFit.fill,
          ),
        ),
      ],
    );
  }
}
