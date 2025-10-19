import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm.dart';
import '../utils/database_helper.dart';
import './callkit_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _panicModeEnabled = false;
  int _panicNotificationCount = 200;
  int _panicNotificationIntervalSeconds = 3;
  final Set<int> _panicNotificationIds = <int>{};
  bool _timeZoneConfigured = false;
  Timer? _panicTimer; // 用于实时发送通知

  NotificationService._init();

  Future<void> initialize() async {
    // 请求通知权限（包括 Critical Alerts）
    await Permission.notification.request();
    await Permission.criticalAlerts.request(); // 关键警报权限
    await _refreshPanicConfig();
    await _ensureTimeZoneConfigured();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS 通知分类与动作（接听/稍后提醒）
    final iosCategory = DarwinNotificationCategory(
      'AI_CALL_CATEGORY',
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.plain(
          'ACCEPT',
          '接听',
          options: {
            DarwinNotificationActionOption.authenticationRequired,
            DarwinNotificationActionOption.foreground,
          },
        ),
        DarwinNotificationAction.plain('SNOOZE_5', '稍后提醒(5分钟)'),
      ],
      options: {DarwinNotificationCategoryOption.customDismissAction},
    );

    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: <DarwinNotificationCategory>[iosCategory],
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  Future<void> _refreshPanicConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _panicModeEnabled = prefs.getBool('panic_mode_enabled') ?? false;
    _panicNotificationCount = prefs.getInt('panic_notification_count') ?? 200;
    _panicNotificationIntervalSeconds =
        prefs.getInt('panic_notification_interval') ?? 3;
  }

  Future<void> refreshPanicConfig() => _refreshPanicConfig();

  Future<void> _ensureTimeZoneConfigured() async {
    if (_timeZoneConfigured) return;
    try {
      final timeZoneName = await FlutterNativeTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      _timeZoneConfigured = true;
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
      _timeZoneConfigured = true;
    }
  }

  bool get panicModeEnabled => _panicModeEnabled;
  int get panicNotificationCount => _panicNotificationCount;
  int get panicNotificationIntervalSeconds => _panicNotificationIntervalSeconds;

  void _onNotificationTapped(NotificationResponse response) async {
    final alarmId = response.payload;
    if (alarmId == null) return;
    final alarm = await DatabaseHelper.instance.getAlarmById(alarmId);
    if (alarm == null) return;

    // 根据 iOS 行为按钮执行不同动作
    final actionId = response.actionId;
    if (actionId == 'SNOOZE_5') {
      await stopPanicNotifications();
      // 延后 5 分钟
      final newTime = DateTime.now().add(const Duration(minutes: 5));
      await scheduleAlarmNotification(
        id: alarm.id.hashCode,
        title: alarm.name,
        body: 'AI助手将稍后再次来电',
        scheduledDate: newTime,
        payload: alarm.id,
      );
      // 同步 CallKit 计划（前台可直接弹，后台作为兜底）
      CallKitService.instance.scheduleIncomingCall(alarm, newTime);
      return;
    }

    // 默认：接听（或正文点击）
    await stopPanicNotifications();
    await CallKitService.instance.startCall(
      uuid: alarm.id,
      callerName: alarm.name,
      alarm: alarm,
    );
  }

  Future<void> startPanicNotifications({required Alarm alarm}) async {
    await _refreshPanicConfig();
    if (!_panicModeEnabled) return;
    if (_panicNotificationCount <= 0) return;

    await stopPanicNotifications();

    final intervalSeconds = _panicNotificationIntervalSeconds.clamp(1, 3600);
    final effectiveCount = _panicNotificationCount.clamp(1, 60);
    
    debugPrint('🚨 开始急中生智模式：$effectiveCount 条通知，间隔 $intervalSeconds 秒');
    
    // 立即显示第一条通知
    int currentIndex = 0;
    await _showPanicNotification(alarm, currentIndex, effectiveCount);
    currentIndex++;
    
    // 使用 Timer.periodic 持续发送通知（绕过 iOS 后台限制）
    _panicTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (timer) async {
        if (currentIndex >= effectiveCount) {
          timer.cancel();
          debugPrint('✅ 急中生智通知已全部发送');
          return;
        }
        
        await _showPanicNotification(alarm, currentIndex, effectiveCount);
        currentIndex++;
      },
    );
  }
  
  /// 显示单条急中生智通知
  Future<void> _showPanicNotification(Alarm alarm, int index, int total) async {
    final id = _composePanicNotificationId(alarm.id, index);
    _panicNotificationIds.add(id);
    
    debugPrint('📢 准备发送通知 #${index + 1}/$total (ID: $id)');
    
    const title = '紧急唤醒';
    final body = 'AI 正在呼叫你，请立即应答！ [${index + 1}/$total]';
    
    const notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'panic_channel',
        '紧急唤醒通知',
        channelDescription: '连续唤醒用户的紧急提醒',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
      ),
      iOS: DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.critical,
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
        categoryIdentifier: 'AI_CALL_CATEGORY',
        sound: 'default',
      ),
    );
    
    try {
      await _notifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: alarm.id,
      );
      debugPrint('✅ 发送通知 #${index + 1}/$total');
    } catch (e) {
      debugPrint('❌ 发送通知 #${index + 1} 失败: $e');
    }
  }

  Future<void> stopPanicNotifications() async {
    // 停止定时器
    _panicTimer?.cancel();
    _panicTimer = null;
    
    // 取消所有通知
    for (final id in _panicNotificationIds) {
      await _notifications.cancel(id);
    }
    _panicNotificationIds.clear();
    
    debugPrint('🛑 急中生智通知已停止');
  }

  int _composePanicNotificationId(String alarmId, int index) {
    // 确保ID在32位整数范围内：[-2^31, 2^31 - 1]
    // 最大值：2147483647 (约21亿)
    
    // 方案：使用alarmId的hashCode的低位 + index
    // 1. 取hashCode的绝对值
    // 2. 限制在2000万以内（留出空间给index）
    // 3. 乘以100（最多支持100个通知）+ index
    
    final base = (alarmId.hashCode.abs() % 20000000); // 限制在2000万以内
    final id = base * 100 + index; // 最大：2000000000 + 100 = 2000000100
    
    // 确保不超过32位整数最大值
    return id.clamp(0, 2147483647);
  }

  Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'alarm_channel',
      'Alarm Notifications',
      channelDescription: 'AI闹钟通知',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      // 注意：Critical 需要额外申请权限，若无则按普通高优先级展示
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: 'AI_CALL_CATEGORY',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    await stopPanicNotifications();
  }

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'immediate_channel',
      'Immediate Notifications',
      channelDescription: '即时通知',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(id, title, body, details);
  }
}
