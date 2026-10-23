import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'core/runtime_config.dart';
import 'features/auth/auth_gate.dart';
import 'features/demo/demo_patient_app.dart';
import 'firebase_options.dart';
import 'core/device_reminders.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Presentation mode is an isolated debug-only app. It never creates a
  // Firebase session and is rejected by PatientRuntimeConfig in release.
  if (PatientRuntimeConfig.demoMode && !kReleaseMode) {
    runApp(const MaatriWatchPatientApp(demoMode: true));
    return;
  }
  final configurationError = PatientRuntimeConfig.validationError() ??
      PatientFirebaseOptions.validationError();
  var firebaseReady =
      configurationError == null && PatientFirebaseOptions.isConfigured;
  String? initializationError = configurationError;
  if (firebaseReady) {
    try {
      await Firebase.initializeApp(
          options: PatientFirebaseOptions.currentPlatform);
      DeviceReminders.listenForeground();
    } catch (_) {
      firebaseReady = false;
      initializationError =
          'MaatriWatch could not start securely. Check the hospital-issued app configuration and connection.';
    }
  } else {
    initializationError ??=
        'This app has not been configured for a patient account.';
  }
  runApp(MaatriWatchPatientApp(
      firebaseReady: firebaseReady, initializationError: initializationError));
}

/// Android-first entry point for the MaatriWatch companion app.
class MaatriWatchPatientApp extends StatelessWidget {
  const MaatriWatchPatientApp({
    super.key,
    this.firebaseReady = false,
    this.initializationError,
    this.home,
    this.demoMode = false,
  });

  final bool firebaseReady;
  final String? initializationError;
  final Widget? home;
  final bool demoMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MaatriWatch',
        debugShowCheckedModeBanner: false,
        theme: maatriTheme(),
        home: home ??
            (demoMode
                ? const DemoPatientSignIn()
                : (firebaseReady
                    ? PatientAuthGate(
                        auth: FirebaseAuth.instance,
                        allowUnverifiedEmail:
                            PatientRuntimeConfig.allowUnverifiedPatientDemo,
                      )
                    : _ConfigurationScreen(
                        message: initializationError,
                        allowPresentationDemo: !kReleaseMode,
                      ))),
      );
}

class _ConfigurationScreen extends StatelessWidget {
  const _ConfigurationScreen(
      {this.message, this.allowPresentationDemo = false});
  final String? message;
  final bool allowPresentationDemo;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text('MaatriWatch setup needed',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    message ?? 'This app is not ready to connect securely.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Please contact your hospital care team. Do not use an unconfigured app for care decisions.',
                    textAlign: TextAlign.center,
                  ),
                  if (allowPresentationDemo) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text(
                      'For the presentation only, you can open the clearly labelled simulated demo.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => const DemoPatientSignIn()),
                      ),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Run presentation demo'),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}
