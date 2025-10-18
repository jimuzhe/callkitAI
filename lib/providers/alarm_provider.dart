import 'dart:async';
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

  Future<void> loadAlarms({bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _alarms = await DatabaseHelperHybrid.instance.getAllAlarms();
    } catch (e) {
      debugPrint('加载闹钟失败: $e');
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
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

    // 🚀 乐观更新：立即添加到列表并刷新UI
    _alarms.add(alarm);
    notifyListeners();

    // 后台异步保存
    try {
      await DatabaseHelperHybrid.instance.createAlarm(alarm);
      await _scheduleAlarm(alarm);
      
      // 触发增量同步
      unawaited(_syncManager.triggerIncrementalSync());
    } catch (e) {
      debugPrint('❌ 添加闹钟失败: $e');
      // 如果失败，从列表中移除并重新加载
      _alarms.removeWhere((a) => a.id == alarm.id);
      await loadAlarms();
      rethrow;
    }
  }

  Future<void> updateAlarm(Alarm alarm) async {
    // 🚀 乐观更新：立即更新列表并刷新UI
    final index = _alarms.indexWhere((a) => a.id == alarm.id);
    final oldAlarm = index >= 0 ? _alarms[index] : null;
    
    if (index >= 0) {
      _alarms[index] = alarm;
      notifyListeners();
    }

    // 后台异步保存
    try {
      await DatabaseHelperHybrid.instance.updateAlarm(alarm);

      // 重新调度通知
      await NotificationService.instance.cancelNotification(alarm.id.hashCode);
      CallKitService.instance.cancelScheduledCall(alarm.id);
      
      if (alarm.isEnabled) {
        await _scheduleAlarm(alarm);
      }
      
      // 触发增量同步
      unawaited(_syncManager.triggerIncrementalSync());
    } catch (e) {
      debugPrint('❌ 更新闹钟失败: $e');
      // 如果失败，恢复旧值并重新加载
      if (oldAlarm != null && index >= 0) {
        _alarms[index] = oldAlarm;
      }
      await loadAlarms();
      rethrow;
    }
  }

  Future<void> toggleAlarm(String id, bool enabled) async {
    // 🚀 乐观更新：立即切换状态
    final index = _alarms.indexWhere((a) => a.id == id);
    if (index < 0) return;
    
    final oldAlarm = _alarms[index];
    final updated = oldAlarm.copyWith(isEnabled: enabled);
    
    _alarms[index] = updated;
    notifyListeners();

    // 后台异步保存
    try {
      await DatabaseHelperHybrid.instance.updateAlarm(updated);
      
      // 重新调度通知
      await NotificationService.instance.cancelNotification(updated.id.hashCode);
      CallKitService.instance.cancelScheduledCall(updated.id);
      
      if (enabled) {
        await _scheduleAlarm(updated);
      }
      
      // 触发增量同步
      unawaited(_syncManager.triggerIncrementalSync());
    } catch (e) {
      debugPrint('❌ 切换闹钟状态失败: $e');
      // 如果失败，恢复旧值
      _alarms[index] = oldAlarm;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteAlarm(String id) async {
    // 🚀 乐观更新：立即从列表移除
    final index = _alarms.indexWhere((a) => a.id == id);
    if (index < 0) return;
    
    final deletedAlarm = _alarms[index];
    _alarms.removeAt(index);
    notifyListeners();

    // 后台异步删除
    try {
      await NotificationService.instance.cancelNotification(id.hashCode);
      CallKitService.instance.cancelScheduledCall(id);
      await DatabaseHelperHybrid.instance.deleteAlarm(id);
      
      // 触发增量同步
      unawaited(_syncManager.triggerIncrementalSync());
    } catch (e) {
      debugPrint('❌ 删除闹钟失败: $e');
      // 如果失败，恢复删除的闹钟
      _alarms.insert(index, deletedAlarm);
      notifyListeners();
      rethrow;
    }
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

    // 🚀 乐观更新
    final index = _alarms.indexWhere((a) => a.id == id);
    if (index >= 0) {
      _alarms[index] = updated;
      notifyListeners();
    }

    // 后台异步保存
    try {
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
    } catch (e) {
      debugPrint('❌ 贪睡设置失败: $e');
      // 失败时重新加载
      await loadAlarms(showLoading: false);
      rethrow;
    }
  }

  /// 批量删除闹钟（优化版）
  Future<void> deleteAlarms(List<String> ids) async {
    if (ids.isEmpty) return;

    // 🚀 乐观更新：立即从列表移除所有
    final deletedAlarms = <int, Alarm>{};
    for (final id in ids) {
      final index = _alarms.indexWhere((a) => a.id == id);
      if (index >= 0) {
        deletedAlarms[index] = _alarms[index];
      }
    }
    
    _alarms.removeWhere((a) => ids.contains(a.id));
    notifyListeners();

    // 后台异步删除
    try {
      for (final id in ids) {
        await NotificationService.instance.cancelNotification(id.hashCode);
        CallKitService.instance.cancelScheduledCall(id);
        await DatabaseHelperHybrid.instance.deleteAlarm(id);
      }
      
      // 触发增量同步
      unawaited(_syncManager.triggerIncrementalSync());
    } catch (e) {
      debugPrint('❌ 批量删除闹钟失败: $e');
      // 如果失败，恢复删除的闹钟
      deletedAlarms.forEach((index, alarm) {
        _alarms.insert(index, alarm);
      });
      notifyListeners();
      rethrow;
    }
  }

  /// 刷新单个闹钟（用于后台更新后同步）
  Future<void> refreshAlarm(String id) async {
    try {
      final updated = await DatabaseHelperHybrid.instance.getAlarmById(id);
      if (updated == null) {
        // 闹钟已被删除
        _alarms.removeWhere((a) => a.id == id);
      } else {
        final index = _alarms.indexWhere((a) => a.id == id);
        if (index >= 0) {
          _alarms[index] = updated;
        } else {
          _alarms.add(updated);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ 刷新闹钟失败: $e');
    }
  }
}
