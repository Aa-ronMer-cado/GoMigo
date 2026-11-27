import 'package:flutter/material.dart';

import 'booking_widgets.dart';

class AmigoDeclineScreen extends StatefulWidget {
  const AmigoDeclineScreen({super.key, required this.travelerName});

  final String travelerName;

  @override
  State<AmigoDeclineScreen> createState() => _AmigoDeclineScreenState();
}

class _AmigoDeclineScreenState extends State<AmigoDeclineScreen> {
  static const _reasons = [
    "I'm unavailable at that time",
    'The location is outside my service area',
    "I'm unable to accommodate this request",
    'The request details are unclear',
    'Other reason',
  ];

  final _note = TextEditingController();
  String? _selected;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _confirm() {
    final details = _note.text.trim();
    Navigator.pop(
      context,
      [_selected!, if (details.isNotEmpty) details].join('\n'),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
        children: [
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Why are you '),
                TextSpan(
                  text: 'declining?',
                  style: TextStyle(color: bookingRust),
                ),
              ],
            ),
            style: TextStyle(
              color: bookingInk,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose a reason to share with the Traveler.',
            style: TextStyle(color: bookingMuted),
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF1E3D5),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              'Booking request from ${widget.travelerName}',
              style: const TextStyle(
                color: bookingInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            'Select a reason',
            style: TextStyle(color: bookingInk, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final reason in _reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: BookingRadioTile(
                title: reason,
                selected: _selected == reason,
                onTap: () => setState(() => _selected = reason),
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'Additional note (optional)',
            style: TextStyle(color: bookingInk, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: _note,
            maxLength: 380,
            minLines: 2,
            maxLines: 3,
            decoration: bookingInput(
              'Add a short explanation for the Traveler…',
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: bookingOutlineStyle(),
                  child: const Text('Go back'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _selected == null ? null : _confirm,
                  style: bookingPrimaryStyle(),
                  child: const Text('Confirm decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
