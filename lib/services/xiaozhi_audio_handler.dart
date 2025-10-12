import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'audio_service.dart';

/// 简化的音频处理器 - 统一调用 AudioService
///
/// 职责：
/// - 接收 WebSocket 的音频数据（二进制或 JSON）
/// - 转发给 AudioService 的统一处理接口
class XiaozhiAudioHandler {
  XiaozhiAudioHandler._();

  static final XiaozhiAudioHandler instance = XiaozhiAudioHandler._();

  /// 处理二进制音频帧
  Future<void> processBinary(Uint8List bytes) async {
    if (bytes.isEmpty) return;

    // 直接转发给 AudioService 的统一处理接口
    unawaited(_handleBinary(bytes));
  }

  /// 处理 JSON 音频消息
  /// 返回 true 表示已处理音频内容
  Future<bool> processJson(Map<String, dynamic> msg) async {
    final type = (msg['type'] as String?) ?? '';
    if (type != 'audio') {
      return false;
    }

    final dataField = msg['data'];
    final urlField = msg['url'];
    final fmt = (msg['format'] as String?)?.toLowerCase();

    // 处理 base64 编码的音频数据
    if (dataField is String && dataField.isNotEmpty) {
      try {
        final bytes = base64Decode(dataField);
        await AudioService.instance.processAudioData(
          bytes,
          declaredFormat: fmt,
        );
        return true;
      } catch (e) {
        debugPrint('❌ [XiaozhiAudioHandler] base64 解码失败: $e');
        return false;
      }
    }

    // 处理音频 URL
    if (urlField is String && urlField.isNotEmpty) {
      try {
        await AudioService.instance.playAudioFromUrl(urlField);
        return true;
      } catch (e) {
        debugPrint('❌ [XiaozhiAudioHandler] 播放 URL 失败: $e');
        return false;
      }
    }

    debugPrint('⚠️ [XiaozhiAudioHandler] 音频消息缺少 data/url 字段');
    return false;
  }

  Future<void> _handleBinary(Uint8List bytes, {String? declaredFormat}) async {
    try {
      // 直接调用 AudioService 的统一处理接口
      await AudioService.instance.processAudioData(
        bytes,
        declaredFormat: declaredFormat,
      );
    } catch (e, stack) {
      debugPrint('❌ [XiaozhiAudioHandler] 处理二进制音频失败: $e');
      debugPrint('📍 $stack');
    }
  }
}
