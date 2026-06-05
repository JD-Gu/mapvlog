import 'package:geolocator/geolocator.dart';

/// 웹/비-Android: 포그라운드 알림 없이 기본 LocationSettings.
/// (웹에서는 백그라운드 위치 자체를 쓰지 않으므로 실제 호출되지 않음)
LocationSettings bgLocationSettings() => const LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 100,
    );
