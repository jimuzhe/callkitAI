import 'dart:async';
import '../models/alarm.dart';
import '../services/alarm_api_service.dart';
import 'database_helper_io.dart' as local_db;

/// 混合数据源的数据库助手
/// 优先使用远程API，失败时回退到本地数据库
class DatabaseHelperHybrid {
  static final DatabaseHelperHybrid instance = DatabaseHelperHybrid._();
  DatabaseHelperHybrid._();

  final _apiService = AlarmApiService.instance;
  final _localDb = local_db.DatabaseHelper.instance;
  
  // 是否使用API模式
  bool _useApi = true;

  void _fireAndForget(Future<void> Function() task, String debugTag) {
    unawaited(
      task().catchError((error, stack) {
        print('[$debugTag] 远程操作失败: $error');
      }),
    );
  }

  /// 检查API是否可用
  Future<bool> checkApiAvailable() async {
    return await _apiService.checkHealth();
  }

  /// 设置是否使用API
  void setUseApi(bool use) {
    _useApi = use;
  }

  /// 获取单个闹钟
  Future<Alarm?> getAlarmById(String id) async {
    if (_useApi) {
      try {
        final alarm = await _apiService.getAlarmById(id);
        if (alarm != null) {
          // 同步到本地数据库
          try {
            await _localDb.updateAlarm(alarm);
          } catch (e) {
            await _localDb.createAlarm(alarm);
          }
          return alarm;
        }
      } catch (e) {
        print('API获取闹钟失败，回退到本地: $e');
      }
    }
    // 回退到本地数据库
    return await _localDb.getAlarmById(id);
  }

  /// 创建闹钟
  Future<Alarm> createAlarm(Alarm alarm) async {
    // 先保存到本地
    await _localDb.createAlarm(alarm);
    
    if (_useApi) {
      _fireAndForget(() async {
        final result = await _apiService.createAlarm(alarm);
        if (result != null) {
          print('[createAlarm] 闹钟已同步到远程服务器');
        } else {
          print('[createAlarm] 远程同步失败，仅保存在本地');
        }
      }, 'createAlarm');
    }
    
    return alarm;
  }

  /// 获取所有闹钟
  Future<List<Alarm>> getAllAlarms() async {
    if (_useApi) {
      try {
        final alarms = await _apiService.getAllAlarms();
        // 同步到本地数据库
        for (final alarm in alarms) {
          try {
            await _localDb.updateAlarm(alarm);
          } catch (e) {
            // 如果更新失败，尝试创建
            try {
              await _localDb.createAlarm(alarm);
            } catch (createError) {
              print('同步闹钟到本地失败: $createError');
            }
          }
        }
        return alarms;
      } catch (e) {
        print('API获取闹钟列表失败，回退到本地: $e');
      }
    }
    // 回退到本地数据库
    return await _localDb.getAllAlarms();
  }

  /// 更新闹钟
  Future<int> updateAlarm(Alarm alarm) async {
    // 先更新本地
    final localResult = await _localDb.updateAlarm(alarm);
    
    if (_useApi) {
      _fireAndForget(() async {
        final success = await _apiService.updateAlarm(alarm);
        if (success) {
          print('[updateAlarm] 闹钟已同步到远程服务器');
        } else {
          print('[updateAlarm] 远程同步失败，仅更新本地');
        }
      }, 'updateAlarm');
    }
    
    return localResult;
  }

  /// 删除闹钟
  Future<int> deleteAlarm(String id) async {
    // 先删除本地
    final localResult = await _localDb.deleteAlarm(id);
    
    if (_useApi) {
      _fireAndForget(() async {
        final success = await _apiService.deleteAlarm(id);
        if (success) {
          print('[deleteAlarm] 闹钟已从远程服务器删除');
        } else {
          print('[deleteAlarm] 远程删除失败，仅删除本地');
        }
      }, 'deleteAlarm');
    }
    
    return localResult;
  }

  /// 同步本地闹钟到远程
  Future<void> syncToRemote() async {
    if (!_useApi) return;
    
    try {
      print('开始同步本地闹钟到远程...');
      final localAlarms = await _localDb.getAllAlarms();
      
      for (final alarm in localAlarms) {
        try {
          await _apiService.updateAlarm(alarm);
        } catch (e) {
          // 如果更新失败，尝试创建
          try {
            await _apiService.createAlarm(alarm);
          } catch (createError) {
            print('同步闹钟 ${alarm.id} 失败: $createError');
          }
        }
      }
      
      print('同步完成');
    } catch (e) {
      print('同步失败: $e');
    }
  }

  /// 从远程同步到本地
  Future<void> syncFromRemote() async {
    if (!_useApi) return;
    
    try {
      print('开始从远程同步闹钟...');
      final remoteAlarms = await _apiService.getAllAlarms();
      
      for (final alarm in remoteAlarms) {
        try {
          await _localDb.updateAlarm(alarm);
        } catch (e) {
          // 如果更新失败，尝试创建
          try {
            await _localDb.createAlarm(alarm);
          } catch (createError) {
            print('同步闹钟 ${alarm.id} 到本地失败: $createError');
          }
        }
      }
      
      print('同步完成');
    } catch (e) {
      print('同步失败: $e');
    }
  }

  // 日志相关方法直接使用本地数据库
  Future<void> log(String level, String message) async {
    return _localDb.log(level, message);
  }

  Future<List<Map<String, dynamic>>> getLogs({int limit = 100}) async {
    return _localDb.getLogs(limit: limit);
  }

  Future<void> clearOldLogs({int daysToKeep = 7}) async {
    return _localDb.clearOldLogs(daysToKeep: daysToKeep);
  }

  Future<void> close() async {
    return _localDb.close();
  }
}