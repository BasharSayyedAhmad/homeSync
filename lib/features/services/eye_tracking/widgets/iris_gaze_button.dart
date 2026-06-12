// lib/widgets/iris_gaze_button.dart
//
// زر تبديل (Toggle) لتفعيل/إيقاف تتبع العين المستقل
// يُضاف في أي شاشة تريدها للتجريب أمام اللجنة
//
// مثال الاستخدام في شاشتك:
//   import 'widgets/iris_gaze_button.dart';
//   ...
//   child: IrisGazeButton()

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:homesync/features/services/eye_tracking/iris_gaze_service.dart';

class IrisGazeButton extends StatefulWidget {
  /// callback اختياري يُستدعى عند كل اتجاه جديد
  final void Function(String gaze)? onGazeChanged;

  const IrisGazeButton({super.key, this.onGazeChanged});

  @override
  State<IrisGazeButton> createState() => _IrisGazeButtonState();
}

class _IrisGazeButtonState extends State<IrisGazeButton> {
  bool _active = false;
  String _gaze = 'center';
  StreamSubscription<String>? _sub;

  // ── أيقونة وسهم لكل اتجاه ─────────────────────────────────────────────────
  static const _icons = {
    'gazeUp': Icons.arrow_upward,
    'gazeDown': Icons.arrow_downward,
    'gazeLeft': Icons.arrow_back,
    'gazeRight': Icons.arrow_forward,
    'center': Icons.remove_red_eye_outlined,
    'calibrating': Icons.autorenew,
    'noFace': Icons.face_retouching_off,
  };

  static const _colors = {
    'gazeUp': Colors.blue,
    'gazeDown': Colors.orange,
    'gazeLeft': Colors.purple,
    'gazeRight': Colors.green,
    'center': Colors.grey,
    'calibrating': Colors.yellow,
    'noFace': Colors.red,
  };

  // ── تشغيل / إيقاف ─────────────────────────────────────────────────────────
  Future<void> _toggle() async {
    if (_active) {
      await _stopGaze();
    } else {
      await _startGaze();
    }
  }

  Future<void> _startGaze() async {
    try {
      await IrisGazeService.start();
      _sub = IrisGazeService.gazeStream.listen((gaze) {
        setState(() => _gaze = gaze);
        widget.onGazeChanged?.call(gaze);
      });
      setState(() {
        _active = true;
        _gaze = 'calibrating';
      });
    } catch (e) {
      _showError('فشل تشغيل تتبع العين:\n$e');
    }
  }

  Future<void> _stopGaze() async {
    await _sub?.cancel();
    _sub = null;
    await IrisGazeService.stop();
    setState(() {
      _active = false;
      _gaze = 'center';
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  void dispose() {
    _sub?.cancel();
    IrisGazeService.stop();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final color = _colors[_gaze] ?? Colors.grey;
    final icon = _icons[_gaze] ?? Icons.remove_red_eye_outlined;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── زر التفعيل ───────────────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: _toggle,
          icon: Icon(_active ? Icons.visibility_off : Icons.visibility),
          label: Text(
            _active ? 'إيقاف تتبع العين' : 'تفعيل تتبع العين',
            style: const TextStyle(fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _active ? Colors.red.shade700 : Colors.indigo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // ── مؤشر الاتجاه (يظهر فقط عند التشغيل) ────────────────────────
        if (_active) ...[
          const SizedBox(height: 16),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 10),
                Text(
                  _gazeLabel(_gaze),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // ── زر إعادة المعايرة ─────────────────────────────────────────
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await IrisGazeService.recalibrate();
              setState(() => _gaze = 'calibrating');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('انظر للأمام... جارٍ إعادة المعايرة'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.autorenew, size: 18),
            label: const Text('إعادة معايرة العين'),
          ),
        ],
      ],
    );
  }

  String _gazeLabel(String gaze) {
    switch (gaze) {
      case 'gazeUp':
        return 'نظر لأعلى ↑';
      case 'gazeDown':
        return 'نظر لأسفل ↓';
      case 'gazeLeft':
        return 'نظر يساراً ←';
      case 'gazeRight':
        return 'نظر يميناً →';
      case 'center':
        return 'مركز ●';
      case 'calibrating':
        return 'جارٍ المعايرة...';
      case 'noFace':
        return 'لا يوجد وجه';
      default:
        return gaze;
    }
  }
}
