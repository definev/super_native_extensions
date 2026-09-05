// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:io';
import 'dart:ui';

import 'package:flutter/src/widgets/_window_macos.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';

/// Native identity for one Flutter view in the current isolate.
///
/// The window handle is only needed by the experimental same-isolate windowing
/// API on macOS. Other platforms keep using the engine context until their
/// embedders expose an equivalent stable view lookup.
class NativeViewContextDescriptor {
  const NativeViewContextDescriptor({
    required this.engineHandle,
    required this.viewId,
    required this.nativeWindowHandle,
  });

  static Future<NativeViewContextDescriptor> create(FlutterView view) async {
    final engineHandle = await EngineContext.instance.getEngineHandle();
    final nativeWindowHandle = Platform.isMacOS
        ? WindowingOwnerMacOS.getWindowHandle(view).address
        : null;
    return NativeViewContextDescriptor(
      engineHandle: engineHandle,
      viewId: view.viewId,
      nativeWindowHandle: nativeWindowHandle,
    );
  }

  final int engineHandle;
  final int viewId;
  final int? nativeWindowHandle;

  bool get hasNativeView =>
      !Platform.isMacOS || (nativeWindowHandle ?? 0) != 0;

  Map<String, Object?> serialize() => {
    'engineHandle': engineHandle,
    'viewId': viewId,
    'nativeWindowHandle': nativeWindowHandle,
  };
}
