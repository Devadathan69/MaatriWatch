import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'runtime_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl, this.demoRole})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? DashboardRuntimeConfig.apiUri.toString())
            .replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;
  final String? demoRole;
  Future<Map<String, dynamic>> patientNutrition(
          String hospitalId, String patientId) =>
      _request('GET', '/hospitals/$hospitalId/patients/$patientId/nutrition');
  Future<Map<String, dynamic>> reviewNutrition(String hospitalId,
          String patientId, String planId, String action, String note) =>
      _request('PATCH',
          '/hospitals/$hospitalId/patients/$patientId/nutrition/$planId',
          body: {'action': action, 'note': note});
  Future<Map<String, dynamic>> concernSummary(
          String hospitalId, String patientId, String month) =>
      _request('GET',
          '/hospitals/$hospitalId/patients/$patientId/concerns/summary?month=$month');

  Future<Map<String, dynamic>> me() => _request('GET', '/me');

  Future<List<PatientSummary>> patients(String hospitalId,
      {String sort = 'risk'}) async {
    final json =
        await _request('GET', '/hospitals/$hospitalId/patients?sort=$sort');
    return (json['items'] as List<dynamic>? ?? const [])
        .map((item) => PatientSummary.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<PatientDetail> patient(String hospitalId, String patientId) async =>
      PatientDetail.fromJson(
          await _request('GET', '/hospitals/$hospitalId/patients/$patientId'));

  Future<List<VitalReading>> vitals(
    String hospitalId,
    String patientId, {
    String resolution = 'raw',
  }) async {
    final end = DateTime.now().toUtc();
    final start = end.subtract(const Duration(hours: 24));
    final json = await _request(
      'GET',
      '/hospitals/$hospitalId/patients/$patientId/vitals?from=${Uri.encodeQueryComponent(start.toIso8601String())}'
          '&to=${Uri.encodeQueryComponent(end.toIso8601String())}&resolution=$resolution',
    );
    return (json['items'] as List<dynamic>? ?? const [])
        .map((item) => VitalReading.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<List<AlertItem>> alerts(String hospitalId, {String? patientId}) async {
    final suffix = patientId == null
        ? ''
        : '&patient_id=${Uri.encodeQueryComponent(patientId)}';
    final json = await _request(
        'GET', '/hospitals/$hospitalId/alerts?status=active$suffix');
    return (json['items'] as List<dynamic>? ?? const [])
        .map((item) => AlertItem.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<AlertItem> updateAlert(
    String hospitalId,
    String alertId, {
    required String action,
    String? note,
  }) async {
    final body = <String, dynamic>{
      'action': action,
      if (note != null) 'note': note
    };
    final json = await _request(
      'PATCH',
      '/hospitals/$hospitalId/alerts/$alertId',
      body: body,
    );
    return AlertItem.fromJson(asMap(json['alert']));
  }

  Future<List<ClinicalNote>> notes(String hospitalId, String patientId) async {
    final json = await _request(
        'GET', '/hospitals/$hospitalId/patients/$patientId/clinical-notes');
    return (json['items'] as List<dynamic>? ?? const [])
        .map((item) => ClinicalNote.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<ClinicalNote> createNote(
      String hospitalId, String patientId, String note) async {
    final json = await _request(
      'POST',
      '/hospitals/$hospitalId/patients/$patientId/clinical-notes',
      body: <String, dynamic>{'note': note},
    );
    return ClinicalNote.fromJson(asMap(json['note']));
  }

  Future<List<CareMessage>> careMessages(
      String hospitalId, String patientId) async {
    if (demoRole != null) return const [];
    final json = await _request(
        'GET', '/hospitals/$hospitalId/patients/$patientId/care-messages');
    return (json['items'] as List<dynamic>? ?? const [])
        .map((item) => CareMessage.fromJson(asMap(item)))
        .toList(growable: false);
  }

  Future<CareMessage> sendCareMessage(
    String hospitalId,
    String patientId,
    String body, {
    String? inReplyTo,
  }) async {
    if (demoRole != null) {
      throw const ApiException(
          'Care messaging is unavailable in the isolated demo.');
    }
    final json = await _request(
      'POST',
      '/hospitals/$hospitalId/patients/$patientId/care-messages',
      body: <String, dynamic>{
        'body': body,
        if (inReplyTo != null) 'in_reply_to': inReplyTo,
      },
    );
    return CareMessage.fromJson(asMap(json['message']));
  }

  Future<Map<String, dynamic>> createGuidance(
    String hospitalId,
    String patientId, {
    required String category,
    required String title,
    required String body,
  }) =>
      _request('POST', '/hospitals/$hospitalId/patients/$patientId/guidance',
          body: <String, dynamic>{
            'category': category,
            'title': title,
            'body': body,
          });

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = demoRole == null
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : null;
    if (demoRole == null && (token == null || token.isEmpty)) {
      throw const ApiException('Your session has ended. Please sign in again.');
    }
    final response = await _client
        .send(
          http.Request(method, Uri.parse('$_baseUrl$path'))
            ..headers.addAll(<String, String>{
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
              if (demoRole != null) 'X-Demo-Role': demoRole!,
              if (body != null) 'Content-Type': 'application/json',
            })
            ..body = body == null ? '' : jsonEncode(body),
        )
        .then(http.Response.fromStream);
    final decoded =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    final map = asMap(decoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          map['message'] as String? ?? 'Unable to complete that request.',
          statusCode: response.statusCode);
    }
    return map;
  }
}
