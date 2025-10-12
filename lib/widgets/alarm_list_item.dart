import 'package:flutter/material.dart';
import '../services/haptics_service.dart';
import '../models/alarm.dart';
import './metallic_card.dart';

class AlarmListItem extends StatelessWidget {
  final Alarm alarm;
  final Function(bool) onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const AlarmListItem({
    super.key,
    required this.alarm,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  // 触觉反馈统一由 HapticsService 控制

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: Key(alarm.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: isDark
                ? [Colors.transparent, const Color(0xFF6B3030)]
                : [Colors.transparent, const Color(0xFFE8C5C5)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline,
          color: isDark ? const Color(0xFFFFAAAA) : const Color(0xFF8B4545),
          size: 32,
        ),
      ),
      confirmDismiss: (direction) async {
        await HapticsService.instance.impact();

        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('确认删除'),
                content: Text('确定要删除闹钟"${alarm.name}"吗?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      '删除',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (direction) {
        onDelete();
      },
      child: MetallicCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        onTap: onEdit,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      MetallicText(
                        text: alarm.getFormattedTime(),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        isLarge: true,
                      ),
                      const SizedBox(width: 12),
                      if (!alarm.isEnabled)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (isDark ? Colors.grey[700] : Colors.grey[400])!
                                    .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDark
                                  ? Colors.grey[600]!
                                  : Colors.grey[400]!,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '已关闭',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MetallicText(
                    text: alarm.name,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.repeat,
                        size: 14,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        alarm.getRepeatDescription(),
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Switch(value: alarm.isEnabled, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}
