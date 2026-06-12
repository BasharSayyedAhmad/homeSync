// lib/features/head_pose/head_pose_command_bridge.dart
//
// ── الجسر الكامل بين تتبع الرأس وأوامر MQTT ──────────────────────────────
//
// كيف تستخدمه:
//   final bridge = HeadPoseCommandBridge(ref);
//   bridge.start();
//   bridge.dispose();   // في dispose() للشاشة

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/mqtt_provider.dart';
import 'head_pose_tracker.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 🗺️ خريطة الأوامر — غيّر هنا لتعديل أي أمر
// ═══════════════════════════════════════════════════════════════════════════

const Map<HeadDirection, String> _directionCommands = {
  HeadDirection.left: 'FAN_ON', // رأس يسار  → مروحة تشغيل
  HeadDirection.right: 'FAN_OFF', // رأس يمين  → مروحة إيقاف
  HeadDirection.up: 'LAMP_ON', // رأس أعلى  → مصباح تشغيل
  HeadDirection.down: 'LAMP_OFF', // رأس أسفل  → مصباح إيقاف
};

const String _mouthOpenCommand = 'STRIP_ON'; // فتح الفم → شريط إضاءة تشغيل
const String _mouthCloseCommand = 'STRIP_OFF'; // إغلاق الفم → شريط إضاءة إيقاف
const String _headShakeCommand = 'SECURITY_ON'; // هز الرأس → تفعيل الأمان

// ═══════════════════════════════════════════════════════════════════════════

class HeadPoseCommandBridge {
  final WidgetRef _ref;

  HeadPoseCommandBridge(this._ref);

  StreamSubscription<HeadPose>? _sub;

  // حالة داخلية لتجنب الأوامر المكررة
  HeadDirection _lastDirection = HeadDirection.center;
  bool _lastMouthOpen = false;

  // cooldown: 800ms بين كل أمر
  DateTime _lastCommandTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _cooldown = Duration(milliseconds: 800);

  // ── تشغيل ─────────────────────────────────────────────────────────────
  void start() {
    _sub?.cancel();
    _sub = HeadPoseTracker().poseStream.listen(_onPose);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  // ── معالجة كل إطار ────────────────────────────────────────────────────
  void _onPose(HeadPose pose) {
    final now = DateTime.now();

    // ── اتجاه الرأس ────────────────────────────────────────────
    // فقط عند تغير الاتجاه (لا مركز) وبعد انتهاء الـ cooldown
    if (pose.direction != HeadDirection.center &&
        pose.direction != _lastDirection &&
        now.difference(_lastCommandTime) >= _cooldown) {
      final cmd = _directionCommands[pose.direction];
      if (cmd != null) {
        _sendCommand(cmd);
        _lastCommandTime = now;
      }
    }
    _lastDirection = pose.direction;

    // ── فتح الفم (Mouth) ────────────────────────────────────────
    if (pose.mouthOpen != _lastMouthOpen &&
        now.difference(_lastCommandTime) >= _cooldown) {
      _sendCommand(pose.mouthOpen ? _mouthOpenCommand : _mouthCloseCommand);
      _lastCommandTime = now;
      _lastMouthOpen = pose.mouthOpen;
    }

    // ── هز الرأس (HeadShake) — يُرسَل مرة واحدة عند الكشف ──────
    if (pose.headShake && now.difference(_lastCommandTime) >= _cooldown) {
      _sendCommand(_headShakeCommand);
      _lastCommandTime = now;
    }
  }

  void _sendCommand(String cmd) {
    try {
      _ref.read(mqttNotifierProvider.notifier).sendCommand(cmd);
    } catch (e) {
      // MQTT غير متصل — تجاهل بصمت
    }
  }
}
