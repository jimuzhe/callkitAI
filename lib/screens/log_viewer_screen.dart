import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_log_service.dart';
import '../widgets/metallic_card.dart';

class LogViewerScreen extends StatelessWidget {
  const LogViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = AppLogService.instance.snapshot();
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统日志'),
        actions: [
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all),
            onPressed: () async {
              final entries = AppLogService.instance.snapshot();
              final messenger = ScaffoldMessenger.of(context);
              if (entries.isEmpty) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('没有可复制的日志')),
                );
                return;
              }
              final text = entries.join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              messenger.showSnackBar(
                SnackBar(content: Text('已复制 ${entries.length} 条日志')),
              );
            },
          ),
          IconButton(
            tooltip: '清空日志',
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              AppLogService.instance.clear();
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: AppLogService.instance.logListenable,
        builder: (context, value, _) {
          final entries = value.isEmpty ? logs : value;
          if (entries.isEmpty) {
            return const _EmptyLogsView();
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final log = entries[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: MetallicCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MetallicIconBox(icon: Icons.bubble_chart, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetallicText(
                          text: log,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyLogsView extends StatelessWidget {
  const _EmptyLogsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.receipt_long, size: 56, color: Colors.grey),
          SizedBox(height: 12),
          Text('暂无日志记录', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
