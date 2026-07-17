import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../core/parse.dart';

enum WsState { connecting, connected, disconnected }

/// Persistent WebSocket to /events with automatic reconnect + backoff. Decodes
/// each frame to a Map and re-broadcasts on [events]. Unknown message types are
/// passed through untouched — consumers ignore what they don't handle, and a
/// bad frame is dropped rather than crashing the socket. "ping" keep-alives are
/// swallowed here.
class EventsService {
  EventsService(this.wsUri);

  final Uri wsUri;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<WsState>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _closed = false;
  WsState _state = WsState.disconnected;

  Stream<Map<String, dynamic>> get events => _controller.stream;
  Stream<WsState> get state => _stateController.stream;
  WsState get currentState => _state;

  void connect() {
    if (_closed) return;
    _setState(WsState.connecting);
    try {
      final ch = WebSocketChannel.connect(wsUri);
      _channel = ch;
      _sub = ch.stream.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      // web_socket_channel has no explicit "open" event; treat first successful
      // subscription as connected. Real failures surface via onError/onDone.
      _attempt = 0;
      _setState(WsState.connected);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    if (_state != WsState.connected) _setState(WsState.connected);
    _attempt = 0;
    try {
      final decoded = jsonDecode(raw is String ? raw : raw.toString());
      if (decoded is Map) {
        final map = decoded.cast<String, dynamic>();
        if (asStr(map['type']) == 'ping') return; // keep-alive
        _controller.add(map);
      }
    } catch (_) {
      // Ignore malformed frames — never break the stream.
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _setState(WsState.disconnected);
    _sub?.cancel();
    _sub = null;
    _channel = null;
    _reconnectTimer?.cancel();
    // Exponential backoff capped at 15s, so a laptop that's briefly asleep or a
    // Wi‑Fi blip recovers on its own without hammering.
    final delayMs = (500 * (1 << _attempt.clamp(0, 5))).clamp(500, 15000);
    _attempt++;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), connect);
  }

  void _setState(WsState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    try {
      await _channel?.sink.close(ws_status.goingAway);
    } catch (_) {}
    await _controller.close();
    await _stateController.close();
  }
}
