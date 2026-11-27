import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../navigation/amigo_ui.dart';
import 'account_repository.dart';

class AmigoLoginScreen extends StatefulWidget {
  const AmigoLoginScreen({
    super.key,
    required this.account,
    this.accountNotice,
  });
  final AmigoAccountRepository? account;
  final String? accountNotice;

  @override
  State<AmigoLoginScreen> createState() => _AmigoLoginScreenState();
}

class _AmigoLoginScreenState extends State<AmigoLoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hidePassword = true;
  late String? _notice = widget.accountNotice;

  @override
  void dispose() {
    for (final controller in [_name, _email, _phone, _password, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final account = widget.account;
    if (account == null) {
      setState(
        () => _notice =
            'GoMigo is not configured on this build. Contact the demo organizer.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final signedIn = await account.authenticate(
        email: _email.text.trim(),
        password: _password.text,
        name: _register ? _name.text.trim() : null,
        phone: _register ? _phone.text.trim() : null,
      );
      if (!signedIn && mounted) {
        setState(() {
          _register = false;
          _notice = 'Check your email to confirm your account, then log in.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _notice = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'GoMigo could not connect. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required String hint,
    TextInputType? keyboard,
    bool password = false,
    String? Function(String?)? validate,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(color: amigoInk, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: label,
          child: TextFormField(
            controller: controller,
            keyboardType: keyboard,
            obscureText: password && _hidePassword,
            autocorrect: !password && keyboard == null,
            enabled: !_busy,
            validator: validate,
            decoration: InputDecoration(
              filled: true,
              hintText: hint,
              fillColor: const Color(0xFFFFFDFA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Color(0xFFB6C6BC)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              suffixIcon: password
                  ? IconButton(
                      tooltip: _hidePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () =>
                          setState(() => _hidePassword = !_hidePassword),
                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Color(0xFFF9F3E6)),
      Opacity(
        opacity: .4,
        child: Image.asset(
          'assets/figma/account/auth_background.png',
          fit: BoxFit.cover,
        ),
      ),
      SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: _register ? 28 : 40,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_register)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/figma/account/signup_mark.svg',
                            width: 84,
                            height: 85.4,
                          ),
                          const SizedBox(width: 16),
                          Flexible(
                            child: SvgPicture.asset(
                              'assets/figma/account/signup_wordmark.svg',
                              width: 190,
                              height: 52,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          SvgPicture.asset(
                            'assets/figma/account/login_mark.svg',
                            width: 124.6,
                            height: 126.9,
                          ),
                          const SizedBox(height: 20),
                          SvgPicture.asset(
                            'assets/figma/account/login_wordmark.svg',
                            width: 282,
                            height: 76.8,
                          ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    if (_register)
                      _field(
                        'Full Name',
                        _name,
                        hint: 'Enter your name',
                        validate: (value) =>
                            value!.trim().isEmpty || value.trim().length > 80
                            ? 'Enter a name of up to 80 characters.'
                            : null,
                      ),
                    _field(
                      'Email Address',
                      _email,
                      hint: 'Enter your email',
                      keyboard: TextInputType.emailAddress,
                      validate: (value) => value!.trim().contains('@')
                          ? null
                          : 'Enter an email address.',
                    ),
                    if (_register)
                      _field(
                        'Mobile Number (optional)',
                        _phone,
                        hint: 'Enter your mobile number',
                        keyboard: TextInputType.phone,
                        validate: (value) => value!.length > 25
                            ? 'Enter a shorter phone number.'
                            : null,
                      ),
                    _field(
                      'Password',
                      _password,
                      hint: 'Enter your password',
                      password: true,
                      validate: (value) => value!.length >= (_register ? 8 : 1)
                          ? null
                          : 'Enter ${_register ? 'at least 8 characters' : 'your password'}.',
                    ),
                    if (_register)
                      _field(
                        'Confirm Password',
                        _confirm,
                        hint: 'Confirm your password',
                        password: true,
                        validate: (value) => value == _password.text
                            ? null
                            : 'Passwords must match.',
                      ),
                    if (_notice != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _notice!,
                            style: const TextStyle(
                              color: amigoInk,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    Center(
                      child: SizedBox(
                        width: 274,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: amigoRust,
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _busy ? null : _submit,
                          child: Text(
                            _busy
                                ? 'Please wait…'
                                : _register
                                ? 'Sign Up'
                                : 'Log In',
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _register = !_register;
                              _notice = null;
                            }),
                      child: Text(
                        _register
                            ? 'Already have an account? Log In'
                            : 'Don’t have an account? Sign Up',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
