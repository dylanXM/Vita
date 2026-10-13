import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

/// Debug-only evidence capture. Preserve Flutter's original error handling.
/// Capture once, with bounded traversal, rather than dumping every frame.
void installSemanticsDiagnostics() {
  if (!kDebugMode) return;
  final previous = FlutterError.onError;
  final recent = <FlutterErrorDetails>[];
  var reported = false;
  FlutterError.onError = (details) {
    final semanticsFailure =
        details.exceptionAsString().contains('semantics.parentDataDirty');
    if (!semanticsFailure) {
      recent.add(details);
      if (recent.length > 3) recent.removeAt(0);
    } else if (!reported) {
      reported = true;
      debugPrint(
          '[Vita semantics] first failure; route=${Get.currentRoute}; library=${details.library}');
      for (final earlier in recent) {
        debugPrint(
            '[Vita semantics] preceding exception: ${earlier.exceptionAsString()}');
        if (earlier.stack != null) debugPrintStack(stackTrace: earlier.stack);
      }
      if (details.stack != null) debugPrintStack(stackTrace: details.stack);
      var visited = 0;
      var dirty = 0;
      void inspect(RenderObject node) {
        if (visited++ >= 400 || dirty >= 15) return;
        if (node.debugNeedsSemanticsUpdate) {
          dirty++;
          debugPrint(
              '[Vita semantics] dirty=${node.runtimeType}; creator=${node.debugCreator}');
        }
        node.visitChildren(inspect);
      }

      for (final view in RendererBinding.instance.renderViews) {
        inspect(view);
      }
    }
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  };
}
