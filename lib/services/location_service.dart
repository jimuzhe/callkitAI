// iOS专用位置服务
import 'location_service_mobile.dart';

export 'location_service_mobile.dart';

class LocationService {
  static Future<LocationResult?> getCurrentLocation() async {
    return getLocationMobile();
  }
}
