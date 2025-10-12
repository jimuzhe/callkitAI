import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import '../models/alarm.dart';
import '../utils/database_helper.dart';
import '../providers/alarm_provider.dart';
import './volume_service.dart';
import './haptics_service.dart';
import './audio_service.dart';
import './notification_service.dart';
import './ai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CallKitService {
  static final CallKitService instance = CallKitService._init();

  final Map<String, Alarm> _activeCalls = {};
  final Map<String, Timer> _pendingCallTimers = {};
  final Map<String, Timer> _prewarmTimers = {};
  static const Duration _prewarmWindow = Duration(seconds: 25);

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
    debugPrint('通话已接听: $callId');
    // 接通后停止后台保活
    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();

    var alarm = _activeCalls[callId];
    alarm ??= await DatabaseHelper.instance.getAlarmById(callId);

    if (alarm == null) {
      debugPrint('未找到对应闹钟信息,无法开始AI对话');
      return;
    }

    await AIService.instance.startConversation(alarm: alarm);
  }

  Future<void> _handleCallDeclined(String callId) async {
    debugPrint('通话被拒绝: $callId');
    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(callId);
  }

  Future<void> _handleCallEnded(String callId) async {
    debugPrint('通话已结束: $callId');
    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(callId);
  }

  Future<void> _handleCallTimeout(String callId) async {
    debugPrint('通话超时: $callId');
    await AudioService.instance.stopBackgroundKeepAlive();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(callId);
  }

  Future<void> endCall(String callId) async {
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
    await FlutterCallkitIncoming.endAllCalls();
    await NotificationService.instance.stopPanicNotifications();
    // 恢复音量
    await VolumeService.instance.restoreVolume();
    await _cleanupCall(null);
  }

  Future<String?> getVoipPushToken() async {
    if (_voipToken != null) return _voipToken;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('voip_push_token');
  }

}
