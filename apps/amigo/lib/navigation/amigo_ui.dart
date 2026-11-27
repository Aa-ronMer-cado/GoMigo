import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const amigoInk = Color(0xFF4A2E26);
const amigoSage = Color(0xFFC6D4AE);
const amigoCream = Color(0xFFFFF8F0);
const amigoRust = Color(0xFFA1472E);
const amigoBorder = Color(0xFFD9C7B6);

AppBar amigoHeader(String title, {Widget? leading}) => AppBar(
  title: Text(title),
  leading: leading,
  titleTextStyle: const TextStyle(
    color: amigoInk,
    fontSize: 18,
    fontWeight: FontWeight.w900,
  ),
  backgroundColor: amigoSage,
  foregroundColor: amigoInk,
  elevation: 0,
);

class AmigoBackButton extends StatelessWidget {
  const AmigoBackButton({super.key, this.chat = false});
  final bool chat;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    icon: SvgPicture.asset(
      chat ? 'assets/figma/amigo_chat_back.svg' : 'assets/figma/amigo_back.svg',
    ),
    onPressed: () => Navigator.maybePop(context),
  );
}

class TravelerAvatar extends StatelessWidget {
  const TravelerAvatar({super.key, this.radius = 28});
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFFECE0D5),
    foregroundColor: amigoInk,
    child: Icon(Icons.person_outline, size: radius),
  );
}

void amigoNotice(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

DateTime manilaTime(DateTime utc) => utc.toUtc().add(const Duration(hours: 8));
