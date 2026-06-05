import 'package:geolocator/geolocator.dart';
import 'package:geolocator_android/geolocator_android.dart';

/// Android: 포그라운드 서비스(상시 알림)로 백그라운드 위치 스트림 유지.
/// 앱을 닫아도 위치 업데이트가 흐르게 하되, **시간 기준 5분 고정**(이동과 무관)으로
/// 배터리 절약. (distanceFilter:0 → 거리 필터 없이 주기마다 갱신)
LocationSettings bgLocationSettings() => AndroidSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: 0, // 거리 필터 없음
      intervalDuration: const Duration(minutes: 5), // 5분 고정
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'PinFlick 위치 공유 중',
        notificationText: '친구에게 내 위치를 공유하고 있어요. 끄려면 앱에서 해제하세요.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
