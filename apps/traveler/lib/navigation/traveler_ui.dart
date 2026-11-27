import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const travelerInk = Color(0xFF4A2E26);
const travelerSage = Color(0xFFC6D4AE);
const travelerCream = Color(0xFFFFF8F0);
const travelerBorder = Color(0xFFD9C7B6);
const travelerRust = Color(0xFFA1472E);

AppBar travelerHeader(
  String title, {
  Color color = travelerSage,
  VoidCallback? onBack,
}) => AppBar(
  title: Text(title),
  leading: onBack == null
      ? null
      : IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const TravelerAsset('finding_chevron_backward'),
        ),
  titleTextStyle: const TextStyle(
    color: travelerInk,
    fontSize: 18,
    fontWeight: FontWeight.w900,
  ),
  backgroundColor: color,
  foregroundColor: travelerInk,
  elevation: 0,
);

InputDecoration travelerField(String label, {String? hint}) => InputDecoration(
  labelText: label,
  hintText: hint,
  filled: true,
  fillColor: travelerCream,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(15),
    borderSide: const BorderSide(color: travelerBorder),
  ),
);

class TravelerButton extends StatelessWidget {
  const TravelerButton(this.label, this.onPressed, {super.key});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: travelerRust,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 52),
      visualDensity: VisualDensity.standard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

class TravelerCard extends StatelessWidget {
  const TravelerCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: travelerCream,
      border: Border.all(color: travelerBorder),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class TravelerError extends StatelessWidget {
  const TravelerError(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}

class TravelerAsset extends StatelessWidget {
  const TravelerAsset(
    this.name, {
    super.key,
    this.size = 24,
    this.height,
    this.color,
  });
  final String name;
  final double size;
  final double? height;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: height ?? size,
    child: SvgPicture.asset(
      'assets/figma/$name.svg',
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    ),
  );
}

String pesos(Object? cents) =>
    '₱${((cents as num? ?? 0) / 100).toStringAsFixed(2)}';
String statusLabel(String value) =>
    value.isEmpty ? '' : '${value[0].toUpperCase()}${value.substring(1)}';

void notifyTraveler(BuildContext context, String message) =>
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
