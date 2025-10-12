import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_persona.dart';
import '../services/persona_store.dart';
import '../services/haptics_service.dart';

class PersonaEditScreen extends StatefulWidget {
  final AIPersona? persona; // null => create
  const PersonaEditScreen({super.key, this.persona});

  @override
  State<PersonaEditScreen> createState() => _PersonaEditScreenState();
}

class _PersonaEditScreenState extends State<PersonaEditScreen> {
  late TextEditingController _name;
  late TextEditingController _emoji;
  late TextEditingController _desc;
  late TextEditingController _system;
  late TextEditingController _opening;
  late TextEditingController _voice;
  late TextEditingController _features;

  late bool _isEdit;
  late String _id;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.persona != null;
    _id = widget.persona?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _name = TextEditingController(text: widget.persona?.name ?? '自定义人设');
    _emoji = TextEditingController(text: widget.persona?.emoji ?? '🙂');
    _desc = TextEditingController(text: widget.persona?.description ?? '');
    _system = TextEditingController(text: widget.persona?.systemPrompt ?? '');
    _opening = TextEditingController(text: widget.persona?.openingLine ?? '');
    _voice = TextEditingController(text: widget.persona?.voiceId ?? '');
    _features = TextEditingController(text: widget.persona?.features.join(', ') ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _emoji.dispose();
    _desc.dispose();
    _system.dispose();
    _opening.dispose();
    _voice.dispose();
    _features.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入名称')));
      return;
    }
    if (_system.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入提示词/人设内容')));
      return;
    }

    await HapticsService.instance.impact();

    final features = _features.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final persona = AIPersona(
      id: _id,
      name: _name.text.trim(),
      description: _desc.text.trim(),
      emoji: _emoji.text.trim().isEmpty ? '🙂' : _emoji.text.trim(),
      systemPrompt: _system.text.trim(),
      openingLine: _opening.text.trim(),
      voiceId: _voice.text.trim(),
      features: features,
    );

    await PersonaStore.instance.addOrUpdate(persona);

    if (mounted) {
      Navigator.pop(context, persona);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存人设')));
    }
  }

  Future<void> _setAsDefault() async {
    await HapticsService.instance.selection();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_persona_id', _id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已设为默认人设')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑人设' : '新建人设'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
            tooltip: '保存',
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名称', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emoji,
                  decoration: const InputDecoration(labelText: 'Emoji', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _voice,
                  decoration: const InputDecoration(labelText: '音色ID(可选)', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: '描述(可选)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _system,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '提示词 / 人设内容',
              helperText: '支持占位符: {time}, {alarm}, {date}',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _opening,
            decoration: const InputDecoration(labelText: '开场白建议(可选)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _features,
            decoration: const InputDecoration(labelText: '标签(逗号分隔, 可选)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _setAsDefault,
            icon: const Icon(Icons.star_outline),
            label: const Text('设为默认人设'),
          ),
        ],
      ),
    );
  }
}
