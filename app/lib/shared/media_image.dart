import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/token_storage.dart';

class VitaMediaImage extends StatelessWidget {
  const VitaMediaImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.placeholderBuilder,
  });

  final String url;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final WidgetBuilder? placeholderBuilder;

  Widget _frame(
          BuildContext context, Widget child, int? frame, bool synchronous) =>
      synchronous || frame != null || placeholderBuilder == null
          ? child
          : placeholderBuilder!(context);

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('asset://')) {
      return Image.asset(
        url.substring('asset://'.length),
        fit: fit,
        errorBuilder: errorBuilder,
        frameBuilder: _frame,
      );
    }
    if (url.startsWith('data:image/') && url.contains(',')) {
      return Image.memory(
        base64Decode(url.substring(url.indexOf(',') + 1)),
        fit: fit,
        errorBuilder: errorBuilder,
        frameBuilder: _frame,
      );
    }
    final resolved = url.startsWith('http')
        ? url
        : '${vitaApiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}${url.startsWith('/') ? url : '/$url'}';
    final needsAuthentication =
        Uri.tryParse(resolved)?.path.startsWith('/v1/media/') == true;
    if (!needsAuthentication) {
      return Image.network(resolved,
          fit: fit, errorBuilder: errorBuilder, frameBuilder: _frame);
    }
    return FutureBuilder<String?>(
      future: TokenStorage.read(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return placeholderBuilder?.call(context) ?? const SizedBox.expand();
        }
        return Image.network(
          resolved,
          fit: fit,
          headers: snapshot.data?.isNotEmpty == true
              ? {'Authorization': 'Bearer ${snapshot.data}'}
              : const {},
          errorBuilder: errorBuilder,
          frameBuilder: _frame,
        );
      },
    );
  }
}
