import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'amigo_booking_repository.dart';

const bookingInk = Color(0xFF4A2E26);
const bookingRust = Color(0xFFA84B32);
const bookingSage = Color(0xFFC6D4AE);
const bookingGreen = Color(0xFF507259);
const bookingMuted = Color(0xFF78655B);
const bookingBorder = Color(0xFFD9C7B6);
const bookingCream = Color(0xFFFFF8F0);
const bookingPaper = Color(0xFFFFFCFA);

const bookingGradient = LinearGradient(
  colors: [bookingInk, bookingRust],
  stops: [.48, 1],
);

SvgPicture bookingAsset(String name) => SvgPicture.asset(
  'assets/figma/booking/$name.svg',
  excludeFromSemantics: true,
);

AppBar bookingHeader(BuildContext context, String title) => AppBar(
  backgroundColor: bookingSage,
  foregroundColor: bookingInk,
  elevation: 0,
  centerTitle: false,
  automaticallyImplyLeading: false,
  leading: Navigator.of(context).canPop()
      ? IconButton(
          tooltip: 'Back',
          onPressed: Navigator.of(context).maybePop,
          icon: bookingAsset('chevron_back'),
        )
      : null,
  titleTextStyle: const TextStyle(
    color: bookingInk,
    fontSize: 19,
    fontWeight: FontWeight.w900,
  ),
  title: Text(title),
);

ButtonStyle bookingPrimaryStyle({double height = 48}) => FilledButton.styleFrom(
  backgroundColor: bookingRust,
  foregroundColor: Colors.white,
  minimumSize: Size(0, height),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
  textStyle: const TextStyle(fontWeight: FontWeight.w800),
);

ButtonStyle bookingOutlineStyle({double height = 48}) =>
    OutlinedButton.styleFrom(
      backgroundColor: bookingPaper,
      foregroundColor: bookingRust,
      minimumSize: Size(0, height),
      side: const BorderSide(color: bookingBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    );

InputDecoration bookingInput(String hint) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: bookingCream,
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: bookingBorder),
  ),
);

String bookingPesos(int amount) {
  final digits = (amount.abs() ~/ 100).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final decimals = (amount.abs() % 100).toString().padLeft(2, '0');
  return '${amount < 0 ? '−' : ''}₱$digits.$decimals';
}

DateTime bookingPhilippineTime(DateTime value) =>
    value.toUtc().add(const Duration(hours: 8));

String bookingTime(BuildContext context, DateTime value) =>
    TimeOfDay.fromDateTime(bookingPhilippineTime(value)).format(context);

String bookingDate(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(
      context,
    ).formatShortDate(bookingPhilippineTime(value));

String bookingSchedule(BuildContext context, AmigoBooking booking) {
  final starts = booking.startsAt;
  final ends = booking.endsAt;
  final crossesMidnight = !DateUtils.isSameDay(
    bookingPhilippineTime(starts),
    bookingPhilippineTime(ends),
  );
  return '${bookingDate(context, starts)}  •  ${bookingTime(context, starts)} – '
      '${crossesMidnight ? '${bookingDate(context, ends)}  •  ' : ''}'
      '${bookingTime(context, ends)} PHT';
}

String bookingStatus(String status) => switch (status) {
  'pending' => 'Pending',
  'accepted' => 'Accepted',
  'declined' => 'Declined',
  'cancelled' => 'Cancelled',
  'completed' => 'Completed',
  'paid' => 'Paid',
  'unpaid' => 'Unpaid',
  'failed' => 'Failed',
  _ => status,
};

String bookingError(Object error, String fallback) =>
    error is PostgrestException &&
        const {'23P01', 'P0001', '42501'}.contains(error.code)
    ? error.message
    : fallback;

class BookingRetry extends StatelessWidget {
  const BookingRetry(this.message, {super.key, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(message),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}

class BookingAvatar extends StatelessWidget {
  const BookingAvatar(this.name, {super.key, this.radius = 25});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final names = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    final initials = [
      for (final word in names.take(2)) word.characters.first,
    ].join();
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFE3CFBE),
        foregroundColor: bookingInk,
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(fontSize: radius * .72, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class BookingRadioTile extends StatelessWidget {
  const BookingRadioTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    enabled: onTap != null,
    child: Material(
      color: selected ? const Color(0xFFF2F6EC) : bookingCream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? bookingSage : bookingBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  bookingAsset(selected ? 'radio_selected' : 'radio_idle'),
                  if (selected) bookingAsset('radio_center'),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: bookingInk)),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: bookingMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
