import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_persona.dart';
import 'api_config.dart';

class PersonaApiService {
  static final PersonaApiService instance = PersonaApiService._();
  PersonaApiService._();

  Future<String> get _baseUrl async => await ApiConfig.instance.getBaseUrl();

  Future<Uri> _buildUri(String path, [Map<String, dynamic>? query]) async {
    final baseUri = Uri.parse(await _baseUrl);
    final normalizedSegments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final combinedSegments = <String>[...
        baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      ...normalizedSegments,
    ];
    return baseUri.replace(
      pathSegments: combinedSegments,
      queryParameters: query?.map((key, value) => MapEntry(key, value?.toString() ?? '')),
    );
  }

  Future<List<AIPersona>?> getAllPersonas({bool activeOnly = true, String? search}) async {
    try {
      final uri = await _buildUri('/personas', {
        'active_only': activeOnly ? 'true' : 'false',
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      });
      final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final list = (data['data'] as List)
              .whereType<Map<String, dynamic>>()
              .map(AIPersona.fromApi)
              .toList();
          return list;
        }
      }
    } catch (e, s) {
      debugPrint('getAllPersonas failed: $e\n$s');
    }
    return null;
  }

  Future<AIPersona?> getPersona(String id) async {
    try {
      final uri = await _buildUri('/personas/$id');
      final response = await http.get(uri, headers: {'Content-Type': 'application/json'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] is Map<String, dynamic>) {
          return AIPersona.fromApi(data['data'] as Map<String, dynamic>);
        }
      }
    } catch (e, s) {
      debugPrint('getPersona failed: $e\n$s');
    }
    return null;
  }

  Future<String?> createPersona(AIPersona persona) async {
    try {
      final uri = await _buildUri('/personas');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(persona.toApiPayload()),
      );
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final payload = data['data'];
          if (payload is Map<String, dynamic> && payload['persona_id'] is String) {
            return payload['persona_id'] as String;
          }
          return persona.id;
        }
      }
    } catch (e, s) {
      debugPrint('createPersona failed: $e\n$s');
    }
    return null;
  }

  Future<bool> updatePersona(AIPersona persona) async {
    try {
      final uri = await _buildUri('/personas/${persona.id}');
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(persona.toApiPayload()),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e, s) {
      debugPrint('updatePersona failed: $e\n$s');
    }
    return false;
  }

  Future<bool> deletePersona(String id) async {
    try {
      final uri = await _buildUri('/personas/$id');
      final response = await http.delete(uri, headers: {'Content-Type': 'application/json'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e, s) {
      debugPrint('deletePersona failed: $e\n$s');
    }
    return false;
  }

  Future<bool> togglePersona(String id, bool isActive) async {
    try {
      final uri = await _buildUri('/personas/$id/toggle');
      final response = await http.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'is_active': isActive}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
    } catch (e, s) {
      debugPrint('togglePersona failed: $e\n$s');
    }
    return false;
  }
}
