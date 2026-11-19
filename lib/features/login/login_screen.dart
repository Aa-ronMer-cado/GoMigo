import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFF9F3E6)),
        Opacity(
          opacity: 0.4,
          child: Image.asset('assets/figma/login_sign_up.png', fit: BoxFit.cover),
        ),
        SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
            child: Column(
              children: [
                const SizedBox(height: 66),
                SizedBox(
                  width: 308,
                  height: 14,
                  child: SvgPicture.asset('assets/figma/login_group2.svg', fit: BoxFit.fill),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 304,
                  height: 85.4,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        width: 84,
                        height: 85.4,
                        child: SvgPicture.asset('assets/figma/login_frame1.svg'),
                      ),
                      Positioned(
                        left: 112,
                        top: 17,
                        width: 190,
                        height: 52,
                        child: SvgPicture.asset('assets/figma/login_frame2.svg'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 39),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    children: const [
                      _InputField(label: 'Full Name', hint: 'Enter your username'),
                      _InputField(label: 'Email Address', hint: 'Enter your username'),
                      _InputField(label: 'Mobile Number', hint: 'Enter your username', extraHeight: 13),
                      _InputField(label: 'Password', hint: 'Enter Password', obscure: true),
                      _InputField(label: 'Confirm Password', hint: 'Confirm Password', obscure: true),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 274,
                  height: 52,
                  child: FilledButton(
                    onPressed: onContinue,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFA64E31),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    child: const Text('Sign Up'),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    required this.hint,
    this.obscure = false,
    this.extraHeight = 0,
  });

  final String label;
  final String hint;
  final bool obscure;
  final double extraHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: (obscure ? 107 : 99) + extraHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: obscure ? 34 : 34,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF4C2E24),
                  fontSize: 16.97,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 63,
            child: TextField(
              obscureText: obscure,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF5C706F), fontSize: 19.4),
                filled: true,
                fillColor: const Color(0xFFFFFDFA),
                contentPadding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
                suffixIcon: obscure
                    ? const Icon(Icons.visibility_off_outlined, color: Color(0xFF5C706F), size: 22)
                    : null,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: const BorderSide(color: Color(0xFFB9C9C4), width: 1.2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(17),
                  borderSide: const BorderSide(color: Color(0xFFA64E31), width: 1.2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
