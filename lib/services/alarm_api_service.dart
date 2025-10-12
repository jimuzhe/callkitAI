import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/alarm.dart';
import 'api_config.dart';

/// 闹钟API服务 - 与Python后端交互
class AlarmApiService {
  static final AlarmApiService instance = AlarmApiService._();
  AlarmApiService._();

  // 动态获取API配置
  Future<String> get _baseUrl async => await ApiConfig.instance.getBaseUrl();
  Future<String> get _userId async => await ApiConfig.instance.getUserId();
  final http.Client _client = http.Client();
  Duration requestTimeout = const Duration(seconds: 20);

  Future<T?> _guardRequest<T>(Future<T> future) async {
    try {
      return await future.timeout(requestTimeout);
    } on TimeoutException catch (e) {
      debugPrint('AlarmApiService timeout: $e');
      return null;
    } catch (e) {
      debugPrint('AlarmApiService error: $e');
      rethrow;
    }
  }

  Future<http.Response?> _get(Uri uri) => _guardRequest(_client.get(uri, headers: _jsonHeaders));
  Future<http.Response?> _post(Uri uri, {Object? body}) =>
      _guardRequest(_client.post(uri, headers: _jsonHeaders, body: body));
  Future<http.Response?> _put(Uri uri, {Object? body}) =>
      _guardRequest(_client.put(uri, headers: _jsonHeaders, body: body));
  Future<http.Response?> _delete(Uri uri) =>
      _guardRequest(_client.delete(uri, headers: _jsonHeaders));
  Future<http.Response?> _patch(Uri uri, {Object? body}) =>
      _guardRequest(_client.patch(uri, headers: _jsonHeaders, body: body));

  Map<String, String> get _jsonHeaders => {'Content-Type': 'application/json'};

  /// 获取所有闹钟
  Future<List<Alarm>> getAllAlarms() async {
    try {
      final baseUrl = await _baseUrl;
      final userId = await _userId;
      final response = await _get(Uri.parse('$baseUrl/alarms?user_id=$userId'));
      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final List<dynamic> alarmsData = data['data'];
          return alarmsData.map((json) => _alarmFromApiJson(json)).toList();
        }
      }
      return [];
    } catch (e) {
      print('获取闹钟列表失败: $e');
      return [];
    }
  }

  /// 获取单个闹钟
  Future<Alarm?> getAlarmById(String id) async {
    try {
      final baseUrl = await _baseUrl;
      final response = await _get(Uri.parse('$baseUrl/alarms/$id'));
      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return _alarmFromApiJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      print('获取闹钟失败: $e');
      return null;
    }
  }

  /// 创建闹钟
  Future<String?> createAlarm(Alarm alarm) async {
    try {
      final body = await _alarmToApiJson(alarm);
      final baseUrl = await _baseUrl;
      
      final response = await _post(
        Uri.parse('$baseUrl/alarms'),
        body: jsonEncode(body),
      );

      if (response != null && response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return alarm.id; // 返回闹钟ID
        }
      }
      return null;
    } catch (e) {
      print('创建闹钟失败: $e');
      return null;
    }
  }

  /// 更新闹钟
  Future<bool> updateAlarm(Alarm alarm) async {
    try {
      final body = await _alarmToApiJson(alarm);
      final baseUrl = await _baseUrl;
      
      final response = await _put(
        Uri.parse('$baseUrl/alarms/${alarm.id}'),
        body: jsonEncode(body),
      );

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('更新闹钟失败: $e');
      return false;
    }
  }

  /// 删除闹钟
  Future<bool> deleteAlarm(String id) async {
    try {
      final baseUrl = await _baseUrl;
      final response = await _delete(Uri.parse('$baseUrl/alarms/$id'));
      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('删除闹钟失败: $e');
      return false;
    }
  }

  /// 切换闹钟状态
  Future<bool> toggleAlarm(String id, bool enabled) async {
    try {
      final baseUrl = await _baseUrl;
      final response = await _patch(
        Uri.parse('$baseUrl/alarms/$id/toggle'),
        body: jsonEncode({'is_enabled': enabled}),
      );

      if (response != null && response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('切换闹钟状态失败: $e');
      return false;
    }
  }

  /// 将API返回的JSON转换为Alarm对象
  Alarm _alarmFromApiJson(Map<String, dynamic> json) {
    // 解析时间字符串 "HH:MM"
    final timeParts = (json['alarm_time'] as String).split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);

    // 解析重复日期 "1,2,3,4,5"
    final repeatDaysStr = json['repeat_days'] as String?;
    final repeatDays = repeatDaysStr != null && repeatDaysStr.isNotEmpty
        ? repeatDaysStr.split(',').map((e) => int.parse(e)).toList()
        : <int>[];

    return Alarm(
      id: json['alarm_id'] as String,
      name: json['alarm_name'] as String? ?? '闹钟',
      hour: hour,
      minute: minute,
      isEnabled: json['is_enabled'] == true || json['is_enabled'] == 1,
      repeatDays: repeatDays,
      aiPersonaId: json['ai_persona_id'] as String? ?? 'gentle',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      nextAlarmTime: json['next_alarm_time'] != null
          ? DateTime.parse(json['next_alarm_time'] as String)
          : null,
    );
  }

  /// 将Alarm对象转换为API所需的JSON格式
  Future<Map<String, dynamic>> _alarmToApiJson(Alarm alarm) async {
    final userId = await _userId;
    return {
      'alarm_id': alarm.id,
      'user_id': userId,
      'alarm_time': alarm.getFormattedTime(),
      'alarm_name': alarm.name,
      'ai_persona_id': alarm.aiPersonaId,
      'repeat_days': alarm.repeatDays.join(','),
      'is_enabled': alarm.isEnabled,
      'next_alarm_time': alarm.nextAlarmTime?.toIso8601String(),
    };
  }

  /// 健康检查
  Future<bool> checkHealth() async {
    try {
      final baseUrl = await _baseUrl;
      final healthUri = Uri.parse(baseUrl).resolve('/health');
      final response = await _get(healthUri);
      return response != null && response.statusCode == 200;
    } catch (e) {
      print('健康检查失败: $e');
      return false;
    }
  }
}
