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

      // 🔥 关键修复：先准备指示词，在连接建立后立即发送（在麦克风启动前）
      debugPrint('📝 准备闹钟指示词...');
      final directiveText = await _prepareDirectiveText(alarm);
      debugPrint('✅ 指示词已准备，长度: ${directiveText.length}');

      // Always use realtime mode for alarm-initiated calls
      await AICallManager.instance.startCall(AICallMode.realtime);

      // 🔥 在连接成功后立即发送指示词（优先级最高）
      await _sendDirectiveAfterConnected(alarm, prebuiltDirective: directiveText);
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

  Future<void> _sendDirectiveAfterConnected(
    Alarm alarm, {
    String? prebuiltDirective,
  }) async {
    // If already connected, send immediately
    if (XiaozhiService.instance.isConnected) {
      debugPrint('🚀 连接已建立，立即发送指示词');
      await _sendDirectiveText(alarm, prebuiltDirective: prebuiltDirective);
      return;
    }

    // Otherwise, wait for the next true from connection stream
    final completer = Completer<void>();
    _connSub?.cancel();
    _connSub = XiaozhiService.instance.connectionStream.listen((ok) async {
      if (!ok) return;
      try {
        debugPrint('🚀 连接成功，立即发送指示词');
        await _sendDirectiveText(alarm, prebuiltDirective: prebuiltDirective);
      } catch (e) {
        debugPrint('send directive after connected failed: $e');
      } finally {
        await _connSub?.cancel();
        _connSub = null;
        if (!completer.isCompleted) completer.complete();
      }
    });

    // Fallback timeout to avoid hanging forever
    unawaited(
      Future.delayed(const Duration(seconds: 8)).then((_) async {
        if (completer.isCompleted) return;
        try {
          // Try anyway even if we didn't observe the event
          if (XiaozhiService.instance.isConnected) {
            debugPrint('⏱️ 超时后尝试发送指示词');
            await _sendDirectiveText(alarm, prebuiltDirective: prebuiltDirective);
          }
        } catch (_) {}
        if (!completer.isCompleted) completer.complete();
      }),
    );

    return completer.future;
  }

  /// 预先构建指示词文本（不发送）
  Future<String> _prepareDirectiveText(Alarm alarm) async {
    // 构建闹钟上下文信息
    final alarmContext = _buildAlarmContext(alarm);

    // 1) Try persona-based directive (alarm.aiPersonaId)
    String? directive;
    try {
      final persona = await PersonaStore.instance.getByIdMerged(
        alarm.aiPersonaId,
      );
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
      directive = _applyDirectivePlaceholders(
        alarm,
        _buildDefaultDirective(alarm),
      );
    }

    // 3) 将闹钟上下文信息添加到指示词前面
    return '$alarmContext\n\n$directive';
  }

  Future<void> _sendDirectiveText(
    Alarm alarm, {
    String? prebuiltDirective,
  }) async {
    final fullDirective = prebuiltDirective ?? await _prepareDirectiveText(alarm);

    // 获取人设名称用于日志
    String? personaName;
    try {
      final persona = await PersonaStore.instance.getByIdMerged(
        alarm.aiPersonaId,
      );
      personaName = persona?.name;
    } catch (_) {}

    // Use text channel to inject instruction into the conversation
    await XiaozhiService.instance.sendText(fullDirective);
    debugPrint('📝 已发送闹钟指示词 (包含上下文)');
    debugPrint('   闹钟: ${alarm.name}');
    debugPrint('   人设: ${personaName ?? "默认"}');
    debugPrint('   时间: ${alarm.getFormattedTime()}');
    debugPrint('   指示词长度: ${fullDirective.length} 字符');
  }

  /// 构建闹钟上下文信息，让小智了解闹钟的目的
  String _buildAlarmContext(Alarm alarm) {
    final time = alarm.getFormattedTime();
    final repeatDesc = alarm.getRepeatDescription();
    final now = DateTime.now();
    final date =
        '${now.year}年${now.month}月${now.day}日 ${_getWeekdayName(now.weekday)}';

    // 构建上下文信息
    final context = StringBuffer();
    context.writeln('【闹钟上下文信息】');
    context.writeln('当前时间：$date $time');
    context.writeln('闹钟名称：${alarm.name}');
    context.writeln('闹钟类型：$repeatDesc');
    context.writeln('---');
    context.writeln('请根据以上信息，以合适的方式与用户对话，帮助用户完成闹钟设定的任务。');

    return context.toString();
  }

  /// 获取星期名称
  String _getWeekdayName(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[weekday - 1];
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
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return text
        .replaceAll('{time}', time)
        .replaceAll('{alarm}', alarm.name)
        .replaceAll('{date}', date);
  }
}
