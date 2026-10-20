import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

typedef TdObject = Map<String, dynamic>;

class TdError implements Exception {
  TdError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'TdError $code: $message';
}

/// Низкоуровневый клиент TDLib поверх нативного моста (ios/Runner/AppDelegate.swift).
class TdClient {
  TdClient._();
  static final TdClient instance = TdClient._();

  static const _methods = MethodChannel('ayu/td');
  static const _events = EventChannel('ayu/td/events');

  int? _clientId;
  int _extra = 0;
  final _pending = <String, Completer<TdObject>>{};
  final _updates = StreamController<TdObject>.broadcast();
  StreamSubscription? _sub;

  Stream<TdObject> get updates => _updates.stream;

  Future<void> start() async {
    if (_clientId != null) return;
    _sub = _events.receiveBroadcastStream().listen(_onEvent);
    await execute({'@type': 'setLogVerbosityLevel', 'new_verbosity_level': 1});
    _clientId = await _methods.invokeMethod<int>('create');
    // Первый запрос "будит" клиента, после него приходит updateAuthorizationState.
    send({'@type': 'getOption', 'name': 'version'});
  }

  void _onEvent(dynamic raw) {
    final obj = jsonDecode(raw as String) as TdObject;
    final clientId = obj.remove('@client_id');
    if (clientId != null && clientId != _clientId) return;
    final extra = obj['@extra'];
    if (extra is String && _pending.containsKey(extra)) {
      final c = _pending.remove(extra)!;
      if (obj['@type'] == 'error') {
        c.completeError(TdError(obj['code'] ?? 0, obj['message'] ?? ''));
      } else {
        c.complete(obj);
      }
      return;
    }
    _updates.add(obj);
  }

  /// Отправить запрос и дождаться ответа.
  Future<TdObject> send(TdObject request) {
    final id = clientId;
    final extra = 'r${_extra++}';
    final c = Completer<TdObject>();
    _pending[extra] = c;
    _methods.invokeMethod('send', {
      'client': id,
      'json': jsonEncode({...request, '@extra': extra}),
    });
    return c.future;
  }

  /// Отправить запрос, не дожидаясь ответа и не падая на ошибке.
  void fire(TdObject request) {
    send(request).catchError((_) => <String, dynamic>{});
  }

  Future<TdObject?> execute(TdObject request) async {
    final res = await _methods.invokeMethod<String>('execute', jsonEncode(request));
    return res == null ? null : jsonDecode(res) as TdObject;
  }

  int get clientId {
    final id = _clientId;
    if (id == null) throw StateError('TdClient not started');
    return id;
  }

  /// После logOut TDLib закрывает клиента — для нового входа нужен новый client id.
  Future<void> restart() async {
    _clientId = await _methods.invokeMethod<int>('create');
    send({'@type': 'getOption', 'name': 'version'});
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
