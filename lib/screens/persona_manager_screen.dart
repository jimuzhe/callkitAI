import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_persona.dart';
import '../services/persona_store.dart';
import '../services/haptics_service.dart';
import 'persona_edit_screen.dart';

class PersonaManagerScreen extends StatefulWidget {
  const PersonaManagerScreen({super.key});

  @override
  State<PersonaManagerScreen> createState() => _PersonaManagerScreenState();
}

class _PersonaManagerScreenState extends State<PersonaManagerScreen> {
  late Future<void> _loadFuture;
  List<AIPersona> _merged = [];
  Set<String> _customIds = {};
  String? _defaultId;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _defaultId = prefs.getString('default_persona_id');
    final all = await PersonaStore.instance.getAllMerged();
    final custom = await PersonaStore.instance.loadCustom();
    _merged = all;
    _customIds = custom.map((e) => e.id).toSet();
    if (mounted) setState(() {});
  }

  bool _isCustom(String id) => _customIds.contains(id);

  Future<void> _setDefault(String id) async {
    await HapticsService.instance.selection();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_persona_id', id);
    setState(() => _defaultId = id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已设为默认人设')));
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除人设'),
        content: const Text('确定要删除这个自定义人设吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await PersonaStore.instance.deleteById(id);
    await _load();
  }

  Future<void> _openEditor({AIPersona? persona}) async {
    final res = await Navigator.push<AIPersona>(
      context,
      MaterialPageRoute(builder: (_) => PersonaEditScreen(persona: persona)),
    );
    if (res != null) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI人设库'),
        actions: [
          IconButton(
            tooltip: '新增人设',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, _) {
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: _merged.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = _merged[index];
              final isDefault = p.id == _defaultId;
              final custom = _isCustom(p.id);
              return Card(
                child: ListTile(
                  leading: Text(p.emoji, style: const TextStyle(fontSize: 28)),
                  title: Row(
                    children: [
                      Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                      if (isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('默认', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p.description.isNotEmpty) Text(p.description),
                      if (p.voiceId.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('音色: ${p.voiceId}', style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  onTap: () => _setDefault(p.id),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        tooltip: '设为默认',
                        icon: const Icon(Icons.star_border),
                        onPressed: () => _setDefault(p.id),
                      ),
                      IconButton(
                        tooltip: custom ? '编辑' : '仅内置可查看',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: custom ? () => _openEditor(persona: p) : null,
                      ),
                      IconButton(
                        tooltip: custom ? '删除' : '内置不可删',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: custom ? () => _delete(p.id) : null,
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
