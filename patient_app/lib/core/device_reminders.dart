import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'patient_api.dart';

class DeviceReminders {
  static StreamSubscription<String>? _refresh;
  static Future<void> enable(PatientApi api) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError(
          'Phone reminders are available in the configured Android app. Web reminders remain in the app inbox.');
    }
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError(
          'Notifications were not allowed. Your in-app reminder inbox remains available.');
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      throw StateError(
          'This device could not register for reminders. Check Firebase configuration.');
    }
    await api.registerPushToken(token);
    await _refresh?.cancel();
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      try {
        await api.registerPushToken(token);
      } catch (_) {
        /* Retry by re-enabling on this device; do not log device tokens. */
      }
    });
  }

  static Future<void> disable(PatientApi api) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _refresh?.cancel();
    _refresh = null;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await api.registerPushToken(token, remove: true);
    } catch (_) {/* Signing out must remain possible when offline. */}
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
