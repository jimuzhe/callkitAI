import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm.dart';
import '../utils/database_helper_hybrid.dart';
import '../services/platform_services.dart';
import '../services/sync_manager.dart';

class AlarmProvider extends ChangeNotifier {
  static AlarmProvider? _instance;
  static AlarmProvider? get instance => _instance;

  List<Alarm> _alarms = [];
  bool _isLoading = false;
  
  // 同步管理器
  final _syncManager = SyncManager.instance;

  List<Alarm> get alarms => _alarms;
  bool get isLoading => _isLoading;

  Alarm? get nextAlarm {
    final enabledAlarms = _alarms.where((a) => a.isEnabled).toList();
    if (enabledAlarms.isEmpty) return null;

    final now = DateTime.now();
    Alarm? nearest;
    Duration? shortestDuration;

    for (final alarm in enabledAlarms) {
      final nextTime = _calculateNextAlarmTime(alarm, now);
      if (nextTime == null) continue;

      final duration = nextTime.difference(now);
      if (shortestDuration == null || duration < shortestDuration) {
        shortestDuration = duration;
        nearest = alarm;
      }
    }

    return nearest;
  }

  AlarmProvider() {
    _instance = this;
    _initializeDataSource();
    _initSyncManager();
  }
  
  /// 初始化同步管理器
  void _initSyncManager() {
    // 启动自动同步
    _syncManager.startPeriodicSync();
  }

  /// 初始化数据源
  Future<void> _initializeDataSource() async {
    // 检查API可用性
    final isApiAvailable = await DatabaseHelperHybrid.instance.checkApiAvailable();
    DatabaseHelperHybrid.instance.setUseApi(isApiAvailable);
    
    if (isApiAvailable) {
      debugPrint('连接到远程服务器，开启云端同步');
    } else {
      debugPrint('远程服务器不可用，使用本地数据库');
    }
    
    await loadAlarms();
  }

  Future<void> loadAlarms() async {
    _isLoading = true;
    notifyListeners();

    try {
      _alarms = await DatabaseHelperHybrid.instance.getAllAlarms();
    } catch (e) {
      debugPrint('加载闹钟失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addAlarm({
    required String name,
    required int hour,
    required int minute,
    List<int> repeatDays = const [],
    String aiPersonaId = 'gentle',
  }) async {
    final alarm = Alarm(
      id: const Uuid().v4(),
      name: name,
      hour: hour,
      minute: minute,
      isEnabled: true,
      repeatDays: repeatDays,
      aiPersonaId: aiPersonaId,
      createdAt: DateTime.now(),
    );

    await DatabaseHelperHybrid.instance.createAlarm(alarm);
    await _scheduleAlarm(alarm);
    await loadAlarms();
    
    // 触发增量同步
    _syncManager.triggerIncrementalSync();
  }

  Future<void> updateAlarm(Alarm alarm) async {
    await DatabaseHelperHybrid.instance.updateAlarm(alarm);

    // 重新调度通知
    await NotificationService.instance.cancelNotification(alarm.id.hashCode);
    CallKitService.instance.cancelScheduledCall(alarm.id);
    
    if (alarm.isEnabled) {
      await _scheduleAlarm(alarm);
    }

    await loadAlarms();
    
    // 触发增量同步
    _syncManager.triggerIncrementalSync();
  }

  Future<void> toggleAlarm(String id, bool enabled) async {
    final alarm = _alarms.firstWhere((a) => a.id == id);
    final updated = alarm.copyWith(isEnabled: enabled);
    await updateAlarm(updated);
    if (!enabled) {
      CallKitService.instance.cancelScheduledCall(id);
    }
  }

  Future<void> deleteAlarm(String id) async {
    await NotificationService.instance.cancelNotification(id.hashCode);
    CallKitService.instance.cancelScheduledCall(id);
    await DatabaseHelperHybrid.instance.deleteAlarm(id);
    await loadAlarms();
    
    // 触发增量同步
    _syncManager.triggerIncrementalSync();
  }

  Future<void> _scheduleAlarm(Alarm alarm) async {
    final nextTime = _calculateNextAlarmTime(alarm, DateTime.now());
    if (nextTime != null) {
      // iOS: 若应用在前台或活跃状态，使用 CallKit；
      // 锁屏/后台/被系统回收时，无法自行唤起 CallKit，只能依赖 VoIP Push 或本地通知兜底。
      // 因此这里 iOS 也安排一条本地通知作为兜底，用户点进来后再弹 CallKit/进入通话页。
      await NotificationService.instance.scheduleAlarmNotification(
        id: alarm.id.hashCode,
        title: alarm.name,
        body: '点击接听AI通话',
        scheduledDate: nextTime,
        payload: alarm.id,
      );
      CallKitService.instance.scheduleIncomingCall(alarm, nextTime);
    }
  }

  DateTime? _calculateNextAlarmTime(Alarm alarm, DateTime from) {
    final now = from;

    if (alarm.nextAlarmTime != null && alarm.nextAlarmTime!.isAfter(now)) {
      return alarm.nextAlarmTime;
    }

    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      alarm.hour,
      alarm.minute,
    );

    // 如果今天的时间已过,则移到明天
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    // 如果是仅一次的闹钟
    if (alarm.repeatDays.isEmpty) {
      return scheduled;
    }

    // 如果是重复闹钟,找到下一个匹配的日期
    for (int i = 0; i < 7; i++) {
      final weekday = scheduled.weekday; // 1=周一, 7=周日
      if (alarm.repeatDays.contains(weekday)) {
        return scheduled;
      }
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return null;
  }

  Duration? getTimeUntilNextAlarm() {
    final next = nextAlarm;
    if (next == null) return null;

    final nextTime = _calculateNextAlarmTime(next, DateTime.now());
    if (nextTime == null) return null;

    return nextTime.difference(DateTime.now());
  }

  String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 24) {
      final days = hours ~/ 24;
      final remainingHours = hours % 24;
      return '$days天$remainingHours小时后';
    } else if (hours > 0) {
      return '$hours小时$minutes分钟后';
    } else {
      return '$minutes分钟后';
    }
  }

  // 快速设置闹钟
  Future<void> quickSetAlarm(int minutes, String name) async {
    final now = DateTime.now();
    final targetTime = now.add(Duration(minutes: minutes));

    await addAlarm(
      name: name,
      hour: targetTime.hour,
      minute: targetTime.minute,
      repeatDays: [], // 仅一次
    );
  }

  Alarm? getAlarmById(String id) {
    try {
      return _alarms.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> snoozeAlarm(String id, Duration offset) async {
    final currentAlarm =
        getAlarmById(id) ?? await DatabaseHelperHybrid.instance.getAlarmById(id);
    if (currentAlarm == null) return;

    final snoozedTime = DateTime.now().add(offset);
    final updated = currentAlarm.copyWith(nextAlarmTime: snoozedTime);

    await DatabaseHelperHybrid.instance.updateAlarm(updated);
    await NotificationService.instance.cancelNotification(
      currentAlarm.id.hashCode,
    );
    await NotificationService.instance.scheduleAlarmNotification(
      id: currentAlarm.id.hashCode,
      title: currentAlarm.name,
      body: 'AI助手将稍后再次来电',
      scheduledDate: snoozedTime,
      payload: currentAlarm.id,
    );
    CallKitService.instance.scheduleIncomingCall(updated, snoozedTime);

    await loadAlarms();
  }
}
