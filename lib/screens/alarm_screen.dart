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

class _AlarmScreenState extends State<AlarmScreen>
    with SingleTickerProviderStateMixin {
  bool _isRefreshing = false;
  late AnimationController _refreshAnimController;
  late Animation<double> _refreshAnimation;

  @override
  void initState() {
    super.initState();
    
    // 刷新动画控制器
    _refreshAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _refreshAnimation = CurvedAnimation(
      parent: _refreshAnimController,
      curve: Curves.easeOutCubic,
    );
    
    // 加载闹钟数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlarmProvider>().loadAlarms();
    });
  }

  @override
  void dispose() {
    _refreshAnimController.dispose();
    super.dispose();
  }

  Future<void> _refreshAlarms(BuildContext context) async {
    if (_isRefreshing) return; // 防止重复刷新
    
    setState(() {
      _isRefreshing = true;
    });
    _refreshAnimController.forward();

    try {
      // 触觉反馈
      await HapticsService.instance.selection();
      
      // 刷新数据（不显示loading，因为有下拉动画）
      await context.read<AlarmProvider>().loadAlarms(showLoading: false);
      
      // 最小显示时间，让用户感知到刷新动作
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (mounted) {
        // 成功反馈
        await HapticsService.instance.impact();
        
        // 显示成功提示（可选）
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text('已刷新 ${context.read<AlarmProvider>().alarms.length} 个闹钟'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 1500),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // 错误反馈
        await HapticsService.instance.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('刷新失败: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
          ),
        );
      }
    } finally {
      if (mounted) {
        await _refreshAnimController.reverse();
        setState(() {
          _isRefreshing = false;
        });
      }
    }
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
              // 自定义颜色和样式
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              displacement: 40.0, // 下拉距离
              strokeWidth: 3.0, // 指示器粗细
              // 添加刷新状态提示
              notificationPredicate: (notification) {
                // 只在顶部触发刷新
                return notification.depth == 0;
              },
              child: CustomScrollView(
                slivers: [
                  // 刷新状态提示（可选）
                  if (_isRefreshing)
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '正在刷新...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

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
                      hasScrollBody: false, // 允许下拉刷新
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedOpacity(
                              opacity: _isRefreshing ? 0.3 : 1.0,
                              duration: const Duration(milliseconds: 300),
                              child: Icon(
                                Icons.alarm_off_outlined,
                                size: 80,
                                color: Colors.grey[300],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isRefreshing ? '正在刷新...' : '还没有闹钟',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[400],
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (!_isRefreshing)
                              Text(
                                '点击下方"+"按钮添加\n或下拉刷新',
                                textAlign: TextAlign.center,
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
                          
                          // 刷新时添加淡入动画
                          return FadeTransition(
                            opacity: _refreshAnimation,
                            child: AlarmListItem(
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
                            ),
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
