import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_config.dart';
import '../utils/database_helper_hybrid.dart';
import '../providers/alarm_provider.dart';
import '../services/sync_manager.dart';
import 'package:provider/provider.dart';

/// 数据同步设置页面
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _baseUrlController = TextEditingController();
  final _userIdController = TextEditingController();
  
  bool _isApiEnabled = true;
  bool _isLoading = false;
  bool _isApiAvailable = false;
  
  // 同步管理器
  final _syncManager = SyncManager.instance;
  SyncInfo? _syncInfo;
  StreamSubscription<SyncStatus>? _syncStatusSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkApiStatus();
    _initSyncManager();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _userIdController.dispose();
    _syncStatusSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final apiEnabled = await ApiConfig.instance.isApiEnabled();
    final baseUrl = await ApiConfig.instance.getBaseUrl();
    final userId = await ApiConfig.instance.getUserId();
    
    if (mounted) {
      setState(() {
        _isApiEnabled = apiEnabled;
        _baseUrlController.text = baseUrl;
        _userIdController.text = userId;
      });
    }
  }

  Future<void> _checkApiStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final isAvailable = await DatabaseHelperHybrid.instance.checkApiAvailable();
      if (mounted) {
        setState(() {
          _isApiAvailable = isAvailable;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isApiAvailable = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    
    try {
      await ApiConfig.instance.setApiEnabled(_isApiEnabled);
      await ApiConfig.instance.setBaseUrl(_baseUrlController.text.trim());
      await ApiConfig.instance.setUserId(_userIdController.text.trim());
      
      // 更新混合数据源配置
      DatabaseHelperHybrid.instance.setUseApi(_isApiEnabled);
      
      // 检查新配置下的API状态
      await _checkApiStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设置已保存'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncToRemote() async {
    setState(() => _isLoading = true);
    
    try {
      final success = await _syncManager.uploadToCloud();
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('同步到云端完成'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('上传同步失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncFromRemote() async {
    setState(() => _isLoading = true);
    
    try {
      final success = await _syncManager.downloadFromCloud();
      
      if (success) {
        // 刷新闹钟列表
        final provider = Provider.of<AlarmProvider>(context, listen: false);
        await provider.loadAlarms();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('从云端同步完成'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('同步操作失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  /// 初始化同步管理器
  Future<void> _initSyncManager() async {
    // 监听同步状态
    _syncStatusSub = _syncManager.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _syncInfo = _syncManager.getSyncInfo();
        });
      }
    });
    
    // 获取初始同步信息
    setState(() {
      _syncInfo = _syncManager.getSyncInfo();
    });
  }
  
  /// 全量同步
  Future<void> _performFullSync() async {
    setState(() => _isLoading = true);
    
    try {
      final success = await _syncManager.forceSyncAll();
      
      if (success) {
        // 刷新闹钟列表
        final provider = Provider.of<AlarmProvider>(context, listen: false);
        await provider.loadAlarms();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('全量同步完成'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('全量同步失败');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('云端同步设置'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // API状态
          _buildStatusCard(),
          const SizedBox(height: 16),
          
          // API开关
          _buildApiToggle(),
          const SizedBox(height: 16),
          
          // 服务器配置
          if (_isApiEnabled) ...[
            _buildServerConfig(),
            const SizedBox(height: 16),
          ],
          
          // 同步状态
          if (_isApiEnabled && _isApiAvailable) ...[
            _buildSyncStatusCard(),
            const SizedBox(height: 16),
          ],
          
          // 同步操作
          if (_isApiEnabled && _isApiAvailable) ...[
            _buildSyncActions(),
            const SizedBox(height: 16),
          ],
          
          // 保存按钮
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '连接状态',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _isApiAvailable ? Icons.cloud_done : Icons.cloud_off,
                  color: _isApiAvailable ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _isApiAvailable ? '已连接到云端服务器' : '云端服务器不可用',
                  style: TextStyle(
                    color: _isApiAvailable ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _checkApiStatus,
                  child: const Text('检查连接'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiToggle() {
    return Card(
      child: SwitchListTile(
        title: const Text('启用云端同步'),
        subtitle: const Text('关闭后将仅使用本地数据库'),
        value: _isApiEnabled,
        onChanged: (value) {
          setState(() => _isApiEnabled = value);
        },
      ),
    );
  }

  Widget _buildServerConfig() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '服务器配置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'API服务器地址',
                hintText: 'http://localhost:5000/api',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: '用户ID',
                hintText: 'user_001',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '同步状态',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildSyncInfoWidget(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSyncActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '手动同步',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _syncToRemote,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('上传到云端'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _syncFromRemote,
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('从云端下载'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _performFullSync,
                icon: const Icon(Icons.sync),
                label: const Text('全量同步'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveSettings,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: const Text('保存设置'),
      ),
    );
  }
  
  /// 构建同步信息显示 Widget
  Widget _buildSyncInfoWidget() {
    if (_syncInfo == null) {
      return const Text('没有同步信息');
    }
    
    final info = _syncInfo!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _getSyncStatusIcon(info.status),
              color: _getSyncStatusColor(info.status),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              _getSyncStatusText(info.status),
              style: TextStyle(
                color: _getSyncStatusColor(info.status),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (info.lastSyncTime != null) ...
          [
            Text(
              '上次同步: ${_formatDateTime(info.lastSyncTime!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
          ],
        if (info.lastError != null)
          Text(
            '错误: ${info.lastError}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        if (info.status == SyncStatus.syncing)
          Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                '同步中...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
      ],
    );
  }
  
  /// 获取同步状态图标
  IconData _getSyncStatusIcon(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return Icons.sync_disabled;
      case SyncStatus.syncing:
        return Icons.sync;
      case SyncStatus.success:
        return Icons.sync_alt;
      case SyncStatus.error:
        return Icons.sync_problem;
    }
  }
  
  /// 获取同步状态颜色
  Color _getSyncStatusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return Colors.grey;
      case SyncStatus.syncing:
        return Colors.blue;
      case SyncStatus.success:
        return Colors.green;
      case SyncStatus.error:
        return Colors.red;
    }
  }
  
  /// 获取同步状态文本
  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return '空闲';
      case SyncStatus.syncing:
        return '同步中';
      case SyncStatus.success:
        return '同步成功';
      case SyncStatus.error:
        return '同步失败';
    }
  }
  
  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
