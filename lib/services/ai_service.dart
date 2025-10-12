import 'dart:async';
import 'package:flutter/foundation.dart';
import 'persona_store.dart';
import '../models/alarm.dart';
import 'ai_call_manager.dart';
import 'xiaozhi_service.dart';
import 'callkit_service.dart';

/// AIService: bridges alarm -> realtime AI call workflow.
class AIService {
  static final AIService instance = AIService._internal();

  AIService._internal();

  StreamSubscription<bool>? _connSub;
  bool _isCallKitSession = false;
  String? _callKitCallId;

  /// Start a realtime conversation for the given alarm, then send a directive
  /// text to the AI right after the connection is established.
  Future<void> startConversation({required Alarm alarm}) async {
    try {
      // 检查是否在CallKit会话中
      _isCallKitSession = CallKitService.instance.isInCallKitSession;
      _callKitCallId = CallKitService.instance.currentCallId;
      
      if (_isCallKitSession) {
        debugPrint('🤖 在CallKit会话中启动AI对话 (CallID: $_callKitCallId)');
      }
      
      // Always use realtime mode for alarm-initiated calls
      await AICallManager.instance.startCall(AICallMode.realtime);

      // After WS connected, send directive text once
      await _sendDirectiveAfterConnected(alarm);
    } catch (e) {
      debugPrint('AIService.startConversation failed: $e');
      // 如果在CallKit会话中启动失败，结束CallKit通话
      if (_isCallKitSession && _callKitCallId != null) {
        await CallKitService.instance.endCall(_callKitCallId!);
      }
    }
  }

  Future<void> stopConversation() async {
    // Forward to AICallManager to gracefully end
    try {
      await AICallManager.instance.endCall();
      debugPrint('🛑 AI对话已停止');
      
      // 如果在CallKit会话中，也结束CallKit通话（如果还没结束的话）
      if (_isCallKitSession && _callKitCallId != null) {
        if (CallKitService.instance.isInCallKitSession && 
            CallKitService.instance.currentCallId == _callKitCallId) {
          debugPrint('🔚 AI对话结束，同步结束CallKit通话');
          await CallKitService.instance.endCall(_callKitCallId!);
        }
      }
    } catch (e) {
      debugPrint('AIService.stopConversation failed: $e');
    } finally {
      await _connSub?.cancel();
      _connSub = null;
      _isCallKitSession = false;
      _callKitCallId = null;
    }
  }

  Future<void> _sendDirectiveAfterConnected(Alarm alarm) async {
    // If already connected, send immediately
    if (XiaozhiService.instance.isConnected) {
      await _sendDirectiveText(alarm);
      return;
    }

    // Otherwise, wait for the next true from connection stream
    final completer = Completer<void>();
    _connSub?.cancel();
    _connSub = XiaozhiService.instance.connectionStream.listen((ok) async {
      if (!ok) return;
      try {
        await _sendDirectiveText(alarm);
      } catch (e) {
        debugPrint('send directive after connected failed: $e');
      } finally {
        await _connSub?.cancel();
        _connSub = null;
        if (!completer.isCompleted) completer.complete();
      }
    });

    // Fallback timeout to avoid hanging forever
    unawaited(Future.delayed(const Duration(seconds: 8)).then((_) async {
      if (completer.isCompleted) return;
      try {
        // Try anyway even if we didn't observe the event
        if (XiaozhiService.instance.isConnected) {
          await _sendDirectiveText(alarm);
        }
      } catch (_) {}
      if (!completer.isCompleted) completer.complete();
    }));

    return completer.future;
  }

  Future<void> _sendDirectiveText(Alarm alarm) async {
    // 1) Try persona-based directive (alarm.aiPersonaId)
    String? directive;
    try {
      final persona = await PersonaStore.instance.getByIdMerged(alarm.aiPersonaId);
      if (persona != null) {
        final prompt = _applyDirectivePlaceholders(alarm, persona.systemPrompt);
        final opening = persona.openingLine.trim().isNotEmpty
            ? '\n开场白建议：${_applyDirectivePlaceholders(alarm, persona.openingLine)}'
            : '';
        final voiceHint = persona.voiceId.trim().isNotEmpty
            ? '\n音色：${persona.voiceId}（若支持）'
            : '';
        directive = '$prompt$opening$voiceHint';
      }
    } catch (_) {}

    // 2) Fallback to default directive if no persona found
    if (directive == null) {
      directive = _applyDirectivePlaceholders(alarm, _buildDefaultDirective(alarm));
    }

    // Use text channel to inject instruction into the conversation
    await XiaozhiService.instance.sendText(directive);
    debugPrint('📝 已发送闹钟指示词: $directive');
  }

  String _buildDefaultDirective(Alarm alarm) {
    final time = alarm.getFormattedTime();
    // Default gentle wake-up directive
    return '现在是$time，闹钟“${alarm.name}”已响铃。请用一句简短而有活力的话温柔唤醒我，然后等待我回应。';
  }

  String _applyDirectivePlaceholders(Alarm alarm, String text) {
    final now = DateTime.now();
    final hh = alarm.hour.toString().padLeft(2, '0');
    final mm = alarm.minute.toString().padLeft(2, '0');
    final time = '$hh:$mm';
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return text
        .replaceAll('{time}', time)
        .replaceAll('{alarm}', alarm.name)
        .replaceAll('{date}', date);
  }
}
