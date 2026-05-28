import 'dart:async';
import 'package:flutter/services.dart';

enum HeadDirection { left, right, up, down, center }

class HeadPose {
  final double yaw;
  final double pitch;
  final double roll;
  final HeadDirection direction;

  const HeadPose({
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.direction,
  });

  factory HeadPose.fromMap(Map<dynamic, dynamic> map) {
    final dirString = (map['direction'] as String?) ?? 'center';
    return HeadPose(
      yaw: (map['yaw'] as num?)?.toDouble() ?? 0.0,
      pitch: (map['pitch'] as num?)?.toDouble() ?? 0.0,
      roll: (map['roll'] as num?)?.toDouble() ?? 0.0,
      direction: _directionFromString(dirString),
    );
  }

  static HeadDirection _directionFromString(String value) {
    switch (value) {
      case 'left':
        return HeadDirection.left;
      case 'right':
        return HeadDirection.right;
      case 'up':
        return HeadDirection.up;
      case 'down':
        return HeadDirection.down;
      case 'center':
      default:
        return HeadDirection.center;
    }
  }

  @override
  String toString() {
    return 'HeadPose(yaw: $yaw, pitch: $pitch, roll: $roll, direction: $direction)';
  }
}

class HeadPoseTracker {
  static const MethodChannel _methodChannel = MethodChannel(
    'head_pose_channel',
  );

  static const EventChannel _eventChannel = EventChannel('head_pose_events');

  static final HeadPoseTracker _instance = HeadPoseTracker._internal();

  factory HeadPoseTracker() => _instance;

  HeadPoseTracker._internal();

  Stream<HeadPose>? _poseStream;
  StreamSubscription? _subscription;

  Stream<HeadPose> get poseStream {
    _poseStream ??= _eventChannel.receiveBroadcastStream().map(
      (event) => HeadPose.fromMap(event as Map<dynamic, dynamic>),
    );
    return _poseStream!;
  }

  Future<void> start() async {
    await _methodChannel.invokeMethod('start');
  }

  Future<void> stop() async {
    await _methodChannel.invokeMethod('stop');
  }

  /// Helper to connect directly to your HeadNavigationManager
  void bindToHeadNavigationManager(HeadNavigationManager manager) {
    _subscription?.cancel();
    _subscription = poseStream.listen((pose) {
      manager.onHeadPose(pose);
    });
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// Example HeadNavigationManager integration
/// (افترض أن عندك HeadNavigationManager جاهز، هنا بس نوريك الربط)
abstract class HeadNavigationManager {
  void onHeadPose(HeadPose pose);
}
