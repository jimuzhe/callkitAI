import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class XiaozhiWsConnector {
  XiaozhiWsConnector._(this._channel, this._streamController) {
    // 监听原始流并处理错误
    _subscription = _channel.stream.listen(
      (data) {
        if (!_streamController.isClosed) {
          _streamController.add(data);
        }
      },
      onError: (error) {
        debugPrint('❌ WebSocket流错误: $error');
        if (!_streamController.isClosed) {
          _streamController.addError(error);
        }
      },
      onDone: () {
        debugPrint('🔌 WebSocket流已关闭');
        if (!_streamController.isClosed) {
          _streamController.close();
        }
      },
    );
  }

  final WebSocketChannel _channel;
  final StreamController<dynamic> _streamController;
  StreamSubscription? _subscription;

  WebSocketChannel get channel => _channel;
  Stream<dynamic> get stream => _streamController.stream;
  WebSocketSink get sink => _channel.sink;

  static XiaozhiWsConnector connect({
    required Uri uri,
    required String accessToken,
    required String protocolVersion,
    required String deviceId,
    required String clientId,
  }) {
    final Map<String, dynamic> headers = {
      'Protocol-Version': protocolVersion,
      'Device-Id': deviceId,
      'Client-Id': clientId,
      // 添加额外的连接选项以提高稳定性
      'Connection': 'Upgrade',
      'Upgrade': 'websocket',
      'Sec-WebSocket-Version': '13',
      'User-Agent': 'CallClock/2.0.0 (Flutter)',
    };
    if (accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    
    try {
      // Debug: print headers (mask token)
      final masked = Map<String, dynamic>.from(headers);
      if (masked['Authorization'] is String) {
        masked['Authorization'] = (masked['Authorization'] as String)
            .replaceAll(RegExp(r'(.{6}).+(.{4})'), r"$1****$2");
      }
      debugPrint('🔗 XiaozhiWsConnectorIO 正在连接: $uri');
      debugPrint('📋 Headers: $masked');
    } catch (_) {}
    
    try {
      // 使用更宽松的连接参数提高兼容性
      final ws = IOWebSocketChannel.connect(
        uri,
        headers: headers,
        // 设置连接超时
        connectTimeout: const Duration(seconds: 10),
        // 增加ping间隔以保持连接活跃
        pingInterval: const Duration(seconds: 30),
      );
      
      final streamController = StreamController<dynamic>.broadcast();
      final connector = XiaozhiWsConnector._(ws, streamController);
      
      debugPrint('✅ WebSocket连接已建立');
      return connector;
    } catch (e) {
      debugPrint('❌ WebSocket连接失败: $e');
      rethrow;
    }
  }
  
  /// 优雅关闭连接
  Future<void> close() async {
    try {
      await _subscription?.cancel();
      await _streamController.close();
      await _channel.sink.close(WebSocketStatus.goingAway);
      debugPrint('🔌 WebSocket连接已优雅关闭');
    } catch (e) {
      debugPrint('⚠️ 关闭WebSocket时出现错误: $e');
    }
  }
}
