import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/haptics_service.dart';
import '../providers/alarm_provider.dart';
import '../widgets/alarm_list_item.dart';
import '../widgets/next_alarm_card.dart';
import '../widgets/metallic_card.dart';
import './alarm_edit_screen.dart';

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  Future<void> _refreshAlarms(BuildContext context) async {
    await context.read<AlarmProvider>().loadAlarms();
  }

  @override
  void initState() {
    super.initState();
    // 加载闹钟数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlarmProvider>().loadAlarms();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<AlarmProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: () => _refreshAlarms(context),
              child: CustomScrollView(
                slivers: [
                  // 下一个闹钟倒计时卡片
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: NextAlarmCard(
                        nextAlarm: provider.nextAlarm,
                        duration: provider.getTimeUntilNextAlarm(),
                      ),
                    ),
                  ),

                  // 闹钟列表标题
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '我的闹钟',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${provider.alarms.length}个',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 闹钟列表
                  if (provider.alarms.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.alarm_off_outlined,
                              size: 80,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '还没有闹钟',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[400],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '点击下方"+"按钮添加',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final alarm = provider.alarms[index];
                          return AlarmListItem(
                            alarm: alarm,
                            onToggle: (enabled) async {
                              await provider.toggleAlarm(alarm.id, enabled);
                              await HapticsService.instance.impact();
                            },
                            onEdit: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      AlarmEditScreen(alarm: alarm),
                                ),
                              );
                            },
                            onDelete: () async {
                              // Dismissible已经有confirmDismiss确认,这里直接删除
                              await provider.deleteAlarm(alarm.id);
                              await HapticsService.instance.impact();
                            },
                          );
                        }, childCount: provider.alarms.length),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: MetallicButton(
        onPressed: () async {
          await HapticsService.instance.impact();
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AlarmEditScreen()),
            );
          }
        },
        isExtended: true,
        icon: Icons.add,
        child: const Text('新建闹钟'),
      ),
    );
  }
}
