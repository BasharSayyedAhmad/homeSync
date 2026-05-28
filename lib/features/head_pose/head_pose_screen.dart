import 'package:flutter/material.dart';
import 'head_pose_tracker.dart';

class HeadPoseScreen extends StatefulWidget {
  const HeadPoseScreen({super.key});

  @override
  State<HeadPoseScreen> createState() => _HeadPoseScreenState();
}

class _HeadPoseScreenState extends State<HeadPoseScreen>
    implements HeadNavigationManager {
  final HeadPoseTracker _tracker = HeadPoseTracker();

  HeadPose? _lastPose;

  @override
  void initState() {
    super.initState();
    _tracker.bindToHeadNavigationManager(this);
    _tracker.start();
  }

  @override
  void dispose() {
    _tracker.stop();
    _tracker.dispose();
    super.dispose();
  }

  @override
  void onHeadPose(HeadPose pose) {
    setState(() {
      _lastPose = pose;
    });

    // هنا تربط مع نظامك الحالي HeadNavigationManager + HomeScreen
    // مثال بسيط:
    switch (pose.direction) {
      case HeadDirection.left:
        _moveFocusLeft();
        break;
      case HeadDirection.right:
        _moveFocusRight();
        break;
      case HeadDirection.up:
        _moveFocusUp();
        break;
      case HeadDirection.down:
        _moveFocusDown();
        break;
      case HeadDirection.center:
        // ممكن تستخدمه كـ "no-op" أو confirm بعد ثبات معين
        break;
    }
  }

  void _moveFocusLeft() {
    // استدعِ logic التنقل عندك
  }

  void _moveFocusRight() {}
  void _moveFocusUp() {}
  void _moveFocusDown() {}
  IconData _iconForDirection(HeadDirection dir) {
    switch (dir) {
      case HeadDirection.left:
        return Icons.arrow_back;
      case HeadDirection.right:
        return Icons.arrow_forward;
      case HeadDirection.up:
        return Icons.arrow_upward;
      case HeadDirection.down:
        return Icons.arrow_downward;
      default:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Home Head Navigation')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // دائرة الاتجاه
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade900,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  _lastPose == null
                      ? Icons.circle
                      : _iconForDirection(_lastPose!.direction),
                  size: 70,
                  color: Colors.blueAccent,
                ),
              ),
            ),

            const SizedBox(height: 30),

            // قيم yaw/pitch
            Text(
              _lastPose == null
                  ? 'Waiting for head pose...'
                  : 'Yaw: ${_lastPose!.yaw.toStringAsFixed(1)}°   '
                        'Pitch: ${_lastPose!.pitch.toStringAsFixed(1)}°',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 20),

            // الاتجاه الحالي
            Text(
              _lastPose == null
                  ? '---'
                  : _lastPose!.direction.toString().toUpperCase(),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
