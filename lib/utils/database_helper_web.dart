// Minimal web stub for DatabaseHelper
// For web builds, database operations are no-op; stub interface matches IO implementation.

import '../models/alarm.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._();
  DatabaseHelper._();

  /// Web 平台初始化占位
  Future<void> init() async {}

  /// Web 不提供实际数据库，接口保持一致
  Future<void> get database async {}

  Future<List<Alarm>> getAllAlarms() async => <Alarm>[];

  Future<Alarm?> getAlarmById(String id) async => null;

  Future<Alarm> createAlarm(Alarm alarm) async => alarm;

  Future<int> updateAlarm(Alarm alarm) async => 0;

  Future<int> deleteAlarm(String id) async => 0;
}
