import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/constants.dart';

/// 지도 레이어 전환(지도/위성/하이브리드) + 스트리트뷰 버튼
///
/// 사용 예:
/// ```dart
/// Positioned(
///   right: 12, bottom: 60,
///   child: MapControls(
///     mapType: _mapType,
///     onMapTypeChanged: (t) => setState(() => _mapType = t),
///     center: _mapCenter,
///   ),
/// )
/// ```
class MapControls extends StatefulWidget {
  final MapType mapType;
  final ValueChanged<MapType> onMapTypeChanged;
  final LatLng? center; // 스트리트뷰 기준 좌표

  const MapControls({
    super.key,
    required this.mapType,
    required this.onMapTypeChanged,
    this.center,
  });

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls>
    with SingleTickerProviderStateMixin {
  bool _panelOpen = false;
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _anim, curve: Curves.easeOut);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _togglePanel() {
    setState(() => _panelOpen = !_panelOpen);
    _panelOpen ? _anim.forward() : _anim.reverse();
  }

  Future<void> _openStreetView() async {
    final c = widget.center;
    if (c == null) return;
    final uri = Uri.parse(
      'https://maps.google.com/?cbll=${c.latitude},${c.longitude}&layer=c',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── 레이어 선택 패널 ─────────────────────────────────────────────
        FadeTransition(
          opacity: _fade,
          child: _panelOpen
              ? Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppShadow.card,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TypeTile(
                        icon: Icons.map_outlined,
                        label: '기본지도',
                        selected: widget.mapType == MapType.normal,
                        onTap: () {
                          widget.onMapTypeChanged(MapType.normal);
                          _togglePanel();
                        },
                      ),
                      const Divider(height: 1, indent: 12, endIndent: 12),
                      _TypeTile(
                        icon: Icons.satellite_alt,
                        label: '위성',
                        selected: widget.mapType == MapType.satellite,
                        onTap: () {
                          widget.onMapTypeChanged(MapType.satellite);
                          _togglePanel();
                        },
                      ),
                      const Divider(height: 1, indent: 12, endIndent: 12),
                      _TypeTile(
                        icon: Icons.layers,
                        label: '하이브리드',
                        selected: widget.mapType == MapType.hybrid,
                        onTap: () {
                          widget.onMapTypeChanged(MapType.hybrid);
                          _togglePanel();
                        },
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // ── 레이어 토글 버튼 ─────────────────────────────────────────────
        _MapBtn(
          icon: Icons.layers,
          active: _panelOpen,
          tooltip: '지도 레이어',
          onTap: _togglePanel,
        ),
        const SizedBox(height: 8),

        // ── 스트리트뷰 버튼 ──────────────────────────────────────────────
        _MapBtn(
          icon: Icons.streetview,
          tooltip: '스트리트뷰',
          onTap: _openStreetView,
        ),
      ],
    );
  }
}

// ─── 내부 서브 위젯 ────────────────────────────────────────────────────────────

class _TypeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                color:
                    selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check, size: 14, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _MapBtn({
    required this.icon,
    this.active = false,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.white,
            shape: BoxShape.circle,
            boxShadow: AppShadow.card,
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
