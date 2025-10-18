import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_log_service.dart';

class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  String _filter = '';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('实时日志'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.arrow_downward : Icons.pause),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
            tooltip: _autoScroll ? '暂停自动滚动' : '启用自动滚动',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              final logs = AppLogService.instance.snapshot();
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已复制到剪贴板')),
              );
            },
            tooltip: '复制全部日志',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              AppLogService.instance.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已清空')),
              );
            },
            tooltip: '清空日志',
          ),
        ],
      ),
      body: Column(
        children: [
          // 过滤器
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: '过滤日志 (例如: ❌, 🎤, WebSocket)',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _filter = '';
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _filter = value;
                });
              },
            ),
          ),
          // 日志列表
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: AppLogService.instance.logListenable,
              builder: (context, logs, _) {
                // 应用过滤
                final filteredLogs = _filter.isEmpty
                    ? logs
                    : logs.where((log) => log.contains(_filter)).toList();

                // 自动滚动到底部
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                if (filteredLogs.isEmpty) {
                  return Center(
                    child: Text(
                      _filter.isEmpty ? '暂无日志' : '没有匹配的日志',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: filteredLogs.length,
                  itemBuilder: (context, index) {
                    final log = filteredLogs[index];
                    final color = _getLogColor(log);
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      color: index % 2 == 0
                          ? Colors.transparent
                          : Colors.black.withOpacity(0.02),
                      child: SelectableText(
                        log,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: color,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _scrollToBottom,
        tooltip: '滚动到底部',
        child: const Icon(Icons.arrow_downward),
      ),
    );
  }

  Color _getLogColor(String log) {
    if (log.contains('❌') || log.contains('ERROR') || log.contains('失败')) {
      return Colors.red;
    }
    if (log.contains('⚠️') || log.contains('WARNING') || log.contains('警告')) {
      return Colors.orange;
    }
    if (log.contains('✅') || log.contains('成功')) {
      return Colors.green;
    }
    if (log.contains('🎤') || log.contains('麦克风')) {
      return Colors.blue;
    }
    if (log.contains('📞') || log.contains('CallKit')) {
      return Colors.purple;
    }
    if (log.contains('🔌') || log.contains('WebSocket') || log.contains('连接')) {
      return Colors.teal;
    }
    return Colors.black87;
  }
}
