import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

class LocationResult {
  final double latitude;
  final double longitude;
  final String? cityName; // 可能为空

  LocationResult(this.latitude, this.longitude, {this.cityName});
}

Future<LocationResult?> getLocationMobile() async {
  try {
    // 检查定位权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    // 获取当前位置
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // 尝试本地反向地理编码以获取城市名（iOS/Android 均支持）
    String? city;
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        // 优先 locality，再用 subLocality 或 administrativeArea 做回退
        city = p.locality ?? p.subLocality ?? p.administrativeArea ?? p.name;
      }
    } catch (e) {
      // ignore: avoid_print
      print('反向地理编码失败: $e');
    }

    return LocationResult(
      position.latitude,
      position.longitude,
      cityName: city,
    );
  } catch (e) {
    print('获取位置失败: $e');
    return null;
  }
}

Future<LocationResult?> getLocationWeb() async {
  // Web 平台暂不支持
  return null;
}
