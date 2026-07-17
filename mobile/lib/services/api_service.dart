import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/parse.dart';
import '../models/app_status.dart';
import '../models/known_person.dart';
import '../models/visitor_event.dart';

/// A friendly, already-formatted error the UI can show verbatim. We never let a
/// raw dio stack trace reach the user.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// Thin REST client over the AccessAI backend. Immutable around one base URL —
/// when the URL changes, a fresh ApiService is created (see providers). Every
/// call maps transport/backend failures to an ApiException with a readable
/// message so callers can `try/catch` and show a snackbar instead of crashing.
class ApiService {
  ApiService(this.baseUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
          // Accept any status; we branch on it ourselves for clean messages.
          validateStatus: (_) => true,
        ));

  final String baseUrl;
  final Dio _dio;

  // --- URL helpers (for MJPEG / <img>) -----------------------------------
  String get videoUrl => '$baseUrl/video';
  String knownPhotoUrl(String name) =>
      '$baseUrl/known_photo/${Uri.encodeComponent(name)}';
  String snapshotUrl(String eventId) =>
      '$baseUrl/snapshot/${Uri.encodeComponent(eventId)}';
  String speakAudioUrl(String text) =>
      '$baseUrl/speak_audio?text=${Uri.encodeQueryComponent(text)}';

  Uri get eventsWsUri {
    final u = Uri.parse(baseUrl);
    final scheme = u.scheme == 'https' ? 'wss' : 'ws';
    return u.replace(scheme: scheme, path: '/events');
  }

  // --- Core requests ------------------------------------------------------
  Never _fail(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw ApiException(
            'Can’t reach the server at $baseUrl. Check it’s running and on the '
            'same Wi‑Fi, then test the connection in Settings.');
      }
      throw ApiException('Network error: ${e.message ?? e.type.name}');
    }
    throw ApiException('Unexpected error: $e');
  }

  Map<String, dynamic> _okMap(Response r) {
    if (r.statusCode == null || r.statusCode! >= 400) {
      final detail = r.data is Map ? asStr((r.data as Map)['detail']) : '';
      throw ApiException(
          detail.isNotEmpty ? detail : 'Server returned ${r.statusCode}',
          statusCode: r.statusCode);
    }
    return asMap(r.data);
  }

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, dynamic>? query}) async {
    try {
      return _okMap(await _dio.get(path, queryParameters: query));
    } catch (e) {
      _fail(e);
    }
  }

  Future<Map<String, dynamic>> _post(String path, {Object? body}) async {
    try {
      return _okMap(await _dio.post(path, data: body));
    } catch (e) {
      _fail(e);
    }
  }

  // --- Health / connection -----------------------------------------------
  Future<AppStatus> status() async => AppStatus.fromJson(await _get('/status'));

  /// A quick reachability probe used by the Settings "Test connection" button.
  Future<AppStatus> testConnection() => status();

  // --- Doorbell + door actions -------------------------------------------
  /// Ring: visual-only, fast, records NOTHING. Returns the new event.
  Future<VisitorEvent> trigger() async =>
      VisitorEvent.fromJson(await _post('/trigger'));

  /// The ONLY recorder. Captures the visitor for a few seconds, transcribes +
  /// translates. Returns {transcript, translated, language, event_id}.
  Future<Map<String, dynamic>> hearVisitor() => _post('/hear_visitor');

  /// Speak a typed reply at the door.
  Future<Map<String, dynamic>> reply(String text) =>
      _post('/reply', body: {'text': text});

  /// Text/voice command; returns {intent, answer, text}.
  Future<Map<String, dynamic>> command(String text) =>
      _post('/command', body: {'text': text});

  /// Free-form visual question about the current scene ("what colour is their
  /// dress", "what is he doing now"). Returns {question, answer}. `speak` asks
  /// the backend to also voice the answer on the doorbell's speaker.
  /// Throws ApiException (503) when the VLM isn't available so the UI can say so.
  Future<String> ask(String question, {bool speak = false}) async {
    final m = await _post('/ask', body: {'question': question, 'speak': speak});
    return asStr(m['answer']);
  }

  // --- Translation language ----------------------------------------------
  /// Current translation backend + target language for the picker/pill.
  /// Returns {enabled, available, backend, user_language, user_language_name}.
  Future<Map<String, dynamic>> translateStatus() => _get('/translate_status');

  /// Change the user's target language live (and persist it server-side).
  /// Returns the sanitized {user_language, user_language_name}.
  Future<Map<String, dynamic>> setUserLanguage(String code) =>
      _post('/user_language', body: {'lang': code});

  // --- History ------------------------------------------------------------
  Future<List<VisitorEvent>> history({int limit = 50}) async {
    try {
      final r = await _dio.get('/history', queryParameters: {'limit': limit});
      if (r.statusCode != 200) {
        throw ApiException('Could not load history (${r.statusCode}).');
      }
      final data = r.data;
      final list = data is List ? data : const [];
      return list
          .whereType<Map>()
          .map((e) => VisitorEvent.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _fail(e);
    }
  }

  Future<VisitorEvent> event(String id) async => VisitorEvent.fromJson(
      await _get('/event/${Uri.encodeComponent(id)}'));

  Future<void> deleteEvent(String id) =>
      _post('/event/${Uri.encodeComponent(id)}/delete');

  Future<int> clearHistory() async {
    final m = await _post('/history/clear');
    return asInt(m['cleared']);
  }

  // --- Known people -------------------------------------------------------
  Future<List<KnownPerson>> known() async {
    final m = await _get('/known');
    return asMapList(m['people']).map(KnownPerson.fromJson).toList();
  }

  Future<void> deleteKnown(String name) =>
      _post('/known/delete', body: {'name': name});

  /// Enrol a person from one or more photo files (multipart). `photos` is a list
  /// of (filename, bytes).
  Future<Map<String, dynamic>> enrollUpload(
      String name, List<({String filename, Uint8List bytes})> photos) async {
    try {
      final form = FormData();
      form.fields.add(MapEntry('name', name));
      for (final p in photos) {
        // The backend decodes each upload with cv2.imdecode on the raw bytes,
        // so the MIME type is irrelevant — filename alone is enough.
        form.files.add(MapEntry(
          'files',
          MultipartFile.fromBytes(p.bytes, filename: p.filename),
        ));
      }
      final r = await _dio.post('/enroll_upload', data: form);
      return _okMap(r);
    } catch (e) {
      if (e is ApiException) rethrow;
      _fail(e);
    }
  }

  // --- Mode ---------------------------------------------------------------
  Future<String> getMode() async => asStr((await _get('/mode'))['mode'], 'both');
  Future<String> setMode(String mode) async =>
      asStr((await _post('/mode', body: {'mode': mode}))['mode'], mode);

  // --- Voices -------------------------------------------------------------
  Future<({List<VoiceOption> voices, String current})> voices() async {
    final m = await _get('/voices');
    final list = asMapList(m['voices']).map(VoiceOption.fromJson).toList();
    return (voices: list, current: asStr(m['current']));
  }

  Future<Map<String, dynamic>> setVoice(String id) =>
      _post('/voice', body: {'id': id});

  // --- Blind-mode speech: fetch synthesized WAV bytes --------------------
  /// Returns WAV bytes for the phone to play, or throws ApiException (e.g. 503)
  /// so the caller falls back to on-device TTS.
  Future<Uint8List> speakAudio(String text) async {
    try {
      final r = await _dio.get<List<int>>(
        '/speak_audio',
        queryParameters: {'text': text},
        options: Options(responseType: ResponseType.bytes),
      );
      if (r.statusCode != 200 || r.data == null || r.data!.isEmpty) {
        throw ApiException('No server audio (${r.statusCode}).',
            statusCode: r.statusCode);
      }
      return Uint8List.fromList(r.data!);
    } catch (e) {
      if (e is ApiException) rethrow;
      _fail(e);
    }
  }

  void close() => _dio.close(force: true);
}
