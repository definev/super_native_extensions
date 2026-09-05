import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';

import '../drop.dart';
import '../image_data.dart';
import '../mutex.dart';
import '../reader.dart';
import '../util.dart';
import 'context.dart';
import 'image_data.dart';
import 'reader_manager.dart';
import 'view_context.dart';

final _channel = NativeMethodChannel(
  'DropManager',
  context: superNativeExtensionsContext,
);

class Session {
  DataReader? reader;
  final mutex = Mutex();
}

extension ItemPreviewExt on ItemPreview {
  Future<dynamic> serialize() async => {
    'destinationRect': destinationRect.serialize(),
    'destinationImage': destinationImage != null
        ? (await ImageData.fromImage(destinationImage!)).serialize()
        : null,
    'fadeOutDelay': fadeOutDelay?.inSecondsDouble,
    'fadeOutDuration': fadeOutDuration?.inSecondsDouble,
  };
}

extension BaseDropEventExt on BaseDropEvent {
  static BaseDropEvent deserialize(dynamic event) {
    final map = event as Map;
    return BaseDropEvent(
      sessionId: map['sessionId'],
      viewId: map['viewId'],
    );
  }
}

extension DropItemExt on DropItem {
  static DropItem deserialize(dynamic item, DataReaderItem? readerItem) {
    final map = item as Map;
    return DropItem(
      itemId: map['itemId'],
      formats: (map['formats'] as List).cast<String>(),
      localData: map['localData'],
      readerItem: readerItem,
    );
  }
}

typedef ReaderProvider = DataReader? Function(int viewId, int sessionId);

class DropEventImpl extends DropEvent {
  DropEventImpl({
    required super.sessionId,
    required super.viewId,
    required super.locationInView,
    required super.allowedOperations,
    required super.items,
    super.acceptedOperation,
    this.reader,
  });

  // readerProvider is to ensure that reader is only deserialized once and
  // same instance is used subsequently.
  static Future<DropEventImpl> deserialize(
    dynamic event,
    ReaderProvider readerProvider,
  ) async {
    final map = event as Map;
    final acceptedOperation = map['acceptedOperation'];
    final viewId = map['viewId'] as int;
    final sessionId = map['sessionId'] as int;
    DataReader? getReader() {
      final reader = map['reader'];
      return reader != null
          ? DataReader(handle: $DataReaderHandle.deserialize(reader))
          : null;
    }

    final reader = readerProvider(viewId, sessionId) ?? getReader();
    final items = await reader?.getItems();

    DropItem deserializeItem(int index, dynamic item) {
      final readerItem = (items != null && index < items.length)
          ? items[index]
          : null;
      return DropItemExt.deserialize(item, readerItem);
    }

    return DropEventImpl(
      sessionId: sessionId,
      viewId: viewId,
      locationInView: OffsetExt.deserialize(map['locationInView']),
      items: (map['items'] as Iterable)
          .mapIndexed(deserializeItem)
          .toList(growable: false),
      allowedOperations: (map['allowedOperations'] as Iterable)
          .map((e) => DropOperation.values.byName(e))
          .toList(growable: false),
      acceptedOperation: acceptedOperation != null
          ? DropOperation.values.byName(acceptedOperation)
          : null,
      reader: reader,
    );
  }

  final DataReader? reader;
}

class DropContextImpl extends DropContext {
  DropContextImpl();

  static final _sessions = <(int, int), Session>{};
  final _registeredViews = <int, Future<void>>{};

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _channel.setMethodCallHandler(_handleMethodCall);
    final implicitView =
        WidgetsBinding.instance.platformDispatcher.implicitView;
    if (implicitView != null) {
      await registerView(implicitView);
    }
  }

  @override
  Future<void> registerView(ui.FlutterView view) async {
    final existing = _registeredViews[view.viewId];
    if (existing != null) {
      return existing;
    }
    final descriptor = await NativeViewContextDescriptor.create(view);
    if (!descriptor.hasNativeView) {
      return;
    }
    final registration = _channel.invokeMethod<void>(
      'newContext',
      descriptor.serialize(),
    );
    _registeredViews[view.viewId] = registration;
    try {
      await registration;
    } catch (_) {
      _registeredViews.remove(view.viewId);
      rethrow;
    }
  }

  Session _sessionForEvent(dynamic event) {
    final map = event as Map;
    final viewId = map['viewId'] as int;
    final sessionId = map['sessionId'] as int;
    return _sessionForId(viewId, sessionId);
  }

  Session _sessionForId(int viewId, int sessionId) {
    return _sessions.putIfAbsent((viewId, sessionId), () => Session());
  }

  DataReader? _getReaderForSession(int viewId, int sessionId) {
    return _sessionForId(viewId, sessionId).reader;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onDropUpdate') {
      return handleError(() async {
        final session = _sessionForEvent(call.arguments);
        return session.mutex.protect(() async {
          final event = await DropEventImpl.deserialize(
            call.arguments,
            _getReaderForSession,
          );
          session.reader = event.reader;
          final operation = await delegate?.onDropUpdate(event);
          return (operation ?? DropOperation.none).name;
        });
      }, () => DropOperation.none.name);
    } else if (call.method == 'onPerformDrop') {
      return handleError(() async {
        final session = _sessionForEvent(call.arguments);
        return session.mutex.protect(() async {
          final event = await DropEventImpl.deserialize(
            call.arguments,
            _getReaderForSession,
          );
          session.reader = event.reader;
          return await delegate?.onPerformDrop(event);
        });
      }, () => null);
    } else if (call.method == 'onDropLeave') {
      return handleError(() async {
        final session = _sessionForEvent(call.arguments);
        return session.mutex.protect(() async {
          final event = BaseDropEventExt.deserialize(call.arguments);
          return await delegate?.onDropLeave(event);
        });
      }, () => null);
    } else if (call.method == 'onDropEnded') {
      return handleError(() async {
        final event = BaseDropEventExt.deserialize(call.arguments);
        final session = _sessions.remove((event.viewId, event.sessionId));
        if (session != null) {
          return session.mutex.protect(() async {
            session.reader?.dispose();
            return await delegate?.onDropEnded(event);
          });
        } else {
          return null;
        }
      }, () => null);
    } else if (call.method == 'getPreviewForItem') {
      return handleError(() async {
        final request = ItemPreviewRequest.deserialize(call.arguments);
        final session = _sessions[(request.viewId, request.sessionId)];
        if (session != null) {
          return session.mutex.protect(() async {
            final preview = await delegate?.onGetItemPreview(request);
            return {
              'preview': await preview?.serialize(),
            };
          });
        } else {
          return {'preview': null};
        }
      }, () => {'preview': null});
    } else {
      return null;
    }
  }

  @override
  Future<void> registerDropFormats(List<String> formats) {
    return _channel.invokeMethod("registerDropFormats", {'formats': formats});
  }
}
