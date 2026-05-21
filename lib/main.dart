// import 'package:flutter/material.dart';
// import 'package:homesync/knx/text_knx.dart';
// import 'package:speech_to_text/speech_to_text.dart' as stt;

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Speech Test',
//       home: TestKnx(),
//     );
//   }
// }

// class SpeechTestPage extends StatefulWidget {
//   const SpeechTestPage({super.key});
//   @override
//   _SpeechTestPageState createState() => _SpeechTestPageState();
// }

// class _SpeechTestPageState extends State<SpeechTestPage> {
//   late stt.SpeechToText _speech;
//   bool _isListening = false;
//   String _text = "اضغط زر المايك وبلّش احكي";

//   @override
//   void initState() {
//     super.initState();
//     _speech = stt.SpeechToText();
//   }

//   Future<void> _startListening() async {
//     bool available = await _speech.initialize(
//       onStatus: (status) {
//         print("STATUS: $status");
//         if (status == "done") {
//           setState(() => _isListening = false);
//         }
//       },
//       onError: (error) {
//         print("ERROR: $error");
//       },
//     );

//     if (available) {
//       setState(() => _isListening = true);
//       _speech.listen(
//         localeId: "ar-SY",
//         onResult: (result) {
//           setState(() {
//             _text = result.recognizedWords;
//           });
//         },
//       );
//     } else {
//       setState(() => _isListening = false);
//     }
//   }

//   void _stopListening() {
//     _speech.stop();
//     setState(() => _isListening = false);
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text("Speech To Text Test")),
//       body: Padding(
//         padding: const EdgeInsets.all(20),
//         child: Column(
//           children: [
//             Text(_text, style: TextStyle(fontSize: 22)),
//             const SizedBox(height: 30),
//             FloatingActionButton(
//               onPressed: _isListening ? _stopListening : _startListening,
//               child: Icon(_isListening ? Icons.mic : Icons.mic_none),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

void main() {
  runApp(const HeadControlApp());
}

class HeadControlApp extends StatelessWidget {
  const HeadControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'التحكم بالمكيف بحركة الرأس',
      theme: ThemeData.dark(),
      home: const CameraView(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  bool _isProcessing = false;
  String _lastCommand = "";
  bool _isFrontCamera = true;

  Face? _lastFace; // آخر وجه مكتشف
  String _debugText = ""; // نص يظهر على الشاشة

  final Map<String, String> _acCommands = {
    "RIGHT": "AC_ON",
    "LEFT": "AC_OFF",
    "UP": "TEMP_UP",
    "DOWN": "TEMP_DOWN",
    "RIGHT_BLINK": "HEAT_MODE",
    "LEFT_BLINK": "DRY_MODE",
  };

  void _sendMqttCommand(String command) {
    if (_lastCommand == command) return;
    _lastCommand = command;
    print('📡 [MQTT] sending command: $command');
  }

  @override
  void initState() {
    super.initState();
    _initCameraAndDetector();
  }

  Future<void> _initCameraAndDetector() async {
    final cameraStatus = await Permission.camera.request();
    if (cameraStatus != PermissionStatus.granted) {
      print('❌ صلاحية الكاميرا مرفوضة');
      return;
    }

    final cameras = await availableCameras();
    final camera = _isFrontCamera
        ? cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
          )
        : cameras.first;

    _cameraController = CameraController(camera, ResolutionPreset.medium);
    await _cameraController!.initialize();
    if (mounted) setState(() {});

    final options = FaceDetectorOptions(
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    );

    _faceDetector = FaceDetector(options: options);

    _cameraController!.startImageStream(_processCameraImage);
    print('✅ تم التهيئة بنجاح');
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      final inputImage = _getInputImageFromCamera(image);
      if (inputImage == null) return;

      final faces = await _faceDetector!.processImage(inputImage);

      if (faces.isNotEmpty) {
        final face = faces.first;
        _lastFace = face;
        _analyzeFace(face);
      } else {
        _lastFace = null;
      }

      setState(() {});
    } catch (e) {
      print("⚠️ خطأ أثناء معالجة الصورة: $e");
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _getInputImageFromCamera(CameraImage image) {
    try {
      final WriteBuffer buffer = WriteBuffer();
      for (final Plane plane in image.planes) {
        buffer.putUint8List(plane.bytes);
      }
      final bytes = buffer.done().buffer.asUint8List();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  void _analyzeFace(Face face) {
    final double? yaw = face.headEulerAngleY;
    final double? pitch = face.headEulerAngleX;
    final double? roll = face.headEulerAngleZ;

    final double? leftEye = face.leftEyeOpenProbability;
    final double? rightEye = face.rightEyeOpenProbability;

    _debugText =
        "Yaw: ${yaw?.toStringAsFixed(1)}°\nPitch: ${pitch?.toStringAsFixed(1)}°\nRoll: ${roll?.toStringAsFixed(1)}°\n"
        "LeftEye: ${leftEye?.toStringAsFixed(2)}\nRightEye: ${rightEye?.toStringAsFixed(2)}\n";

    if (yaw != null) {
      if (yaw > 20) {
        _debugText += "➡ حركة: يمين\n";
        _sendMqttCommand(_acCommands["RIGHT"]!);
      } else if (yaw < -20) {
        _debugText += "⬅ حركة: يسار\n";
        _sendMqttCommand(_acCommands["LEFT"]!);
      }
    }

    if (pitch != null) {
      if (pitch > 15) {
        _debugText += "⬆ حركة: فوق\n";
        _sendMqttCommand(_acCommands["UP"]!);
      } else if (pitch < -15) {
        _debugText += "⬇ حركة: تحت\n";
        _sendMqttCommand(_acCommands["DOWN"]!);
      }
    }

    if (leftEye != null && rightEye != null) {
      if (leftEye < 0.3 && rightEye > 0.7) {
        _debugText += "👁️ غمزة يسار\n";
        _sendMqttCommand(_acCommands["LEFT_BLINK"]!);
      } else if (rightEye < 0.3 && leftEye > 0.7) {
        _debugText += "👁️ غمزة يمين\n";
        _sendMqttCommand(_acCommands["RIGHT_BLINK"]!);
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التحكم الذكي بالمكيف')),
      body: _cameraController == null || !_cameraController!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                CameraPreview(_cameraController!),
                if (_lastFace != null)
                  _buildFaceOverlay(), // استخدام دالة منفصلة
                Positioned(
                  top: 20,
                  left: 20,
                  child: Text(
                    _debugText,
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFaceOverlay() {
    // استخدام LayoutBuilder لمعرفة حجم الحاوية الفعلي
    return LayoutBuilder(
      builder: (context, constraints) {
        // قم بضبط الإحداثيات بناءً على حجم الحاوية وأبعاد الكاميرا
        // تأكد من استخدام previewSize الصحيح والعكس إذا لزم الأمر
        final previewSize = _cameraController!.value.previewSize!;
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // حساب المقياس، مع الانتباه إلى أن صورة الكاميرا قد تكون معكوسة أو مستدارة
        double scaleX = screenWidth / previewSize.height;
        double scaleY = screenHeight / previewSize.width;

        // إذا كانت الكاميرا أمامية، قم بعكس الإحداثي الأفقي
        final isFrontCamera =
            _cameraController!.description.lensDirection ==
            CameraLensDirection.front;

        // رسم المربع
        return CustomPaint(
          size: Size(screenWidth, screenHeight),
          painter: FaceOverlayPainter(
            _lastFace!,
            scaleX,
            scaleY,
            isFrontCamera,
          ),
        );
      },
    );
  }
}

class FaceOverlayPainter extends CustomPainter {
  final Face face;
  final double scaleX;
  final double scaleY;
  final bool isFrontCamera;

  FaceOverlayPainter(this.face, this.scaleX, this.scaleY, this.isFrontCamera);

  @override
  void paint(Canvas canvas, Size size) {
    // 1️⃣ رسم المربع المحيط بالوجه
    final rectPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // تحويل إحداثيات ML Kit إلى إحداثيات الشاشة
    double left = face.boundingBox.left * scaleX;
    double top = face.boundingBox.top * scaleY;
    double right = face.boundingBox.right * scaleX;
    double bottom = face.boundingBox.bottom * scaleY;

    // إذا كانت الكاميرا أمامية، نعكس الإحداثيات الأفقية لتتماشى مع معاينة الكاميرا
    if (isFrontCamera) {
      left = size.width - left;
      right = size.width - right;
      // نبدل الـ left والـ right لأن الشاشة معكوسة
      final temp = left;
      left = right;
      right = temp;
    }

    final rect = Rect.fromLTRB(left, top, right, bottom);
    canvas.drawRect(rect, rectPaint);

    // 2️⃣ رسم نقاط العينين (Landmarks)
    final landmarkPaint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 4
      ..style = PaintingStyle.fill;

    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

    if (leftEye != null) {
      double x = leftEye.x * scaleX;
      double y = leftEye.y * scaleY;
      if (isFrontCamera) x = size.width - x;
      canvas.drawCircle(Offset(x, y), 8, landmarkPaint);
    }

    if (rightEye != null) {
      double x = rightEye.x * scaleX;
      double y = rightEye.y * scaleY;
      if (isFrontCamera) x = size.width - x;
      canvas.drawCircle(Offset(x, y), 8, landmarkPaint);
    }

    // 3️⃣ (اختياري) رسم خط أفقي أعلى الرأس لإظهار الاتجاه (يسار/يمين)
    final directionPaint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 2;

    // نستخدم المربع المرسوم لحساب منتصف الرأس
    final double headCenterX = (rect.left + rect.right) / 2;
    final double headY = rect.top - 10;
    canvas.drawLine(
      Offset(headCenterX - 20, headY),
      Offset(headCenterX + 20, headY),
      directionPaint,
    );

    // سهم صغير يشير إلى اتجاه الانعطاف (Yaw) بناءً على زاوية الرأس
    final yaw = face.headEulerAngleY;
    if (yaw != null) {
      final arrowOffset = (yaw / 45).clamp(-1.0, 1.0) * 20;
      canvas.drawLine(
        Offset(headCenterX, headY),
        Offset(headCenterX + arrowOffset, headY - 10),
        directionPaint,
      );
    }
  }

  // يجب أن يعاد الرسم عندما يتغير الوجه، ودائماً نعيد true لضمان التحديث
  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) => true;
}
