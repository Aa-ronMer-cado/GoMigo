import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordSettingsTile extends StatelessWidget {
  const PasswordSettingsTile({super.key, required this.auth});

  final GoTrueClient auth;

  Future<void> _open(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChangePasswordDialog(auth: auth),
    );
    if (changed == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password changed.')));
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.lock_outline),
    title: const Text('Change password'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => _open(context),
  );
}

Future<void> _changeGoMigoPassword(
  GoTrueClient auth, {
  required String currentPassword,
  required String newPassword,
}) async {
  final user = auth.currentUser;
  final email = user?.email;
  if (user == null || email == null || auth.currentSession == null) {
    throw const AuthException('Sign in again.', code: 'session_not_found');
  }

  // Verify the password even when the Auth project does not enforce current_password.
  final login = await auth.signInWithPassword(
    email: email,
    password: currentPassword,
  );
  if (login.user?.id != user.id || auth.currentUser?.id != user.id) {
    throw const AuthException('Sign in again.', code: 'session_not_found');
  }
  await auth.updateUser(
    UserAttributes(currentPassword: currentPassword, password: newPassword),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.auth});

  final GoTrueClient auth;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    String message;
    try {
      await _changeGoMigoPassword(
        widget.auth,
        currentPassword: _current.text,
        newPassword: _password.text,
      );
      if (mounted) Navigator.of(context).pop(true);
      return;
    } on AuthException catch (error) {
      message = switch (error.code) {
        'invalid_credentials' ||
        'current_password_mismatch' => 'Your current password is incorrect.',
        'weak_password' => 'Choose a stronger password.',
        'same_password' => 'Choose a password different from your current one.',
        'session_not_found' || 'session_expired' || 'reauthentication_needed' =>
          'Sign in again before changing your password.',
        'over_request_rate_limit' =>
          'Too many attempts. Try again in a moment.',
        _ => 'Could not change your password. Try again.',
      };
    } catch (_) {
      message = 'Could not change your password. Try again.';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  Widget _field(
    String label,
    TextEditingController controller,
    FormFieldValidator<String> validator, {
    bool last = false,
  }) => TextFormField(
    controller: controller,
    enabled: !_saving,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: last ? TextInputAction.done : TextInputAction.next,
    onFieldSubmitted: last ? (_) => _save() : null,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      errorMaxLines: 2,
    ),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Change password'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field('Current password', _current, (value) {
              if (value == null || value.isEmpty) {
                return 'Enter your current password.';
              }
              return null;
            }),
            const SizedBox(height: 12),
            _field('New password', _password, (value) {
              if (value == null || value.length < 8) {
                return 'Enter at least 8 characters.';
              }
              if (value == _current.text) {
                return 'Choose a different password.';
              }
              return null;
            }),
            const SizedBox(height: 12),
            _field('Confirm new password', _confirm, (value) {
              return value == _password.text ? null : 'Passwords must match.';
            }, last: true),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save password'),
        ),
      ],
    ),
  );
}
