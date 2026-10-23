import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/patient_realtime.dart';
import '../../core/patient_api.dart';
import '../../core/device_reminders.dart';
import '../patient/patient_home.dart';

class PatientAuthGate extends StatelessWidget {
  const PatientAuthGate({
    super.key,
    required this.auth,
    this.allowUnverifiedEmail = false,
  });

  final FirebaseAuth auth;
  final bool allowUnverifiedEmail;
  Future<void> _signOut() async {
    await DeviceReminders.disable(PatientApi());
    await auth.signOut();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: auth.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _ProgressScreen();
          }
          final user = snapshot.data;
          if (user == null) {
            return PatientSignInPage(auth: auth);
          }
          if (!user.emailVerified && !allowUnverifiedEmail) {
            return _EmailVerificationPage(auth: auth, user: user);
          }
          return PatientHome(
            onSignOut: _signOut,
            onAccessDenied: _signOut,
            liveVitals: FirebasePatientLiveVitalsSource(),
          );
        },
      );
}

class PatientSignInPage extends StatefulWidget {
  const PatientSignInPage({super.key, required this.auth});

  final FirebaseAuth auth;

  @override
  State<PatientSignInPage> createState() => _PatientSignInPageState();
}

class _PatientSignInPageState extends State<PatientSignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.auth.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error =
          'Enter the email address linked to your MaatriWatch account first.');
      return;
    }
    try {
      await widget.auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('If this account exists, a reset link has been sent.')),
        );
      }
    } on FirebaseAuthException catch (_) {
      if (mounted) {
        setState(() => _error =
            'We could not start password reset. Please try again or contact your care team.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.favorite_rounded,
                          size: 48, color: Color(0xff245568)),
                      const SizedBox(height: 20),
                      Text('Welcome to MaatriWatch',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      const Text(
                          'Sign in with the account provided by your care team.'),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Email address'),
                        validator: (value) =>
                            value != null && value.trim().contains('@')
                                ? null
                                : 'Enter a valid email address.',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (value) => value != null && value.isNotEmpty
                            ? null
                            : 'Enter your password.',
                        onFieldSubmitted: (_) => _signIn(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _Message(text: _error!),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _submitting ? null : _signIn,
                        child: Text(_submitting ? 'Signing in…' : 'Sign in'),
                      ),
                      TextButton(
                          onPressed: _submitting ? null : _resetPassword,
                          child: const Text('Forgot password?')),
                      const SizedBox(height: 12),
                      const Text(
                        'Do not share your password. If you have not received an invitation, contact your hospital care team.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _EmailVerificationPage extends StatefulWidget {
  const _EmailVerificationPage({required this.auth, required this.user});

  final FirebaseAuth auth;
  final User user;

  @override
  State<_EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<_EmailVerificationPage> {
  bool _sending = false;
  String? _message;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await widget.user.sendEmailVerification();
      if (mounted) {
        setState(() => _message =
            'Verification email sent. Open it, then return here and refresh.');
      }
    } on FirebaseAuthException catch (_) {
      if (mounted) {
        setState(() => _message =
            'We could not send a verification email. Please try again later.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _refresh() async {
    await widget.user.reload();
    await widget.auth.currentUser?.getIdToken(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.mark_email_unread_outlined, size: 48),
                      const SizedBox(height: 18),
                      Text('Verify your email',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                        'Before continuing, verify ${widget.user.email ?? 'the email address linked to this account'}.',
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        _Message(text: _message!)
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: _sending ? null : _send,
                          child: Text(_sending
                              ? 'Sending…'
                              : 'Send verification email')),
                      OutlinedButton(
                          onPressed: _refresh,
                          child: const Text('I have verified my email')),
                      TextButton(
                          onPressed: widget.auth.signOut,
                          child: const Text('Use another account')),
                    ]),
              ),
            ),
          ),
        ),
      );
}

class _ProgressScreen extends StatelessWidget {
  const _ProgressScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12)),
        child: Text(text),
      );
}

String _friendlyAuthError(FirebaseAuthException error) => switch (error.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' =>
        'Check your email address and password.',
      'user-disabled' =>
        'This account is currently unavailable. Contact your care team.',
      'too-many-requests' =>
        'Too many attempts. Please wait a moment, reset your password, or contact your care team.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      _ =>
        'We could not sign you in. Please try again or contact your care team.',
    };
