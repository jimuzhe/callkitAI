import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import '../models/alarm.dart';
import '../models/ai_call_state.dart';
import '../utils/database_helper.dart';
import '../providers/alarm_provider.dart';
import './volume_service.dart';
import './haptics_service.dart';
import './audio_service.dart';
import './notification_service.dart';
import './ai_service.dart';
import './ai_call_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallKitService {
  static final CallKitService instance = CallKitService._init();

  final Map<String, Alarm> _activeCalls = {};
  final Map<String, Timer> _pendingCallTimers = {};
  final Map<String, Timer> _prewarmTimers = {};
  static const Duration _prewarmWindow = Duration(seconds: 25);

  // 当前活跃的通话ID（用于在系统通话界面中进行AI对话）
  String? _currentCallId;
  bool _isInCallKitSession = false;

  CallKitService._init();
  String? _voipToken;

  Future<void> initialize() async {
    // 监听CallKit事件
    FlutterCallkitIncoming.onEvent.listen((event) async {
      debugPrint('CallKit事件: ${event?.event}');

      switch (event!.event) {
        case Event.actionCallAccept:
          // 用户接听电话
          await _handleCallAccepted(event.body['id']);
          break;
        case Event.actionCallDecline:
          // 用户拒接电话
          await _handleCallDeclined(event.body['id']);
          break;
        case Event.actionCallEnded:
          // 通话结束
          await _handleCallEnded(event.body['id']);
          break;
        case Event.actionCallTimeout:
          // 通话超时
          await _handleCallTimeout(event.body['id']);
          break;
        default:
          break;
      }
    });

    // 尝试获取并持久化 VoIP 推送令牌（iOS 真机）
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token != null && token.isNotEmpty) {
        _voipToken = token;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('voip_push_token', token);
      }
    } catch (_) {}

    // iOS 权限：通知权限在 NotificationService.initialize() 请求；
    // 麦克风/定位权限在应用启动阶段统一请求（见 main.dart）。
  }

  Future<void> startCall({
    required String uuid,
    required String callerName,
    String? handle,
    Alarm? alarm,
  }) async {
    final callKitParams = CallKitParams(
      id: uuid,
      nameCaller: callerName,
      appName: 'AI Call Clock',
      avatar: 'https://i.pravatar.cc/100',
      handle: handle ?? '888888',
      type: 1, // Audio call
      duration: 30000,
      textAccept: '接听',
      textDecline: '挂断',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: '未接来电',
        callbackText: '回拨',
      ),
      extra: <String, dynamic>{'userId': '1a2b3c4d'},
      headers: <String, dynamic>{'apiKey': 'Abc@123!', 'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#6366F1',
        backgroundUrl: 'https://i.pravatar.cc/500',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Incoming Call',
        missedCallNotificationChannelName: 'Missed Call',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 16000.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);

    if (alarm != null) {
      _activeCalls[uuid] = alarm;
      // 仅一次的闹钟在触发后自动禁用，避免再次被当作“下一个闹钟”
      try {
        if (alarm.repeatDays.isEmpty && alarm.isEnabled) {
          final updated = alarm.copyWith(isEnabled: false, nextAlarmTime: null);
          await DatabaseHelper.instance.updateAlarm(updated);
          // 通知前台刷新列表/下一次闹钟卡片
          try {
            AlarmProvider.instance?.loadAlarms();
          } catch (_) {}
        }
      } catch (_) {}
    } else {
      final stored = await DatabaseHelper.instance.getAlarmById(uuid);
      if (stored != null) {
        _activeCalls[uuid] = stored;
      }
    }
  }

  void scheduleIncomingCall(Alarm alarm, DateTime scheduledDate) {
    _pendingCallTimers[alarm.id]?.cancel();
    _prewarmTimers[alarm.id]?.cancel();

    final duration = scheduledDate.difference(DateTime.now());

    if (duration.isNegative) {
      unawaited(
        startCall(uuid: alarm.id, callerName: alarm.name, alarm: alarm),
      );
      return;
    }

    // 预热：在响铃前 _prewarmWindow 启动后台保活（可选）
    final prewarmStart = scheduledDate.subtract(_prewarmWindow);
    final prewarmDelay = prewarmStart.difference(DateTime.now());
    _prewarmTimers[alarm.id] = Timer(
      prewarmDelay.isNegative ? Duration.zero : prewarmDelay,
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.getBool('keep_alive_enabled') ?? false) {
            await AudioService.instance.startBackgroundKeepAlive();
          }
        } catch (_) {}
      },
    );

    _pendingCallTimers[alarm.id] = Timer(duration, () async {
      // 巨魔商店增强：设置最大音量
      await VolumeService.instance.setMaxVolume();

      // 启动呼叫
      await startCall(uuid: alarm.id, callerName: alarm.name, alarm: alarm);

      // 启动紧急通知（Critical Alert + 最大音量）
      unawaited(
        NotificationService.instance.startPanicNotifications(alarm: alarm),
      );

      // 巨魔商店增强：强烈震动提醒
      unawaited(HapticsService.instance.alertVibration());

      _pendingCallTimers.remove(alarm.id);
      _prewarmTimers.remove(alarm.id);
    });
  }

  void cancelScheduledCall(String alarmId) {
    _pendingCallTimers[alarmId]?.cancel();
    _pendingCallTimers.remove(alarmId);
    _prewarmTimers[alarmId]?.cancel();
    _prewarmTimers.remove(alarmId);
  }

  Future<void> _handleCallAccepted(String callId) async {
    debugPrint('📞 CallKit通话已接听: $callId');

    // 标记进入CallKit通话会话
    _currentCallId = callId;
    _isInCallKitSession = true;

    // 接通后停止后台保活和紧急通知
    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();

    // 不恢复音量，保持最大音量以便听清AI语音
    // await VolumeService.instance.restoreVolume();

    var alarm = _activeCalls[callId];
    alarm ??= await DatabaseHelper.instance.getAlarmById(callId);

    if (alarm == null) {
      debugPrint('❌ 未找到对应闹钟信息,无法开始AI对话');
      await _endCallKitSession(callId);
      return;
    }

    debugPrint('🤖 开始在CallKit通话界面中与小智对话');

    // 启动AI对话（将在CallKit通话会话中运行）
    try {
      await _startAICallInCallKitSession(alarm, callId);
    } catch (e) {
      debugPrint('❌ AI对话启动失败: $e');
      await _endCallKitSession(callId);
    }
  }

  /// 在CallKit通话会话中启动AI对话
  Future<void> _startAICallInCallKitSession(Alarm alarm, String callId) async {
    debugPrint('🎙️ 配置CallKit音频会话以支持AI对话');

    // 配置音频会话为实时对话模式
    try {
      // 确保音频服务已初始化
      await AudioService.instance.initialize();
      debugPrint('✅ 音频服务已初始化');
      
      // 切换到语音聊天模式（支持CallKit音频输入输出）
      await AudioService.instance.enterVoiceChatMode();
      debugPrint('✅ 音频会话已切换至语音聊天模式');
    } catch (e) {
      debugPrint('⚠️ 音频会话配置失败: $e，尝试继续');
    }

    // 启动AI对话服务（默认使用实时模式）
    try {
      await AIService.instance.startConversation(alarm: alarm);
      debugPrint('✅ AI实时对话已在CallKit通话界面中启动');
    } catch (e) {
      debugPrint('❌ AI对话启动失败: $e');
      rethrow;
    }

    // 监听AI对话结束事件，自动结束CallKit通话
    _monitorAICallAndEndCallKit(callId);
  }

  /// 监听AI对话状态，在对话结束时自动结束CallKit通话
  void _monitorAICallAndEndCallKit(String callId) {
    // 可以通过监听AICallManager的状态来判断对话是否结束
    // 这里使用一个简单的定时检查，或者你可以订阅AICallManager的stream
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isInCallKitSession || _currentCallId != callId) {
        timer.cancel();
        return;
      }

      // 检查AI对话是否仍在进行
      final session = AICallManager.instance.currentSession;
      if (!session.isConnected && session.state == AICallState.idle) {
        debugPrint('🔚 AI对话已结束，自动结束CallKit通话');
        timer.cancel();
        await _endCallKitSession(callId);
      }
    });
  }

  /// 结束CallKit通话会话
  Future<void> _endCallKitSession(String callId) async {
    if (!_isInCallKitSession || _currentCallId != callId) {
      return;
    }

    debugPrint('🔚 结束CallKit通话会话: $callId');
    _isInCallKitSession = false;
    _currentCallId = null;

    // 结束CallKit界面的通话
    await FlutterCallkitIncoming.endCall(callId);

    // 恢复音量
    await VolumeService.instance.restoreVolume();
  }

  Future<void> _handleCallDeclined(String callId) async {
    debugPrint('📵 CallKit通话被拒绝: $callId');
    _isInCallKitSession = false;
    _currentCallId = null;

    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(callId);
  }

  Future<void> _handleCallEnded(String callId) async {
    debugPrint('📴 CallKit通话已结束: $callId');
    _isInCallKitSession = false;
    _currentCallId = null;

    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(callId);
  }

  Future<void> _handleCallTimeout(String callId) async {
    debugPrint('⏱️ CallKit通话超时: $callId');
    _isInCallKitSession = false;
    _currentCallId = null;

    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(callId);
  }

  Future<void> endCall(String callId) async {
    debugPrint('🔚 手动结束CallKit通话: $callId');
    _isInCallKitSession = false;
    _currentCallId = null;

    await FlutterCallkitIncoming.endCall(callId);
    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(callId);
  }

  Future<void> _cleanupCall(String? callId) async {
    // 停止 AI 对话
    await AIService.instance.stopConversation();

    // 停止音频录制和播放
    await AudioService.instance.stopRecording();
    await AudioService.instance.stopPlaying();
    await AudioService.instance.stopBackgroundKeepAlive();

    if (callId != null) {
      _activeCalls.remove(callId);
      cancelScheduledCall(callId);
    } else {
      _activeCalls.clear();
      for (final timer in _pendingCallTimers.values) {
        timer.cancel();
      }
      _pendingCallTimers.clear();
      for (final timer in _prewarmTimers.values) {
        timer.cancel();
      }
      _prewarmTimers.clear();
    }
  }

  Future<void> endAllCalls() async {
    debugPrint('🔚 结束所有CallKit通话');
    _isInCallKitSession = false;
    _currentCallId = null;

    await FlutterCallkitIncoming.endAllCalls();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(null);
  }

  /// 获取当前是否在CallKit通话会话中
  bool get isInCallKitSession => _isInCallKitSession;

  /// 获取当前CallKit通话ID
  String? get currentCallId => _currentCallId;

  Future<String?> getVoipPushToken() async {
    if (_voipToken != null) return _voipToken;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('voip_push_token');
  }
}
