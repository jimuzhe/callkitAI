import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'xiaozhi_ws_connector.dart';

/// Lightweight protocol wrapper around XiaozhiWsConnector.
/// Provides convenience methods similar to the Python project's Protocol
/// (send_text, send_audio, send_start_listening, send_stop_listening), and
/// exposes the underlying stream for parsing incoming messages.
class XiaozhiProtocol {
  final XiaozhiWsConnector _connector;
  late final Stream<dynamic> _stream;

  XiaozhiProtocol._(this._connector) {
    _stream = _connector.stream.asBroadcastStream();
  }

  /// Connect and wrap the returned channel.
  static XiaozhiProtocol connect({
    required Uri uri,
    required String accessToken,
    required String protocolVersion,
    required String deviceId,
    required String clientId,
  }) {
    final ch = XiaozhiWsConnector.connect(
      uri: uri,
      accessToken: accessToken,
      protocolVersion: protocolVersion,
      deviceId: deviceId,
      clientId: clientId,
    );
    return XiaozhiProtocol._(ch);
  }

  /// Underlying stream (String or Uint8List)
  Stream<dynamic> get stream => _stream;

  /// Access to raw channel when needed by legacy code
  WebSocketChannel get channel => _connector.channel;

  /// Underlying sink operations
  void sendText(String text) {
    try {
      _connector.sink.add(text);
    } catch (_) {}
  }

  void sendAudio(Uint8List data) {
    try {
      _connector.sink.add(data);
    } catch (_) {}
  }

  void sendStartListening({required String mode, String? sessionId}) {
    final msg = <String, dynamic>{
      'type': 'listen',
      'state': 'start',
      'mode': mode,
    };
    if (sessionId != null && sessionId.isNotEmpty) {
      msg['session_id'] = sessionId;
    }
    sendText(jsonEncode(msg));
  }

  void sendStopListening({String? sessionId}) {
    final msg = <String, dynamic>{'type': 'listen', 'state': 'stop'};
    if (sessionId != null && sessionId.isNotEmpty) {
      msg['session_id'] = sessionId;
    }
    sendText(jsonEncode(msg));
  }

  void sendAbortSpeaking({required String reason}) {
    final msg = {'type': 'abort', 'reason': reason};
    sendText(jsonEncode(msg));
  }

  void sendTextWithMeta(String text, {Map<String, dynamic>? meta}) {
    final msg = <String, dynamic>{
      'type': 'text',
      'text': text,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (meta != null) {
      msg.addAll(meta);
    }
    sendText(jsonEncode(msg));
  }

  Future<void> close() async {
    try {
      await _connector.sink.close();
    } catch (_) {}
  }
}
