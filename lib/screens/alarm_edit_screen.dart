import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../services/haptics_service.dart';
import '../models/alarm.dart';
import '../models/ai_persona.dart';
import '../services/persona_store.dart';
import 'persona_manager_screen.dart';
import '../providers/alarm_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_service.dart';

class AlarmEditScreen extends StatefulWidget {
  final Alarm? alarm; // null表示新建,非null表示编辑

  const AlarmEditScreen({super.key, this.alarm});

  @override
  State<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  late TextEditingController _nameController;
  late int _selectedHour;
  late int _selectedMinute;
  late Set<int> _selectedDays;
  late String _selectedPersonaId;
  List<AIPersona> _personas = AIPersona.presets;
  bool _loadingPersonas = true;

  final List<String> _dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();

    if (widget.alarm != null) {
      // 编辑模式
      _nameController = TextEditingController(text: widget.alarm!.name);
      _selectedHour = widget.alarm!.hour;
      _selectedMinute = widget.alarm!.minute;
      _selectedDays = widget.alarm!.repeatDays.toSet();
      _selectedPersonaId = widget.alarm!.aiPersonaId;
    } else {
      // 新建模式
      _nameController = TextEditingController(text: '起床闹钟');
      final now = DateTime.now();
      _selectedHour = now.hour;
      _selectedMinute = now.minute;
      _selectedDays = {};
      _selectedPersonaId = 'gentle';
      // 读取用户在设置中选择的默认人设
      _loadDefaultPersona();
    }
    _loadPersonas();
  }

  Future<void> _loadDefaultPersona() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('default_persona_id');
      if (id != null && id.isNotEmpty && mounted) {
        setState(() {
          _selectedPersonaId = id;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadPersonas() async {
    setState(() => _loadingPersonas = true);
    try {
      final merged = await PersonaStore.instance.getAllMerged();
      if (!mounted) return;
      setState(() {
        _personas = merged;
        _loadingPersonas = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPersonas = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.alarm == null ? '新建闹钟' : '编辑闹钟'),
        actions: [
          TextButton(
            onPressed: _saveAlarm,
            child: const Text(
              '保存',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 时间选择器
          _buildTimePickerCard(),
          const SizedBox(height: 16),

          // 闹钟名称
          _buildNameCard(),
          const SizedBox(height: 16),

          // 重复设置
          _buildRepeatCard(),
          const SizedBox(height: 16),

          // AI人设选择
          _buildPersonaCard(),
        ],
      ),
    );
  }

  Widget _buildTimePickerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '闹钟时间',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // 小时选择器
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: _selectedHour,
                      ),
                      itemExtent: 50,
                      onSelectedItemChanged: (index) async {
                        // iOS 系统原生滚轮音效（清脆齿轮声）
                        await HapticsService.instance.pickerSelection();
                        setState(() => _selectedHour = index);
                      },
                      children: List.generate(
                        24,
                        (index) => Center(
                          child: Text(
                            index.toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Text(':', style: TextStyle(fontSize: 24)),
                  // 分钟选择器
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: FixedExtentScrollController(
                        initialItem: _selectedMinute,
                      ),
                      itemExtent: 50,
                      onSelectedItemChanged: (index) async {
                        // iOS 系统原生滚轮音效（清脆齿轮声）
                        await HapticsService.instance.pickerSelection();
                        setState(() => _selectedMinute = index);
                      },
                      children: List.generate(
                        60,
                        (index) => Center(
                          child: Text(
                            index.toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '闹钟名称',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '给闹钟起个名字',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepeatCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '重复',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 快捷选项
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickRepeatChip('仅一次', []),
                _buildQuickRepeatChip('每天', [1, 2, 3, 4, 5, 6, 7]),
                _buildQuickRepeatChip('工作日', [1, 2, 3, 4, 5]),
                _buildQuickRepeatChip('周末', [6, 7]),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // 自定义星期选择
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (index) {
                final dayValue = index + 1;
                final isSelected = _selectedDays.contains(dayValue);

                return GestureDetector(
                  onTap: () async {
                    await HapticsService.instance.impact();
                    setState(() {
                      if (isSelected) {
                        _selectedDays.remove(dayValue);
                      } else {
                        _selectedDays.add(dayValue);
                      }
                    });
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300]!,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _dayLabels[index],
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRepeatChip(String label, List<int> days) {
    final isSelected =
        _selectedDays.toSet().toString() == days.toSet().toString();

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) async {
        await HapticsService.instance.selection();
        setState(() {
          _selectedDays = days.toSet();
        });
      },
    );
  }

  Widget _buildPersonaCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI人设',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_loadingPersonas)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (!_loadingPersonas)
              ..._personas.map((persona) {
              final isSelected = persona.id == _selectedPersonaId;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: Text(
                    persona.emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                  title: Text(
                    persona.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(persona.description),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: persona.features.map((feature) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              feature,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  onTap: () async {
                    await HapticsService.instance.impact();
                    setState(() {
                      _selectedPersonaId = persona.id;
                    });
                  },
                ),
              );
              }),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('管理人设库'),
                onPressed: () async {
                  await HapticsService.instance.selection();
                  if (!mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PersonaManagerScreen()),
                  );
                  await _loadPersonas();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAlarm() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入闹钟名称')));
      return;
    }

    final provider = context.read<AlarmProvider>();

    if (widget.alarm == null) {
      // 新建闹钟
      await provider.addAlarm(
        name: _nameController.text.trim(),
        hour: _selectedHour,
        minute: _selectedMinute,
        repeatDays: _selectedDays.toList()..sort(),
        aiPersonaId: _selectedPersonaId,
      );
    } else {
      // 更新闹钟
      final updated = widget.alarm!.copyWith(
        name: _nameController.text.trim(),
        hour: _selectedHour,
        minute: _selectedMinute,
        repeatDays: _selectedDays.toList()..sort(),
        aiPersonaId: _selectedPersonaId,
      );
      await provider.updateAlarm(updated);
    }

    await HapticsService.instance.impact();

    if (mounted) {
      Navigator.pop(context);
    }
  }
}
