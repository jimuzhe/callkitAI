import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_persona.dart';
import 'persona_api_service.dart';

/// Lightweight store for user-defined AI personas persisted in SharedPreferences.
/// Saved under the key 'custom_personas' as a JSON array of objects.
class PersonaStore {
  static final PersonaStore instance = PersonaStore._();
  PersonaStore._();

  static const String _prefsKey = 'custom_personas';
  final _api = PersonaApiService.instance;

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
    final remote = await _api.getAllPersonas();
    if (remote != null) {
      final remoteIds = remote.map((p) => p.id).toSet();
      final cached = await loadCustom();
      final unsynced = cached.where((p) => !remoteIds.contains(p.id)).toList();
      final remoteCustom = remote.where((p) => !p.isDefault).toList();
      await saveCustom([...remoteCustom, ...unsynced]);
      return [...remote, ...unsynced];
    }

    final custom = await loadCustom();
    return [...AIPersona.presets, ...custom];
  }

  Future<AIPersona?> getByIdMerged(String id) async {
    final remote = await _api.getPersona(id);
    if (remote != null) {
      return remote;
    }

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
    var synced = false;
    final updated = await _api.updatePersona(persona);
    if (updated) {
      synced = true;
    } else {
      final created = await _api.createPersona(persona);
      if (created != null) {
        synced = true;
      }
    }

    final list = await loadCustom();
    final idx = list.indexWhere((p) => p.id == persona.id);
    if (idx >= 0) {
      list[idx] = persona;
    } else {
      list.add(persona);
    }
    if (!synced) {
      await saveCustom(list);
      return;
    }
    await saveCustom(list.where((p) => !p.isDefault).toList());
  }

  Future<void> deleteById(String id) async {
    final remoteDeleted = await _api.deletePersona(id);
    final list = await loadCustom();
    list.removeWhere((p) => p.id == id);
    if (!remoteDeleted) {
      await saveCustom(list);
      return;
    }
    await saveCustom(list.where((p) => !p.isDefault).toList());
  }
}
