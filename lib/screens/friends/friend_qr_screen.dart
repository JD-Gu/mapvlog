import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/friend_service.dart';
import '../../utils/constants.dart';

/// 친구 QR — 내 QR 표시 / 친구 QR 스캔 2탭
class FriendQrScreen extends StatefulWidget {
  const FriendQrScreen({super.key});

  @override
  State<FriendQrScreen> createState() => _FriendQrScreenState();
}

class _FriendQrScreenState extends State<FriendQrScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: const Text(
          'QR로 친구 추가',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code, size: 20), text: '내 QR'),
            Tab(
                icon: Icon(Icons.qr_code_scanner, size: 20),
                text: '친구 스캔'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _MyQrView(),
          _ScanQrView(),
        ],
      ),
    );
  }
}

// ─── 내 QR 표시 ──────────────────────────────────────────────────────────────

class _MyQrView extends StatelessWidget {
  const _MyQrView();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('로그인이 필요합니다'));
    }
    // QR 데이터 — JSON 구조 (uid + name + email)
    final qrData = jsonEncode({
      't': 'pinflick.friend',
      'uid': user.uid,
      'name': user.displayName ?? user.email ?? '사용자',
      if (user.email != null) 'email': user.email,
      if (user.photoURL != null) 'photo': user.photoURL,
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          const SizedBox(height: 16),
          const Text(
            '친구에게 보여주세요',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '상대가 스캔하면 자동으로 친구 요청이 전송됩니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          // QR 카드
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                // 아바타 + 이름
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [
                      Color(0xFF1A73E8),
                      Color(0xFF7C4DFF),
                      Color(0xFFEC407A),
                    ]),
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primary.withAlpha(30),
                    backgroundImage: user.photoURL != null
                        ? NetworkImage(user.photoURL!)
                        : null,
                    child: user.photoURL == null
                        ? Text(
                            (user.displayName ?? user.email ?? 'U')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                                fontSize: 26,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user.displayName ?? '사용자',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (user.email != null)
                  Text(
                    user.email!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 22),
                // QR
                QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  gapless: true,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  embeddedImage: const AssetImage(
                      'assets/images/Pinflick_icon.png'),
                  embeddedImageStyle: const QrEmbeddedImageStyle(
                    size: Size(38, 38),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'PinFlick 친구 QR 코드',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textDisabled,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── QR 스캔 ─────────────────────────────────────────────────────────────────

class _ScanQrView extends StatefulWidget {
  const _ScanQrView();

  @override
  State<_ScanQrView> createState() => _ScanQrViewState();
}

class _ScanQrViewState extends State<_ScanQrView> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _processing = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _processing = true;
    HapticFeedback.mediumImpact();
    await _scanner.stop();
    await _handleScannedData(value);
    _processing = false;
  }

  Future<void> _handleScannedData(String raw) async {
    try {
      // JSON 파싱
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['t'] != 'pinflick.friend') {
        throw Exception('PinFlick QR 코드가 아닙니다');
      }
      final uid = data['uid'] as String?;
      final name = data['name'] as String? ?? '사용자';
      final email = data['email'] as String?;
      final photo = data['photo'] as String?;
      if (uid == null || uid.isEmpty) {
        throw Exception('잘못된 QR 코드');
      }

      // 본인 검사
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == myUid) {
        throw Exception('본인 QR 코드입니다');
      }

      if (!mounted) return;

      // 확인 다이얼로그
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textDisabled.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [
                      Color(0xFF1A73E8),
                      Color(0xFF7C4DFF),
                      Color(0xFFEC407A),
                    ]),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.primary.withAlpha(30),
                    backgroundImage:
                        photo != null ? NetworkImage(photo) : null,
                    child: photo == null
                        ? Text(
                            name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 30,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Text(name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    )),
                if (email != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        )),
                  ),
                const SizedBox(height: 18),
                const Text(
                  '이 사용자에게 친구 요청을 보낼까요?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetCtx, false),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                              color: AppColors.textDisabled
                                  .withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppRadius.full)),
                        ),
                        child: const Text('취소',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(sheetCtx, true),
                        icon: const Icon(Icons.person_add, size: 18),
                        label: const Text('친구 요청'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppRadius.full)),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (confirmed == true && mounted) {
        await FriendService.sendRequest(
          toUid: uid,
          toName: name,
          toPhotoUrl: photo,
          toEmail: email,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✉️ $name님에게 요청을 보냈습니다'),
              backgroundColor: AppColors.secondary,
              duration: const Duration(seconds: 2),
            ),
          );
          Navigator.pop(context); // QR 화면 닫기
        }
        return;
      }

      // 취소되면 스캐너 재시작
      if (mounted) await _scanner.start();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 2),
          ),
        );
        await _scanner.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
        ),
        // 가이드 프레임 (사각형)
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.primary,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(20),
              color: Colors.transparent,
            ),
          ),
        ),
        // 안내 텍스트
        Positioned(
          top: 32,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(160),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: const Text(
                '친구의 QR 코드를 프레임 안에 비춰주세요',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        // 손전등/카메라 토글
        Positioned(
          bottom: 28,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ScanIconButton(
                icon: Icons.flashlight_on,
                onTap: () => _scanner.toggleTorch(),
                tooltip: '플래시',
              ),
              const SizedBox(width: 16),
              _ScanIconButton(
                icon: Icons.cameraswitch,
                onTap: () => _scanner.switchCamera(),
                tooltip: '카메라 전환',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScanIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _ScanIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        elevation: 6,
        shape: const CircleBorder(),
        color: Theme.of(context).colorScheme.surface,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
        ),
      ),
    );
  }
}
