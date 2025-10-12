import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WeatherService {
  static const String _apiKeyPref = 'weather_api_key';
  static const String _apiHostPref = 'weather_api_host';
  static const String _locationPref = 'weather_location';
  static const String _locationNamePref = 'weather_location_name';

  // 默认位置 (北京)
  static const String _defaultLocation = '101010100';
  // 系统预设的和风天气配置
  static const String _defaultApiHost = 'm23v59af3y.re.qweatherapi.com';
  static const String _defaultApiKey = '529759f0a03f4fb8a713eae4848ea4c9';

  static WeatherService? _instance;
  static WeatherService get instance {
    _instance ??= WeatherService._();
    return _instance!;
  }

  WeatherService._();

  // 简单内存缓存，减少频繁请求 & 提供失败时的回退
  WeatherNow? _cachedNow;
  DateTime? _cachedAt;
  // 默认缓存 20 分钟
  final Duration _cacheTtl = const Duration(minutes: 20);

  Future<bool> hasValidConfig() async {
    final apiKey = await getApiKey();
    final apiHost = await getApiHost();
    return apiKey != null &&
        apiKey.isNotEmpty &&
        apiHost != null &&
        apiHost.isNotEmpty;
  }

  /// 对配置做一次探测：调用默认城市天气接口，确认 Host/Key 是否可用。
  Future<bool> probeConfig() async {
    try {
      final apiKey = await getApiKey();
      final apiHost = await getApiHost();
      if (apiKey == null ||
          apiKey.isEmpty ||
          apiHost == null ||
          apiHost.isEmpty) {
        return false;
      }

      final host = _resolveWeatherHost(apiHost);
      final uri = Uri.https(host, _resolveWeatherPath(host), {
        'location': _defaultLocation,
        if (!_isJwtKey(apiKey)) 'key': apiKey,
      });
      final response = await http.get(uri, headers: _buildAuthHeaders(apiKey));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['code'] == '200';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  WeatherNow? getCachedNow() {
    if (_cachedNow == null || _cachedAt == null) return null;
    if (DateTime.now().difference(_cachedAt!) <= _cacheTtl) {
      return _cachedNow;
    }
    return null;
  }

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_apiKeyPref);
    if (val == null || val.isEmpty) {
      await prefs.setString(_apiKeyPref, _defaultApiKey);
      return _defaultApiKey;
    }
    return val;
  }

  Future<void> setApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyPref, apiKey);
  }

  Future<String?> getApiHost() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_apiHostPref);
    if (val == null || val.isEmpty) {
      await prefs.setString(_apiHostPref, _defaultApiHost);
      return _defaultApiHost;
    }
    return val;
  }

  Future<void> setApiHost(String apiHost) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiHostPref, apiHost);
  }

  Future<String> getLocation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_locationPref) ?? _defaultLocation;
  }

  Future<void> setLocation(String location, String locationName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_locationPref, location);
    await prefs.setString(_locationNamePref, locationName);
  }

  /// 统一解析并设置 location 用于天气 API。
  ///
  /// 说明：weather API 的 location 参数支持两种格式：
  /// - LocationID（例如 101010100），可以通过 Geo API (/geo/v2/city/lookup) 获取
  /// - 经纬度字符串，格式为 "lon,lat"（十进制且最多小数点后两位），例如 "116.41,39.92"
  ///
  /// 优先使用经纬度（lat, lon）分两步处理：
  /// 1) 使用 geo API 查询以获取可读的城市名（用于 UI 显示）
  /// 2) 将保存的 location 设置为经度,纬度（lon,lat，保留两位小数）以传入天气 API
  ///
  /// 否则若提供了 cityName，则使用 geo API (/geo/v2/city/lookup) 搜索城市并保存其 LocationID（city.id）与可读名称。
  /// 若都未成功，则返回当前已保存的 location（可能是默认值）。
  Future<String> resolveLocation({
    double? lat,
    double? lon,
    String? cityName,
  }) async {
    // 1) GPS 路径：优先保存为 lon,lat（两位小数），但也尝试通过 geo API 获取城市名用于 UI 显示
    if (lat != null && lon != null) {
      final city = await getCityByLocation(lat, lon);
      final coords = '${lon.toStringAsFixed(2)},${lat.toStringAsFixed(2)}';
      final name = city != null ? city.fullName : '';
      await setLocation(coords, name);
      return coords;
    }

    // 2) 城市名路径：使用 geo API 查找 city id 并保存 city.id
    if (cityName != null && cityName.trim().isNotEmpty) {
      final city = await getCityByName(cityName.trim());
      if (city != null && city.id.isNotEmpty) {
        await setLocation(city.id, city.fullName);
        return city.id;
      }
    }

    // 3) 回退：返回已保存的 location
    return await getLocation();
  }

  /// 根据城市名调用 Geo API 搜索城市并返回 CityInfo（使用 /v2/city/lookup 或 /geo/v2/city/lookup）
  Future<CityInfo?> getCityByName(String name) async {
    try {
      final apiKey = await getApiKey();
      final apiHost = await getApiHost();
      if (apiKey == null ||
          apiKey.isEmpty ||
          apiHost == null ||
          apiHost.isEmpty) {
        return null;
      }

      final host = _resolveCityHost(apiHost);
      final query = {'location': name, if (!_isJwtKey(apiKey)) 'key': apiKey};
      final uri = Uri.https(host, _resolveCityPath(host), query);
      final response = await http.get(uri, headers: _buildAuthHeaders(apiKey));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == '200' &&
            data['location'] != null &&
            data['location'].isNotEmpty) {
          return CityInfo.fromJson(data['location'][0]);
        }
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('按名称查询城市失败: $e');
      return null;
    }
  }

  /// 获取当前保存的 location 名称（可用于 UI 显示），若未设置返回空串。
  Future<String> getLocationName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_locationNamePref) ?? '';
  }

  /// 根据经纬度查询城市信息
  Future<CityInfo?> getCityByLocation(double lat, double lon) async {
    try {
      final apiKey = await getApiKey();
      final apiHost = await getApiHost();
      if (apiKey == null ||
          apiKey.isEmpty ||
          apiHost == null ||
          apiHost.isEmpty) {
        return null;
      }

      final host = _resolveCityHost(apiHost);
      final locationParam =
          '${lon.toStringAsFixed(2)},${lat.toStringAsFixed(2)}';
      final query = {
        'location': locationParam,
        if (!_isJwtKey(apiKey)) 'key': apiKey,
      };
      final uri = Uri.https(host, _resolveCityPath(host), query);
      final response = await http.get(uri, headers: _buildAuthHeaders(apiKey));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == '200' &&
            data['location'] != null &&
            data['location'].isNotEmpty) {
          return CityInfo.fromJson(data['location'][0]);
        }
        // ignore: avoid_print
        print(
          'City lookup response code: ${data['code']} body: ${response.body}',
        );
      }
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('查询城市失败: $e');
      return null;
    }
  }

  /// 尝试使用城市名称直接作为 location 参数查询天气。
  /// 如果查询成功（服务返回 code == '200'），则把该名称保存为当前 location 并返回 true。
  Future<bool> trySetLocationFromCityName(String cityName) async {
    // 使用 Geo API 搜索城市名称并保存 city.id（推荐）
    try {
      final city = await getCityByName(cityName);
      if (city != null && city.id.isNotEmpty) {
        await setLocation(city.id, city.fullName);
        return true;
      }
      return false;
    } catch (e) {
      // ignore: avoid_print
      print('尝试使用城市名通过 Geo API 查询失败: $e');
      return false;
    }
  }

  /// 获取实时天气
  Future<WeatherNow?> getNowWeather({bool allowCache = true}) async {
    try {
      if (allowCache) {
        final cached = getCachedNow();
        if (cached != null) return cached;
      }

      final apiKey = await getApiKey();
      final apiHost = await getApiHost();
      if (apiKey == null ||
          apiKey.isEmpty ||
          apiHost == null ||
          apiHost.isEmpty) {
        return getCachedNow();
      }

      final location = await getLocation();
      final host = _resolveWeatherHost(apiHost);
      final query = {
        'location': location,
        if (!_isJwtKey(apiKey)) 'key': apiKey,
      };
      final uri = Uri.https(host, _resolveWeatherPath(host), query);
      final response = await http.get(uri, headers: _buildAuthHeaders(apiKey));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == '200') {
          final now = WeatherNow.fromJson(data['now']);
          _cachedNow = now;
          _cachedAt = DateTime.now();
          return now;
        }
        // ignore: avoid_print
        print(
          'Weather now response code: ${data['code']} body: ${response.body}',
        );
      }
      return getCachedNow();
    } catch (e) {
      // ignore: avoid_print
      print('获取天气失败: $e');
      return getCachedNow();
    }
  }

  String _resolveCityHost(String apiHost) {
    final normalized = _normalizeHost(apiHost);
    final lower = normalized.toLowerCase();
    if (lower.endsWith('.re.qweatherapi.com')) return normalized;
    if (lower.contains('qweather.com')) return 'geoapi.qweather.com';
    return normalized;
  }

  String _resolveCityPath(String host) {
    final lower = host.toLowerCase();
    if (lower.contains('qweather.com')) {
      return '/v2/city/lookup';
    }
    return '/geo/v2/city/lookup';
  }

  String _resolveWeatherHost(String apiHost) {
    final normalized = _normalizeHost(apiHost);
    final lower = normalized.toLowerCase();
    if (lower.endsWith('.re.qweatherapi.com')) return normalized;
    if (lower.contains('qweather.com')) return 'api.qweather.com';
    return normalized;
  }

  String _resolveWeatherPath(String host) {
    // 和风天气统一使用 /v7/weather/now
    return '/v7/weather/now';
  }

  Map<String, String> _buildAuthHeaders(String apiKey) {
    if (_isJwtKey(apiKey)) {
      return {'Authorization': 'Bearer $apiKey'};
    }
    return <String, String>{};
  }

  bool _isJwtKey(String apiKey) {
    if (apiKey.isEmpty) return false;
    final parts = apiKey.split('.');
    return parts.length == 3 && parts.every((part) => part.isNotEmpty);
  }

  String _normalizeHost(String apiHost) {
    var host = apiHost.trim();
    if (host.startsWith('https://')) {
      host = host.substring(8);
    } else if (host.startsWith('http://')) {
      host = host.substring(7);
    }
    final slashIndex = host.indexOf('/');
    if (slashIndex != -1) {
      host = host.substring(0, slashIndex);
    }
    return host.replaceAll(RegExp(r'/+$'), '');
  }
}

class CityInfo {
  final String id; // 城市ID
  final String name; // 城市名称
  final String adm1; // 省份
  final String adm2; // 城市
  final String country; // 国家

  CityInfo({
    required this.id,
    required this.name,
    required this.adm1,
    required this.adm2,
    required this.country,
  });

  factory CityInfo.fromJson(Map<String, dynamic> json) {
    return CityInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      adm1: json['adm1'] ?? '',
      adm2: json['adm2'] ?? '',
      country: json['country'] ?? '',
    );
  }

  String get fullName {
    if (adm1 == adm2) {
      return '$adm1 $name';
    }
    return '$adm1 $adm2 $name';
  }
}

class WeatherNow {
  final String temp; // 温度
  final String feelsLike; // 体感温度
  final String icon; // 天气图标代码
  final String text; // 天气状况文字
  final String windDir; // 风向
  final String windScale; // 风力等级
  final String windSpeed; // 风速,单位:公里/小时
  final String humidity; // 相对湿度,百分比
  final String precip; // 当前小时累计降水量,单位:毫米
  final String pressure; // 大气压强,单位:百帕
  final String vis; // 能见度,单位:公里
  final String cloud; // 云量,百分比
  final String dew; // 露点温度

  WeatherNow({
    required this.temp,
    required this.feelsLike,
    required this.icon,
    required this.text,
    required this.windDir,
    required this.windScale,
    required this.windSpeed,
    required this.humidity,
    required this.precip,
    required this.pressure,
    required this.vis,
    required this.cloud,
    required this.dew,
  });

  factory WeatherNow.fromJson(Map<String, dynamic> json) {
    return WeatherNow(
      temp: json['temp'] ?? '0',
      feelsLike: json['feelsLike'] ?? '0',
      icon: json['icon'] ?? '100',
      text: json['text'] ?? '未知',
      windDir: json['windDir'] ?? '未知',
      windScale: json['windScale'] ?? '0',
      windSpeed: json['windSpeed'] ?? '0',
      humidity: json['humidity'] ?? '0',
      precip: json['precip'] ?? '0.0',
      pressure: json['pressure'] ?? '0',
      vis: json['vis'] ?? '0',
      cloud: json['cloud'] ?? '0',
      dew: json['dew'] ?? '0',
    );
  }

  // 获取天气图标URL
  String getIconUrl() {
    return 'https://cdn.qweather.com/img/h/$icon.png';
  }
}
