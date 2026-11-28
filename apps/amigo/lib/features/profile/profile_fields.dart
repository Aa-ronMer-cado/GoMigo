import 'package:flutter/material.dart';

import '../../navigation/amigo_ui.dart';

const profileRateLabel = 'Hourly rate (₱)';

const _interestOptions = [
  'Food & Dining',
  'Nature & Adventure',
  'Shopping',
  'Photography',
  'Nightlife',
  'Local Culture',
  'Arts & Museums',
  'Outdoor Activities',
  'Local Experiences',
];

Set<String> profileInterests(Map<String, dynamic>? profile) =>
    (profile?['interests'] as List? ?? []).whereType<String>().toSet();

String profileRate(Object? value) =>
    value is num ? (value / 100).toStringAsFixed(2) : '';

int? profileRateCentavos(String value) {
  final input = value.trim();
  if (!RegExp(r'^\d{1,6}(\.\d{1,2})?$').hasMatch(input)) return null;
  final parts = input.split('.');
  return int.parse(parts.first) * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
}

String? validateProfileRate(String? value) {
  final cents = profileRateCentavos(value ?? '');
  return cents == null || cents < 20000 || cents > 150000
      ? 'Enter ₱200 to ₱1,500, with up to two decimal places.'
      : null;
}

String? validateProfileDescription(String? value) {
  final description = value?.trim() ?? '';
  if (description.isEmpty || description.split(RegExp(r'\s+')).length < 30) {
    return 'Write at least 30 words.';
  }
  return description.characters.length > 1500
      ? 'Use at most 1,500 characters.'
      : null;
}

class ProfileInterestChips extends StatelessWidget {
  const ProfileInterestChips({
    super.key,
    required this.interests,
    required this.onSelected,
  });

  final Set<String> interests;
  final void Function(String interest, bool selected)? onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final interest in {..._interestOptions, ...interests})
        FilterChip(
          label: Text(interest),
          selected: interests.contains(interest),
          selectedColor: amigoSage,
          onSelected: onSelected == null
              ? null
              : (selected) => onSelected!(interest, selected),
        ),
    ],
  );
}

class ProfileTextField extends StatelessWidget {
  const ProfileTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.validate,
    this.enabled = true,
    this.hint,
    this.lines = 1,
    this.keyboard,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?) validate;
  final bool enabled;
  final String? hint;
  final int lines;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboard,
      textCapitalization: keyboard == null
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: amigoCream,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: amigoBorder),
        ),
      ),
      validator: validate,
    ),
  );
}

ButtonStyle profileSaveStyle() => FilledButton.styleFrom(
  backgroundColor: amigoRust,
  minimumSize: const Size(0, 50),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);
