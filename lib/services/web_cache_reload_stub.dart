// 비웹 플랫폼용 stub — Android/iOS 에서는 io 구현이 대신 사용됨
import '../models/remote_version.dart';

Future<String?> fetchRemoteBuildNumber() async => null;
Future<RemoteVersion?> fetchRemoteVersion() async => null;
void hardReload() {}
