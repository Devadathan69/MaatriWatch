import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'runtime_config.dart';

class PatientApi {
  PatientApi({http.Client? client, String? baseUrl, bool demoMode = false})
      : _client = client ?? http.Client(),
        _demoMode = demoMode,
        _baseUrl = (baseUrl ?? PatientRuntimeConfig.apiUri.toString())
            .replaceFirst(RegExp(r'/$'), '') {
    if (demoMode && kReleaseMode) {
      throw StateError('Demo credentials are blocked in release builds');
    }
  }

  final http.Client _client;
  final String _baseUrl;
  final bool _demoMode;
  Future<Map<String, dynamic>> accountAccess() =>
      _request('GET', '/account/access');
  Future<Map<String, dynamic>> guardianHome() =>
      _request('GET', '/guardian/home');
  Future<Map<String, dynamic>> linkGuardian(String code) =>
      _request('POST', '/guardian/link', body: {'code': code});
  Future<Map<String, dynamic>> patientGuardians() =>
      _request('GET', '/patient/guardians');
  Future<Map<String, dynamic>> inviteGuardian(String email) =>
      _request('POST', '/patient/guardians', body: {'email': email});
  Future<Map<String, dynamic>> removeGuardian(String id) =>
      _request('DELETE', '/patient/guardians/$id');
  Future<Map<String, dynamic>> readGuardianNotification(String id) =>
      _request('PATCH', '/guardian/notifications/$id', body: {});
  Future<Map<String, dynamic>> registerGuardianPushToken(
    String token, {
    bool remove = false,
  }) => _request(
    remove ? 'DELETE' : 'POST',
    '/guardian/push-device',
    body: {'token': token},
  );

  Future<Map<String, dynamic>> registerPushToken(String token,
          {bool remove = false}) =>
      _request(remove ? 'DELETE' : 'POST', '/patient/companion/push-device',
          body: {'token': token});
  Future<Map<String, dynamic>> consultationSlots() =>
      _request('GET', '/patient/consultations/slots');
  Future<Map<String, dynamic>> consultations() =>
      _request('GET', '/patient/consultations');
  Future<Map<String, dynamic>> bookConsultation(String slotId, String reason) =>
      _request('POST', '/patient/consultations',
          body: {'slot_id': slotId, 'reason': reason});
  Future<Map<String, dynamic>> changeConsultation(String id, String action,
          {String? slotId}) =>
      _request('PATCH', '/patient/consultations/$id',
          body: {'action': action, 'slot_id': ?slotId});
  Future<Map<String, dynamic>> joinConsultation(String id) =>
      _request('POST', '/patient/consultations/$id/join',
          body: {'video_consent': true});
  Future<Map<String, dynamic>> reportAnalyses() =>
      _request('GET', '/patient/reports/analyses');
  Future<Map<String, dynamic>> extractReportText(String value) =>
      _request('POST', '/patient/reports/extract',
          body: {'report_text': value, 'processing_consent': true});
  Future<Map<String, dynamic>> confirmReport(Map<String, dynamic> value) =>
      _request('POST', '/patient/reports/analyses', body: value);
  Future<Map<String, dynamic>> nutrition() =>
      _request('GET', '/patient/nutrition');
  Future<Map<String, dynamic>> nutritionPreferences(
          Map<String, dynamic> values) =>
      _request('PUT', '/patient/nutrition', body: values);
  Future<Map<String, dynamic>> analyseFoods(String reportId) =>
      _request('POST', '/patient/nutrition', body: {'report_id': reportId, 'processing_consent': true});
  Future<Map<String, dynamic>> extractReportFile(
      Uint8List bytes, String filename) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse('$_baseUrl/patient/reports/extract'))
      ..headers.addAll(await authorizationHeaders())
      ..fields['processing_consent'] = 'true'
      ..files.add(
          http.MultipartFile.fromBytes('document', bytes, filename: filename));
    return _responseValue(
        await http.Response.fromStream(await _client.send(request))
            .timeout(const Duration(seconds: 75)));
  }

  Future<Map<String, dynamic>> concerns() =>
      _request('GET', '/patient/concerns');
  Future<Map<String, dynamic>> draftConcern(String text, String language) =>
      _request('POST', '/patient/concerns/draft', body: {
        'text': text,
        'language': language,
        'processing_consent': true
      });
  Future<Map<String, dynamic>> saveConcern(Map<String, dynamic> values) =>
      _request('POST', '/patient/concerns', body: values);
  Future<Map<String, dynamic>> concernSummary(String month,
          {bool generate = false}) =>
      _request(
          generate ? 'POST' : 'GET', '/patient/concerns/summary?month=$month',
          body: generate ? {'processing_consent': true} : null);
  Future<Map<String, dynamic>> transcribeConcern(
      Uint8List bytes, String filename, String language) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse('$_baseUrl/patient/concerns/transcribe'))
      ..headers.addAll(await authorizationHeaders())
      ..fields.addAll({'language': language, 'processing_consent': 'true'})
      ..files.add(
          http.MultipartFile.fromBytes('audio', bytes, filename: filename));
    return _responseValue(
        await http.Response.fromStream(await _client.send(request))
            .timeout(const Duration(seconds: 75)));
  }

  Future<Map<String, String>> authorizationHeaders() async {
    if (_demoMode && !kReleaseMode) {
      return {'Accept': 'application/json', 'X-Demo-Role': 'patient'};
    }
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw const PatientApiException('Please sign in again to continue.', 401);
    }
    return {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> companion() =>
      _request('GET', '/patient/companion');
  Future<Map<String, dynamic>> companionPreferences(
          Map<String, dynamic> values) =>
      _request('PUT', '/patient/companion', body: values);
  Future<Map<String, dynamic>> companionChat(String message) =>
      _request('POST', '/patient/companion/chat', body: {'message': message});
  Future<Map<String, dynamic>> saveMemory(String value) =>
      _request('POST', '/patient/companion/memories', body: {'text': value});
  Future<Map<String, dynamic>> deleteMemory(String id) =>
      _request('DELETE', '/patient/companion/memories/$id');
  Future<Map<String, dynamic>> clearCompanionHistory() =>
      _request('DELETE', '/patient/companion/messages');
  Future<Map<String, dynamic>> createReminder(Map<String, dynamic> values) =>
      _request('POST', '/patient/companion/reminders', body: values);
  Future<Map<String, dynamic>> changeReminder(String id, String action) =>
      _request('PATCH', '/patient/companion/reminders/$id',
          body: {'action': action});
  Future<Map<String, dynamic>> checkReminders() =>
      _request('POST', '/patient/companion/reminders/check');
  Future<Map<String, dynamic>> home() => _request('GET', '/patient/home');
  Future<Map<String, dynamic>> sos(String note) =>
      _request('POST', '/patient/sos', body: {'note': note});
  Future<Map<String, dynamic>> symptoms(List<String> symptoms, String notes) =>
      _request('POST', '/patient/symptoms',
          body: {'symptoms': symptoms, 'notes': notes});
  Future<Map<String, dynamic>> consents() =>
      _request('GET', '/patient/consents');
  Future<Map<String, dynamic>> setConsent(String type, bool granted) =>
      _request('PUT', '/patient/consents/$type', body: {'granted': granted});
  Future<Map<String, dynamic>> completeTask(String id, String status) =>
      _request('PATCH', '/patient/care-plan/$id', body: {'status': status});
  Future<Map<String, dynamic>> acknowledgeLabOnboarding() =>
      _request('POST', '/patient/lab-onboarding/acknowledge');
  Future<Map<String, dynamic>> extractLabResult(
          String category, String reportText) =>
      _request('POST', '/patient/lab-results/extract',
          body: {'category': category, 'report_text': reportText});
  Future<Map<String, dynamic>> submitLabResult(Map<String, dynamic> result) =>
      _request('POST', '/patient/lab-results', body: result);
  Future<Map<String, dynamic>> submitWellbeingCheckin(
          Map<String, String> answers, bool guardianNotificationConsent) =>
      _request('POST', '/patient/wellbeing-checkins', body: {
        'answers': answers,
        'guardian_notification_consent': guardianNotificationConsent,
      });
  Future<Map<String, dynamic>> clinicalProfile() =>
      _request('GET', '/patient/clinical-profile');
  Future<Map<String, dynamic>> updateClinicalProfile(
          Map<String, dynamic> profile) =>
      _request('PUT', '/patient/clinical-profile', body: profile);
  Future<Map<String, dynamic>> messages() =>
      _request('GET', '/patient/messages');
  Future<Map<String, dynamic>> sendMessage(String body, {String? inReplyTo}) =>
      _request('POST', '/patient/messages', body: {
        'body': body,
        'in_reply_to': ?inReplyTo,
      });
  Future<Map<String, dynamic>> askAssistant(String message) =>
      _request('POST', '/patient/assistant', body: {'message': message});
  Future<Map<String, dynamic>> activity() =>
      _request('GET', '/patient/activity');
  Future<Map<String, dynamic>> recordActivity({
    required String activityType,
    required String sessionPart,
    required int minutes,
    String? note,
  }) =>
      _request('POST', '/patient/activity', body: {
        'activity_type': activityType,
        'session_part': sessionPart,
        'minutes': minutes,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
  Future<Map<String, dynamic>> reportDocuments() =>
      _request('GET', '/patient/report-documents');

  Future<Map<String, dynamic>> uploadReportDocument({
    required Uint8List bytes,
    required String filename,
    required String mediaType,
    required String documentType,
    String? confirmedText,
  }) async {
    final headers = await authorizationHeaders();
    final request = http.MultipartRequest(
        'POST', Uri.parse('$_baseUrl/patient/report-documents'))
      ..headers.addAll(headers)
      ..fields.addAll({
        'document_type': documentType,
        'media_type': mediaType,
        if (confirmedText != null && confirmedText.trim().isNotEmpty)
          'report_text': confirmedText.trim(),
      })
      ..files.add(
          http.MultipartFile.fromBytes('document', bytes, filename: filename));
    final response = await http.Response.fromStream(await request.send());
    return _responseValue(response);
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? body}) async {
    final headers = await authorizationHeaders();
    final response = await _client
        .send(http.Request(method, Uri.parse('$_baseUrl$path'))
          ..headers.addAll({
            ...headers,
            if (body != null) 'Content-Type': 'application/json'
          })
          ..body = body == null ? '' : jsonEncode(body))
        .then(http.Response.fromStream);
    return _responseValue(response);
  }

  Map<String, dynamic> _responseValue(http.Response response) {
    Object? decoded;
    try {
      decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      throw const PatientApiException(
          'The care service returned an invalid response. Please try again.',
          502);
    }
    final value = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw PatientApiException(
          value['message'] as String? ?? 'We could not complete that request.',
          response.statusCode);
    }
    return value;
  }
}

class PatientApiException implements Exception {
  const PatientApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}
