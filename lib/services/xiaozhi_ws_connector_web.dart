import 'dart:async';
// no-op
import 'package:web_socket_channel/web_socket_channel.dart';

// Minimal web implementation that uses web_socket_channel's WebSocketChannel
// This adapter provides a connect() function consistent with xiaozhi_ws_connector_io.

class XiaozhiWsConnector {
  final WebSocketChannel channel;
  XiaozhiWsConnector._(this.channel);

  Stream<dynamic> get stream => channel.stream;
  WebSocketSink get sink => channel.sink;

  static XiaozhiWsConnector connect({
    required Uri uri,
    required String accessToken,
    required String protocolVersion,
    required String deviceId,
    required String clientId,
  }) {
    final ch = WebSocketChannel.connect(uri);
    return XiaozhiWsConnector._(ch);
  }
}
