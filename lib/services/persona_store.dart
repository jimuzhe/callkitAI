import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_persona.dart';

/// Lightweight store for user-defined AI personas persisted in SharedPreferences.
/// Saved under the key 'custom_personas' as a JSON array of objects.
class PersonaStore {
  static final PersonaStore instance = PersonaStore._();
  PersonaStore._();

  static const String _prefsKey = 'custom_personas';

  Future<List<AIPersona>> loadCustom() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return <AIPersona>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((m) => AIPersona.fromMap(m))
          .toList(growable: true);
    } catch (_) {
      return <AIPersona>[];
    }
  }

  Future<void> saveCustom(List<AIPersona> personas) async {
    final prefs = await SharedPreferences.getInstance();
    final list = personas.map((p) => p.toMap()).toList(growable: false);
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  Future<List<AIPersona>> getAllMerged() async {
    final custom = await loadCustom();
    // Presets first or custom first is a UX choice. We'll show presets first.
    return [...AIPersona.presets, ...custom];
  }

  Future<AIPersona?> getByIdMerged(String id) async {
    final custom = await loadCustom();
    final foundCustom = custom.where((p) => p.id == id).toList();
    if (foundCustom.isNotEmpty) return foundCustom.first;
    try {
      return AIPersona.getById(id);
    } catch (_) {
      return null;
    }
  }

  Future<void> addOrUpdate(AIPersona persona) async {
    final list = await loadCustom();
    final idx = list.indexWhere((p) => p.id == persona.id);
    if (idx >= 0) {
      list[idx] = persona;
    } else {
      list.add(persona);
    }
    await saveCustom(list);
  }

  Future<void> deleteById(String id) async {
    final list = await loadCustom();
    list.removeWhere((p) => p.id == id);
    await saveCustom(list);
  }
}
