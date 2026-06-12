// lib/features/head_pose/head_pose_tracker.dart
//
// ✅ محدث: إضافة mouthOpen + headShake + gaze من HeadPosePlugin

import 'dart:async';
import 'package:flutter/services.dart';

// ── اتجاهات الرأس ─────────────────────────────────────────────────────────
enum HeadDirection { left, right, up, down, center }

// ── بيانات الإطار الكاملة من HeadPosePlugin ───────────────────────────────
class HeadPose {
  final double yaw;
  final double pitch;
  final double roll;
  final HeadDirection direction;
  final bool mouthOpen; // ✅ جديد
  final bool headShake; // ✅ جديد
  final String gaze; // ✅ جديد: gazeLeft|gazeRight|gazeUp|gazeDown|center|none

  const HeadPose({
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.direction,
    this.mouthOpen = false,
    this.headShake = false,
    this.gaze = 'none',
  });

  factory HeadPose.fromMap(Map<dynamic, dynamic> map) {
    return HeadPose(
      yaw: (map['yaw'] as num?)?.toDouble() ?? 0.0,
      pitch: (map['pitch'] as num?)?.toDouble() ?? 0.0,
      roll: (map['roll'] as num?)?.toDouble() ?? 0.0,
      direction: _dirFromString((map['direction'] as String?) ?? 'center'),
      mouthOpen: (map['mouthOpen'] as bool?) ?? false, // ✅
      headShake: (map['headShake'] as bool?) ?? false, // ✅
      gaze: (map['gaze'] as String?) ?? 'none', // ✅
    );
  }

  static HeadDirection _dirFromString(String v) {
    switch (v) {
      case 'left':
        return HeadDirection.left;
      case 'right':
        return HeadDirection.right;
      case 'up':
        return HeadDirection.up;
      case 'down':
        return HeadDirection.down;
      default:
        return HeadDirection.center;
    }
  }
}

// ── Tracker (Singleton) ───────────────────────────────────────────────────
class HeadPoseTracker {
  static const _method = MethodChannel('head_pose_channel');
  static const _event = EventChannel('head_pose_events');

  static final HeadPoseTracker _instance = HeadPoseTracker._();
  factory HeadPoseTracker() => _instance;
  HeadPoseTracker._();

  Stream<HeadPose>? _stream;

  Stream<HeadPose> get poseStream {
    _stream ??= _event.receiveBroadcastStream().map(
      (e) => HeadPose.fromMap(e as Map<dynamic, dynamic>),
    );
    return _stream!;
  }

  Future<void> start() => _method.invokeMethod('start');
  Future<void> stop() => _method.invokeMethod('stop');
  Future<void> calibrate() => _method.invokeMethod('calibrate');
}
