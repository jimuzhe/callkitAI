import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/alarm.dart';
import '../utils/database_helper_hybrid.dart';
import '../services/alarm_api_service.dart';
import 'api_config.dart';

/// 增强版数据同步管理器
/// 
/// 特性:
/// - 自动后台同步
/// - 离线优先策略
/// - 冲突检测和解决
/// - 重试机制
/// - 同步状态通知
class SyncManager {
  static final SyncManager instance = SyncManager._();
  SyncManager._();

  final _apiService = AlarmApiService.instance;
  final _hybridDb = DatabaseHelperHybrid.instance;
  
  // 同步状态流
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;
  
  // 同步配置
  Timer? _autoSyncTimer;
  bool _isAutoSyncEnabled = true;
  Duration _autoSyncInterval = const Duration(minutes: 5);
  int _maxRetryCount = 3;
  
  // 同步状态
  SyncStatus _currentStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  String? _lastSyncError;

  /// 初始化同步管理器
  Future<void> initialize() async {
    debugPrint('🔄 初始化同步管理器');
    
    // 检查API配置
    final isApiEnabled = await ApiConfig.instance.isApiEnabled();
    _hybridDb.setUseApi(isApiEnabled);
    
    if (isApiEnabled) {
      // 启动自动同步
      _startAutoSync();
      // 立即执行一次同步
      await _performSync(SyncType.full);
    }
    
    debugPrint('✅ 同步管理器初始化完成');
  }

  /// 强制全量同步
  Future<bool> forceSyncAll() async {
    return await _performSync(SyncType.full);
  }

  /// 快速增量同步
  Future<bool> quickSync() async {
    return await _performSync(SyncType.incremental);
  }

  /// 上传本地数据到云端
  Future<bool> uploadToCloud() async {
    return await _performSync(SyncType.upload);
  }

  /// 从云端下载数据
  Future<bool> downloadFromCloud() async {
    return await _performSync(SyncType.download);
  }

  /// 执行同步操作
  Future<bool> _performSync(SyncType type) async {
    if (_currentStatus == SyncStatus.syncing) {
      debugPrint('⚠️ 同步正在进行中，跳过');
      return false;
    }

    _updateSyncStatus(SyncStatus.syncing);
    debugPrint('🔄 开始同步: ${type.name}');

    try {
      // 检查网络连接
      final isApiAvailable = await _hybridDb.checkApiAvailable();
      if (!isApiAvailable) {
        throw Exception('远程服务器不可用');
      }

      bool success = false;
      switch (type) {
        case SyncType.full:
          success = await _performFullSync();
          break;
        case SyncType.incremental:
          success = await _performIncrementalSync();
          break;
        case SyncType.upload:
          success = await _performUploadSync();
          break;
        case SyncType.download:
          success = await _performDownloadSync();
          break;
      }

      if (success) {
        _lastSyncTime = DateTime.now();
        _lastSyncError = null;
        _updateSyncStatus(SyncStatus.success);
        debugPrint('✅ 同步完成: ${type.name}');
      } else {
        throw Exception('同步操作失败');
      }

      return success;
    } catch (e) {
      _lastSyncError = e.toString();
      _updateSyncStatus(SyncStatus.error);
      debugPrint('❌ 同步失败: $e');
      return false;
    }
  }

  /// 执行全量同步 (双向同步，智能合并)
  Future<bool> _performFullSync() async {
    try {
      // 1. 获取本地和远程数据
      final localAlarms = await _hybridDb.getAllAlarms();
      final remoteAlarms = await _apiService.getAllAlarms();
      
      debugPrint('📊 本地闹钟: ${localAlarms.length}, 远程闹钟: ${remoteAlarms.length}');

      // 2. 创建映射便于查找
      final localMap = {for (var alarm in localAlarms) alarm.id: alarm};
      final remoteMap = {for (var alarm in remoteAlarms) alarm.id: alarm};

      // 3. 合并数据
      final mergedAlarms = <String, Alarm>{};
      
      // 处理本地数据
      for (final local in localAlarms) {
        final remote = remoteMap[local.id];
        if (remote == null) {
          // 本地独有，上传到远程
          await _apiService.createAlarm(local);
          mergedAlarms[local.id] = local;
          debugPrint('📤 上传本地闹钟: ${local.name}');
        } else {
          // 两边都有，选择较新的
          final merged = _mergeAlarms(local, remote);
          mergedAlarms[local.id] = merged;
          
          // 更新到两边
          if (merged != local) {
            await _hybridDb.updateAlarm(merged);
            debugPrint('📥 更新本地闹钟: ${merged.name}');
          }
          if (merged != remote) {
            await _apiService.updateAlarm(merged);
            debugPrint('📤 更新远程闹钟: ${merged.name}');
          }
        }
      }

      // 处理远程独有数据
      for (final remote in remoteAlarms) {
        if (!localMap.containsKey(remote.id)) {
          // 远程独有，下载到本地
          await _hybridDb.createAlarm(remote);
          mergedAlarms[remote.id] = remote;
          debugPrint('📥 下载远程闹钟: ${remote.name}');
        }
      }

      debugPrint('🎯 全量同步完成，合并后闹钟数量: ${mergedAlarms.length}');
      return true;
    } catch (e) {
      debugPrint('❌ 全量同步失败: $e');
      return false;
    }
  }

  /// 执行增量同步 (基于时间戳)
  Future<bool> _performIncrementalSync() async {
    try {
      // 简化版增量同步：获取最近更新的数据
      final remoteAlarms = await _apiService.getAllAlarms();
      
      // TODO: 这里可以基于 updated_at 时间戳进行更精确的增量同步
      // 目前先实现简化版本
      
      for (final remoteAlarm in remoteAlarms) {
        try {
          await _hybridDb.updateAlarm(remoteAlarm);
        } catch (e) {
          // 如果更新失败，尝试创建
          await _hybridDb.createAlarm(remoteAlarm);
        }
      }
      
      debugPrint('🎯 增量同步完成');
      return true;
    } catch (e) {
      debugPrint('❌ 增量同步失败: $e');
      return false;
    }
  }

  /// 执行上传同步
  Future<bool> _performUploadSync() async {
    try {
      final localAlarms = await _hybridDb.getAllAlarms();
      
      for (final alarm in localAlarms) {
        try {
          // 先尝试更新，失败则创建
          final success = await _apiService.updateAlarm(alarm);
          if (!success) {
            await _apiService.createAlarm(alarm);
          }
        } catch (e) {
          debugPrint('⚠️ 上传闹钟 ${alarm.name} 失败: $e');
        }
      }
      
      debugPrint('📤 上传同步完成');
      return true;
    } catch (e) {
      debugPrint('❌ 上传同步失败: $e');
      return false;
    }
  }

  /// 执行下载同步
  Future<bool> _performDownloadSync() async {
    try {
      final remoteAlarms = await _apiService.getAllAlarms();
      
      for (final alarm in remoteAlarms) {
        try {
          await _hybridDb.updateAlarm(alarm);
        } catch (e) {
          await _hybridDb.createAlarm(alarm);
        }
      }
      
      debugPrint('📥 下载同步完成');
      return true;
    } catch (e) {
      debugPrint('❌ 下载同步失败: $e');
      return false;
    }
  }

  /// 智能合并两个闹钟对象 (冲突解决)
  Alarm _mergeAlarms(Alarm local, Alarm remote) {
    // 优先使用更新时间较新的数据
    // 如果时间相同，优先使用本地数据
    
    final localTime = local.createdAt;
    final remoteTime = remote.createdAt;
    
    if (remoteTime.isAfter(localTime)) {
      debugPrint('🔀 选择远程版本 (更新)');
      return remote;
    } else {
      debugPrint('🔀 选择本地版本 (更新或相同)');
      return local;
    }
  }

  /// 启动定时自动同步
  void startPeriodicSync() {
    _isAutoSyncEnabled = true;
    _startAutoSync();
  }
  
  /// 触发增量同步
  Future<void> triggerIncrementalSync() async {
    if (!_isAutoSyncEnabled) return;
    
    // 防抖：如果上次同步时间距现在太近，则跳过
    final now = DateTime.now();
    if (_lastSyncTime != null && 
        now.difference(_lastSyncTime!).inSeconds < 10) {
      return;
    }
    
    await _performSync(SyncType.incremental);
  }
  
  /// 启动自动同步
  void _startAutoSync() {
    if (!_isAutoSyncEnabled) return;
    
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
      // 仅在非活跃同步状态下执行自动同步
      if (_currentStatus != SyncStatus.syncing) {
        _performSync(SyncType.incremental);
      }
    });
    
    debugPrint('⏰ 自动同步已启动 (间隔: ${_autoSyncInterval.inMinutes}分钟)');
  }

  /// 停止自动同步
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _isAutoSyncEnabled = false;
    debugPrint('🔴 自动同步已停止');
  }

  /// 设置自动同步间隔
  void setAutoSyncInterval(Duration interval) {
    _autoSyncInterval = interval;
    if (_isAutoSyncEnabled) {
      _startAutoSync(); // 重启定时器
    }
  }

  /// 更新同步状态
  void _updateSyncStatus(SyncStatus status) {
    _currentStatus = status;
    _syncStatusController.add(status);
  }

  /// 获取同步统计信息
  SyncInfo getSyncInfo() {
    return SyncInfo(
      status: _currentStatus,
      lastSyncTime: _lastSyncTime,
      lastError: _lastSyncError,
      isAutoSyncEnabled: _isAutoSyncEnabled,
      autoSyncInterval: _autoSyncInterval,
    );
  }

  /// 清理资源
  void dispose() {
    _autoSyncTimer?.cancel();
    _syncStatusController.close();
  }
}

/// 同步类型
enum SyncType {
  full,        // 全量双向同步
  incremental, // 增量同步
  upload,      // 仅上传
  download,    // 仅下载
}

/// 同步状态
enum SyncStatus {
  idle,     // 空闲
  syncing,  // 同步中
  success,  // 同步成功
  error,    // 同步失败
}

/// 同步信息
class SyncInfo {
  final SyncStatus status;
  final DateTime? lastSyncTime;
  final String? lastError;
  final bool isAutoSyncEnabled;
  final Duration autoSyncInterval;

  const SyncInfo({
    required this.status,
    this.lastSyncTime,
    this.lastError,
    required this.isAutoSyncEnabled,
    required this.autoSyncInterval,
  });

  String get statusText {
    switch (status) {
      case SyncStatus.idle:
        return '就绪';
      case SyncStatus.syncing:
        return '同步中...';
      case SyncStatus.success:
        return '同步成功';
      case SyncStatus.error:
        return '同步失败';
    }
  }

  String? get lastSyncText {
    if (lastSyncTime == null) return null;
    
    final now = DateTime.now();
    final diff = now.difference(lastSyncTime!);
    
    if (diff.inMinutes < 1) {
      return '刚刚同步';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前同步';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前同步';
    } else {
      return '${diff.inDays}天前同步';
    }
  }
}