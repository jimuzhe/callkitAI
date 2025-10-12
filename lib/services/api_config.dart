import 'package:shared_preferences/shared_preferences.dart';

/// API配置管理
class ApiConfig {
  static final ApiConfig instance = ApiConfig._();
  ApiConfig._();

  static const String _keyApiEnabled = 'api_enabled';
  static const String _keyApiBaseUrl = 'api_base_url';
  static const String _keyUserId = 'user_id';

  // 默认配置
  static const String defaultBaseUrl = 'https://alarm.name666.top/api';
  static const String defaultUserId = 'user_001';

  /// 是否启用API
  Future<bool> isApiEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyApiEnabled) ?? true;
  }

  /// 设置是否启用API
  Future<void> setApiEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyApiEnabled, enabled);
  }

  /// 获取API基础URL
  Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiBaseUrl) ?? defaultBaseUrl;
  }

  /// 设置API基础URL
  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiBaseUrl, url);
  }

  /// 获取用户ID
  Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId) ?? defaultUserId;
  }

  /// 设置用户ID
  Future<void> setUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserId, userId);
  }

  /// 重置为默认配置
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyApiEnabled, true);
    await prefs.setString(_keyApiBaseUrl, defaultBaseUrl);
    await prefs.setString(_keyUserId, defaultUserId);
  }
}
