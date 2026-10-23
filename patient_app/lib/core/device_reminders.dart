import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'patient_api.dart';

class DeviceReminders {
  static StreamSubscription<String>? _refresh;
  static StreamSubscription<RemoteMessage>? _messages;
  static void listenForeground() {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _messages != null) {
      return;
    }
    _messages = FirebaseMessaging.onMessage.listen((message) async {
      try {
        await const MethodChannel(
          'maatriwatch/notifications',
        ).invokeMethod<void>('show', {
          'guardian': message.data['screen'] == 'guardian',
          'id': message.data['notification_id'] ?? '',
        });
      } catch (_) {
        /* The in-app inbox remains available. */
      }
    });
  }

  static Future<void> resumeGuardian(PatientApi api) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      await enable(api, guardian: true);
    }
  }

  static Future<void> enable(PatientApi api, {bool guardian = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError(
        'Phone reminders are available in the configured Android app. Web reminders remain in the app inbox.',
      );
    }
    final permission = await FirebaseMessaging.instance.requestPermission();
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError(
        'Notifications were not allowed. Your in-app reminder inbox remains available.',
      );
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      throw StateError(
        'This device could not register for reminders. Check Firebase configuration.',
      );
    }
    if (guardian) {
      await api.registerGuardianPushToken(token);
    } else {
      await api.registerPushToken(token);
    }
    listenForeground();
    await _refresh?.cancel();
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      try {
        if (guardian) {
          await api.registerGuardianPushToken(token);
        } else {
          await api.registerPushToken(token);
        }
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
      if (token != null) {
        try {
          await api.registerPushToken(token, remove: true);
        } catch (_) {}
        try {
          await api.registerGuardianPushToken(token, remove: true);
        } catch (_) {}
      }
    } catch (_) {
      /* Signing out must remain possible when offline. */
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
