import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/friend_service.dart';
import '../../utils/constants.dart';
import 'friend_qr_screen.dart';

/// 이메일로 친구 검색 + 요청 보내기
class FriendSearchScreen extends StatefulWidget {
  const FriendSearchScreen({super.key});

  @override
  State<FriendSearchScreen> createState() => _FriendSearchScreenState();
}

class _FriendSearchScreenState extends State<FriendSearchScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  Map<String, dynamic>? _result; // 검색 결과 사용자
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final email = _ctrl.text.trim();
    if (email.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _searched = true;
    });
    try {
      final user = await FriendService.findUserByEmail(email);
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _error = '해당 이메일의 사용자를 찾지 못했습니다';
          _loading = false;
        });
        return;
      }
      // 자기 자신 검색 차단
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (user['uid'] == myUid) {
        setState(() {
          _error = '본인은 친구로 추가할 수 없습니다';
          _loading = false;
        });
        return;
      }
      setState(() {
        _result = user;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '검색 실패: $e';
        _loading = false;
      });
    }
  }

  Future<void> _sendRequest() async {
    final u = _result;
    if (u == null) return;
    HapticFeedback.mediumImpact();
    try {
      await FriendService.sendRequest(
        toUid: u['uid'] as String,
        toName: u['displayName'] as String? ?? '사용자',
        toPhotoUrl: u['photoURL'] as String? ?? u['photoUrl'] as String?,
        toEmail: u['email'] as String?,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✉️ ${u['displayName'] ?? '사용자'}님에게 요청을 보냈습니다'),
          backgroundColor: AppColors.secondary,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: const Text(
          '친구 추가',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner,
                color: AppColors.primary),
            tooltip: 'QR 코드',
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FriendQrScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 검색바
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '이메일 주소 입력 (예: friend@example.com)',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward,
                            color: AppColors.primary),
                        onPressed: _search,
                      ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: AppColors.primary, width: 1.5),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          // 결과
          Expanded(
            child: _loading
                ? const SizedBox.shrink()
                : _error != null
                    ? _ErrorView(message: _error!)
                    : _result != null
                        ? _ResultView(
                            user: _result!, onSend: _sendRequest)
                        : !_searched
                            ? const _HintView()
                            : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _HintView extends StatelessWidget {
  const _HintView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              child: const Icon(Icons.alternate_email,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text(
              '친구의 이메일로 검색해보세요',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '검색 후 친구 요청을 보내면\n상대가 수락해야 친구가 됩니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.error.withValues(alpha: 0.08),
              ),
              child: const Icon(Icons.search_off,
                  size: 38, color: AppColors.error),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onSend;
  const _ResultView({required this.user, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final displayName = user['displayName'] as String? ?? '사용자';
    final email = user['email'] as String? ?? '';
    final photoUrl =
        (user['photoURL'] ?? user['photoUrl']) as String?;
    const palette = [
      Color(0xFF1A73E8),
      Color(0xFF34A853),
      Color(0xFFFF6B6B),
      Color(0xFF7C4DFF),
      Color(0xFFFFA726),
      Color(0xFF00ACC1),
      Color(0xFFEC407A),
    ];
    final color = palette[displayName.hashCode.abs() % palette.length];

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadow.card,
        ),
        child: Column(
          children: [
            // 아바타
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: photoUrl == null || photoUrl.isEmpty
                    ? LinearGradient(
                        colors: [
                          color,
                          Color.lerp(color, Colors.black, 0.25) ?? color,
                        ],
                      )
                    : null,
                image: photoUrl != null && photoUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(photoUrl), fit: BoxFit.cover)
                    : null,
              ),
              alignment: Alignment.center,
              child: photoUrl == null || photoUrl.isEmpty
                  ? Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold),
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            Text(
              displayName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              email,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('친구 요청 보내기',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.full)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
