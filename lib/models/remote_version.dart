/// /version.json 의 원격 버전 메타데이터
class RemoteVersion {
  final String version;
  final String build;
  final String? notes; // 업데이트 내역 (선택)

  const RemoteVersion({
    required this.version,
    required this.build,
    this.notes,
  });

  static RemoteVersion? fromJson(Map<String, dynamic> j) {
    final build = j['build']?.toString();
    if (build == null) return null;
    return RemoteVersion(
      version: j['version']?.toString() ?? '',
      build: build,
      notes: j['notes']?.toString(),
    );
  }
}
