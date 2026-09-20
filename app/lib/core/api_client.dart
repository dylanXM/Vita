import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide FormData, MultipartFile;

import 'constants.dart';
import 'supported_locales.dart';
import 'token_storage.dart';

/// Thin wrapper around Dio: injects the bearer token and turns transport
/// errors into a user-friendly [ApiException].
class ApiException implements Exception {
  final String message;
  final String? code;
  final String? action;
  final int? statusCode;
  ApiException(this.message, {this.code, this.action, this.statusCode});

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  late final Dio dio = _build();
  Future<bool>? _refreshing;

  Dio _build() {
    final d = Dio(
      BaseOptions(
        baseUrl: vitaApiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 90),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStorage.read();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          options.headers['X-Vita-Platform'] = switch (defaultTargetPlatform) {
            TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
            TargetPlatform.android => 'android',
            _ => 'web',
          };
          options.headers['X-Vita-App-Version'] = vitaAppVersion;
          options.headers['Accept-Language'] =
              vitaLocaleTag(Get.locale ?? vitaSupportedLocales[1]);
          handler.next(options);
        },
        onError: (error, handler) async {
          final options = error.requestOptions;
          final canRefresh = error.response?.statusCode == 401 &&
              options.extra['vitaRetried'] != true &&
              !options.path.startsWith('/v1/auth/');
          if (!canRefresh || !await _refreshSession()) {
            handler.next(error);
            return;
          }
          try {
            options.extra['vitaRetried'] = true;
            options.headers['Authorization'] =
                'Bearer ${await TokenStorage.read()}';
            handler.resolve(await d.fetch(options));
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
    return d;
  }

  Future<bool> _refreshSession() {
    final active = _refreshing;
    if (active != null) return active;
    final future = _performRefresh();
    _refreshing = future;
    future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  Future<bool> _performRefresh() async {
    try {
      final refreshToken = await TokenStorage.readRefresh();
      if (refreshToken == null || refreshToken.isEmpty) {
        await TokenStorage.clear();
        return false;
      }
      final refreshClient = Dio(
        BaseOptions(
          baseUrl: vitaApiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: const {'Content-Type': 'application/json'},
        ),
      );
      final response = await refreshClient.post(
        '/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      final token = data['token'] as String? ?? '';
      final rotatedRefresh = data['refresh_token'] as String? ?? '';
      if (token.isEmpty || rotatedRefresh.isEmpty) {
        await TokenStorage.clear();
        return false;
      }
      await TokenStorage.writeSession(token, rotatedRefresh);
      return true;
    } catch (_) {
      await TokenStorage.clear();
      return false;
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    try {
      final r = await dio.get(path, queryParameters: query);
      return r.data;
    } on DioException catch (e) {
      throw _exception(e);
    }
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? data}) async {
    try {
      final r = await dio.post(path, data: data);
      return r.data;
    } on DioException catch (e) {
      throw _exception(e);
    }
  }

  Future<dynamic> upload(String path, String filePath,
      {required String kind}) async {
    try {
      final form = FormData.fromMap({
        'kind': kind,
        'file': await MultipartFile.fromFile(filePath,
            contentType: kind == 'audio' ? DioMediaType('audio', 'mp4') : null),
      });
      final response = await dio.post(path,
          data: form, options: Options(contentType: 'multipart/form-data'));
      return response.data;
    } on DioException catch (e) {
      throw _exception(e);
    }
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? data}) async {
    try {
      final r = await dio.put(path, data: data);
      return r.data;
    } on DioException catch (e) {
      throw _exception(e);
    }
  }

  Future<dynamic> delete(String path, {Map<String, dynamic>? data}) async {
    try {
      final r = await dio.delete(path, data: data);
      return r.data;
    } on DioException catch (e) {
      throw _exception(e);
    }
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Cannot reach server';
    }
    return 'Request failed (${e.response?.statusCode ?? 'network'})';
  }

  ApiException _exception(DioException e) {
    final data = e.response?.data;
    return ApiException(
      _message(e),
      code: data is Map ? data['code'] as String? : null,
      action: data is Map ? data['action'] as String? : null,
      statusCode: e.response?.statusCode,
    );
  }
}
