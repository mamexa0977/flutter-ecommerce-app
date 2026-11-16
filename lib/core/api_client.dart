import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Thin typed wrapper over the FastAPI backend.
///
/// Sessions: the backend keeps a MovieBox guest session per `session_id`.
/// Browsers use a cookie; here we call `/user-info` once, store the returned
/// id and send it as `X-Session-Id` on every request.
class ApiClient {
  ApiClient(this._prefs) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      o.baseUrl = baseUrl;
      final sid = await ensureSession();
      if (sid != null) o.headers['X-Session-Id'] = sid;
      h.next(o);
    }));
  }

  static const _kBase = 'base_url';
  static const _kSession = 'session_id';

  final SharedPreferences _prefs;
  late final Dio _dio;
  Future<String?>? _bootstrapping;

  /// Android emulator reaches the host machine at 10.0.2.2.
  static String get defaultBaseUrl =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ? 'http://10.46.156.149:8000'
          : 'http://127.0.0.1:8000';

  String get baseUrl {
    final v = (_prefs.getString(_kBase) ?? defaultBaseUrl).trim();
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }

  String? get sessionId => _prefs.getString(_kSession);

  Future<void> setBaseUrl(String url) async {
    await _prefs.setString(_kBase, url.trim());
    await resetSession();
  }

  Future<void> resetSession() async {
    await _prefs.remove(_kSession);
  }

  Future<String?> ensureSession() {
    final existing = sessionId;
    if (existing != null) return Future.value(existing);
    return _bootstrapping ??=
        _bootstrap().whenComplete(() => _bootstrapping = null);
  }

  Future<String?> _bootstrap() async {
    try {
      final res = await Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 45),
      )).get('/user-info');
      final data = res.data;
      final sid = data is Map ? data['session_id']?.toString() : null;
      if (sid != null && sid.isNotEmpty) {
        await _prefs.setString(_kSession, sid);
        return sid;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> ping() async {
    try {
      final res = await Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
      )).get('/health');
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---- low level -----------------------------------------------------------

  Future<Map<String, dynamic>> _get(String path,
      {Map<String, dynamic>? query, Duration? receiveTimeout}) async {
    try {
      final res = await _dio.get(path,
          queryParameters: query,
          options: Options(receiveTimeout: receiveTimeout));
      final d = res.data;
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiException(_describe(e));
    }
  }

  String _describe(DioException e) {
    final d = e.response?.data;
    if (d is Map && d['detail'] != null) return d['detail'].toString();
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return "Can't reach the server at $baseUrl. Check Settings.";
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to answer. Try again.';
      default:
        return e.message ?? 'Request failed';
    }
  }

  // ---- endpoints -----------------------------------------------------------

  /// Any tab feed returning `{data: {list: [sections]}}`:
  /// /home, /movies, /anime, /western, /asian, /kids ...
  Future<List<Section>> feed(String endpoint, {int page = 1}) async {
    final res = await _get(endpoint, query: {'page': page});
    final data = res['data'];
    final list = data is Map ? data['list'] : null;
    if (list is! List) {
      throw ApiException(res['message']?.toString() ?? 'Feed unavailable');
    }
    return list
        .whereType<Map>()
        .map((e) => Section.fromJson(Map<String, dynamic>.from(e)))
        .where((s) => s.items.isNotEmpty)
        .toList();
  }

  Future<List<Movie>> search(String q, {int page = 1}) async {
    final res = await _get('/search', query: {'q': q, 'page': page});
    final data = res['data'];
    final items = data is Map ? data['items'] : null;
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  Future<MovieDetail> detail(String id) async {
    final res = await _get('/detail/$id');
    final data = res['data'];
    if (res['code'] != 0 || data is! Map) {
      throw ApiException(res['msg']?.toString() ?? 'Title not found');
    }
    return MovieDetail.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<Season>> episodes(String id) async =>
      Season.parse(await _get('/episodes/$id'));

  /// Resolving a stream can take a while (the backend probes several mirrors).
  Future<PlayInfo> play(String id,
      {int season = 1, int episode = 1, String? resourceId}) async {
    final res = await _get('/play/$id',
        query: {
          'season': season,
          'episode': episode,
          if (resourceId != null) 'resource_id': resourceId,
        },
        receiveTimeout: const Duration(seconds: 150));
    final data = res['data'];
    if (data is! Map) throw ApiException('No stream available');
    return PlayInfo.fromJson(Map<String, dynamic>.from(data));
  }
}
