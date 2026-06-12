// lib/features/head_pose/head_pose_screen.dart
//
// ✅ محدث: ConsumerStatefulWidget + MQTT مربوط + UI واضح

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/mqtt_provider.dart';
import 'head_pose_tracker.dart';
import 'head_pose_command_bridge.dart';

class HeadPoseScreen extends ConsumerStatefulWidget {
  const HeadPoseScreen({super.key});

  @override
  ConsumerState<HeadPoseScreen> createState() => _HeadPoseScreenState();
}

class _HeadPoseScreenState extends ConsumerState<HeadPoseScreen> {
  final _tracker = HeadPoseTracker();
  HeadPoseCommandBridge? _bridge;

  HeadPose? _lastPose;
  bool _isActive = false;

  // ── Lifecycle ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  @override
  void dispose() {
    _bridge?.dispose();
    _tracker.stop();
    super.dispose();
  }

  // ── تشغيل / إيقاف ─────────────────────────────────────────────────────
  Future<void> _startTracking() async {
    _bridge = HeadPoseCommandBridge(ref);

    // نستمع للـ stream لتحديث UI فقط
    _tracker.poseStream.listen((pose) {
      if (mounted) setState(() => _lastPose = pose);
    });

    await _tracker.start();
    _bridge!.start();

    if (mounted) setState(() => _isActive = true);
  }

  Future<void> _stopTracking() async {
    _bridge?.dispose();
    await _tracker.stop();
    if (mounted) {
      setState(() {
        _isActive = false;
        _lastPose = null;
      });
    }
  }

  Future<void> _toggle() async {
    _isActive ? await _stopTracking() : await _startTracking();
  }

  // ── UI ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mqtt = ref.watch(mqttNotifierProvider);
    final pose = _lastPose;
    final direction = pose?.direction ?? HeadDirection.center;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('تحكم بالرأس', style: TextStyle(color: Colors.white)),
        actions: [
          // ── مؤشر MQTT ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 16),
            child: Row(
              children: [
                Icon(
                  mqtt.isConnected ? Icons.wifi : Icons.wifi_off,
                  color: mqtt.isConnected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  mqtt.isConnected ? 'متصل' : 'غير متصل',
                  style: TextStyle(
                    color: mqtt.isConnected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          // ── أزرار الأجهزة الحالية ──────────────────────────────
          _DeviceStatusBar(mqtt: mqtt, ref: ref),

          const SizedBox(height: 16),

          // ── مؤشر الاتجاه الرئيسي ──────────────────────────────
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── الدائرة ─────────────────────────────────────
                  _DirectionCircle(
                    direction: direction,
                    isActive: _isActive,
                    mouthOpen: pose?.mouthOpen ?? false,
                  ),

                  const SizedBox(height: 24),

                  // ── معلومات الاتجاه والإيماءات ────────────────
                  _GestureInfo(pose: pose),

                  const SizedBox(height: 32),

                  // ── زر تشغيل/إيقاف ──────────────────────────
                  _ToggleButton(isActive: _isActive, onTap: _toggle),

                  const SizedBox(height: 12),

                  // ── زر معايرة ───────────────────────────────
                  if (_isActive)
                    TextButton.icon(
                      onPressed: () => _tracker.calibrate(),
                      icon: const Icon(Icons.autorenew, color: Colors.amber),
                      label: const Text(
                        'إعادة معايرة',
                        style: TextStyle(color: Colors.amber),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── خريطة الأوامر ──────────────────────────────────────
          const _CommandMapCard(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Widgets مساعدة
// ═══════════════════════════════════════════════════════════════════════════

// شريط حالة الأجهزة
class _DeviceStatusBar extends StatelessWidget {
  final dynamic mqtt;
  final WidgetRef ref;
  const _DeviceStatusBar({required this.mqtt, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _DeviceDot(label: 'مروحة', on: mqtt.fan, icon: Icons.air),
          _DeviceDot(label: 'مصباح', on: mqtt.lamp, icon: Icons.lightbulb),
          _DeviceDot(label: 'شريط', on: mqtt.strip, icon: Icons.straight),
          _DeviceDot(label: 'أمان', on: mqtt.security, icon: Icons.security),
        ],
      ),
    );
  }
}

class _DeviceDot extends StatelessWidget {
  final String label;
  final bool on;
  final IconData icon;
  const _DeviceDot({required this.label, required this.on, required this.icon});

  @override
  Widget build(BuildContext context) {
    final color = on ? Colors.greenAccent : Colors.grey.shade700;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

// دائرة الاتجاه
class _DirectionCircle extends StatelessWidget {
  final HeadDirection direction;
  final bool isActive;
  final bool mouthOpen;
  const _DirectionCircle({
    required this.direction,
    required this.isActive,
    required this.mouthOpen,
  });

  static const _icons = {
    HeadDirection.left: Icons.arrow_back,
    HeadDirection.right: Icons.arrow_forward,
    HeadDirection.up: Icons.arrow_upward,
    HeadDirection.down: Icons.arrow_downward,
    HeadDirection.center: Icons.radio_button_unchecked,
  };

  static const _colors = {
    HeadDirection.left: Colors.cyanAccent,
    HeadDirection.right: Colors.greenAccent,
    HeadDirection.up: Colors.purpleAccent,
    HeadDirection.down: Colors.orangeAccent,
    HeadDirection.center: Colors.white24,
  };

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? (_colors[direction] ?? Colors.white24)
        : Colors.white12;
    final icon = _icons[direction] ?? Icons.radio_button_unchecked;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.1),
        border: Border.all(
          color: mouthOpen ? Colors.yellowAccent : color,
          width: mouthOpen ? 4 : 3,
        ),
        boxShadow: isActive && direction != HeadDirection.center
            ? [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ]
            : [],
      ),
      child: Icon(icon, color: color, size: 72),
    );
  }
}

// معلومات الإيماءات
class _GestureInfo extends StatelessWidget {
  final HeadPose? pose;
  const _GestureInfo({required this.pose});

  @override
  Widget build(BuildContext context) {
    if (pose == null) {
      return const Text(
        'في انتظار الكاميرا...',
        style: TextStyle(color: Colors.white38, fontSize: 16),
      );
    }

    final dirLabel = _dirLabel(pose!.direction);
    final cmdLabel = _cmdFor(pose!.direction);

    return Column(
      children: [
        // الاتجاه والأمر
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: dirLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (cmdLabel != null) ...[
                const TextSpan(
                  text: '  →  ',
                  style: TextStyle(color: Colors.white38, fontSize: 18),
                ),
                TextSpan(
                  text: cmdLabel,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 18,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        // الإيماءات الأخرى
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GesturePill(
              label: 'فتح الفم',
              active: pose!.mouthOpen,
              color: Colors.yellowAccent,
              icon: Icons.sentiment_very_satisfied,
            ),
            const SizedBox(width: 8),
            _GesturePill(
              label: 'هز الرأس',
              active: pose!.headShake,
              color: Colors.redAccent,
              icon: Icons.close,
            ),
          ],
        ),
      ],
    );
  }

  String _dirLabel(HeadDirection d) {
    switch (d) {
      case HeadDirection.left:
        return 'يسار ←';
      case HeadDirection.right:
        return 'يمين →';
      case HeadDirection.up:
        return 'أعلى ↑';
      case HeadDirection.down:
        return 'أسفل ↓';
      case HeadDirection.center:
        return 'مركز';
    }
  }

  String? _cmdFor(HeadDirection d) {
    const map = {
      HeadDirection.left: 'مروحة تشغيل',
      HeadDirection.right: 'مروحة إيقاف',
      HeadDirection.up: 'مصباح تشغيل',
      HeadDirection.down: 'مصباح إيقاف',
    };
    return map[d];
  }
}

class _GesturePill extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final IconData icon;
  const _GesturePill({
    required this.label,
    required this.active,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.2) : Colors.transparent,
        border: Border.all(color: active ? color : Colors.white12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: active ? color : Colors.white24, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? color : Colors.white24,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// زر التشغيل/الإيقاف
class _ToggleButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback onTap;
  const _ToggleButton({required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(
        isActive ? Icons.stop_circle_outlined : Icons.play_circle_outline,
      ),
      label: Text(
        isActive ? 'إيقاف التتبع' : 'بدء التتبع',
        style: const TextStyle(fontSize: 16),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isActive ? Colors.red.shade700 : Colors.indigo,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// بطاقة خريطة الأوامر
class _CommandMapCard extends StatelessWidget {
  const _CommandMapCard();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('رأس يسار  ←', 'FAN_ON    — مروحة تشغيل', Colors.cyanAccent),
      ('رأس يمين  →', 'FAN_OFF   — مروحة إيقاف', Colors.greenAccent),
      ('رأس أعلى  ↑', 'LAMP_ON   — مصباح تشغيل', Colors.purpleAccent),
      ('رأس أسفل  ↓', 'LAMP_OFF  — مصباح إيقاف', Colors.orangeAccent),
      ('فتح الفم', 'STRIP_ON  — شريط إضاءة', Colors.yellowAccent),
      ('هز الرأس', 'SECURITY_ON — أمان', Colors.redAccent),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'خريطة الأوامر',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      r.$1,
                      style: TextStyle(color: r.$3, fontSize: 13),
                    ),
                  ),
                  Text(
                    r.$2,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
