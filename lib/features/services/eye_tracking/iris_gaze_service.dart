// lib/services/iris_gaze_service.dart
//
// خدمة Flutter للتواصل مع IrisGazePlugin
// استخدام: IrisGazeService.start() / stop() / recalibrate()
//          IrisGazeService.gazeStream → Stream<String>

import 'dart:async';
import 'package:flutter/services.dart';

class IrisGazeService {
  IrisGazeService._(); // singleton نمط

  static const _method = MethodChannel('iris_gaze_channel');
  static const _event = EventChannel('iris_gaze_events');

  // ── Stream مباشر من الكاميرا ──────────────────────────────────────────────
  static Stream<String> get gazeStream =>
      _event.receiveBroadcastStream().map((e) => e.toString());

  // ── تشغيل / إيقاف ─────────────────────────────────────────────────────────
  static Future<void> start() async {
    try {
      await _method.invokeMethod('startIrisGaze');
    } on PlatformException catch (e) {
      throw Exception('IrisGaze start failed: ${e.message}');
    }
  }

  static Future<void> stop() async {
    try {
      await _method.invokeMethod('stopIrisGaze');
    } on PlatformException catch (_) {}
  }

  // ── إعادة معايرة (اطلب المستخدم ينظر للأمام ثم استدعها) ─────────────────
  static Future<void> recalibrate() async {
    try {
      await _method.invokeMethod('recalibrate');
    } on PlatformException catch (_) {}
  }

  static Future<bool> get isRunning async {
    try {
      return await _method.invokeMethod<bool>('isRunning') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
