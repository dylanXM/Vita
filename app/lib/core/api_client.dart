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

  Dio _build() {
    final d = Dio(
      BaseOptions(
        baseUrl: vitaApiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
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
      ),
    );
    return d;
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
