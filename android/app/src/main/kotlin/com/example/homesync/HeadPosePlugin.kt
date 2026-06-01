package com.example.homesync

// =============================================================================
//  HeadPosePlugin — النسخة النهائية v4
//  Redmi 15C / Helio G81
//
//  الميزات:
//  ✅ تتبع الرأس (يمين/يسار/أعلى/أسفل) مع Kalman + Hysteresis
//  ✅ كشف الغمز (EAR)             — enableBlinkDetection
//  ✅ رصد القزحية (Iris Gaze)     — enableIrisGaze
//  ✅ فتح الفم (Mouth Open)       — enableMouthGesture
//  ✅ إمالة الرأس (Tilt)          — enableTiltGesture
//  ✅ هز الرأس "لا" (Head Shake)  — enableHeadShake
//
//  ملاحظة فتح الفم: قيمة حقيقية لذوي الإعاقة كأمر "تأكيد ثانٍ".
//  ملاحظة الإمالة: رخيصة جداً (filteredRoll موجود مسبقاً).
//  ملاحظة هز الرأس: يحتاج 4 تحولات يمين/يسار خلال 1.2 ثانية → لا يتعارض مع أوامر الاتجاه.
// =============================================================================

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.*
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.sqrt

class HeadPosePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL_NAME = "head_pose_channel"
        private const val EVENT_CHANNEL_NAME  = "head_pose_events"
        private const val TAG                 = "HeadPosePlugin"
        private const val CAMERA_PERM_CODE    = 1001
    }

    // ── Flutter / Android ─────────────────────────────────────────────────────
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel:  EventChannel
    private var context:   Context?  = null
    private var activity:  Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    // ── Camera & MediaPipe ────────────────────────────────────────────────────
    private var cameraProvider: ProcessCameraProvider? = null
    private var cameraExecutor: ExecutorService?       = null
    private var faceLandmarker: FaceLandmarker?        = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Kalman Filters ────────────────────────────────────────────────────────
    private var yawKalman   = Kalman1D(q = 0.05, r = 0.8)
    private var pitchKalman = Kalman1D(q = 0.05, r = 0.8)
    private var rollKalman  = Kalman1D(q = 0.03, r = 1.2)

    // ── Direction Hysteresis ──────────────────────────────────────────────────
    private var lastDirection = "center"

    // يمين / يسار
    private val yawLeftEnter  = -15.0;  private val yawLeftExit  = -7.0
    private val yawRightEnter =  15.0;  private val yawRightExit =  7.0

    // أعلى / أسفل — العتبات أكبر لتقليل الحساسية وتجنب التشغيل الخاطئ عند العودة من يمين/يسار
    private val pitchUpEnter   = -16.0;  private val pitchUpExit   = -6.0
    private val pitchDownEnter =  16.0;  private val pitchDownExit =  6.0

    // المركز — exit(6) < center(11) < enter(16)  ✓ لكل المحاور
    private val centerYawThreshold   = 10.0   // exit(7) < center(10) < enter(15) ✓
    private val centerPitchThreshold = 11.0   // exit(6) < center(11) < enter(16) ✓

    // ── Views ─────────────────────────────────────────────────────────────────
    private var previewView:      PreviewView?     = null
    private var overlayView:      FaceOverlayView? = null
    private var overlayContainer: FrameLayout?     = null

    // ── Calibration (Trimmed Mean) ────────────────────────────────────────────
    private var isCalibrating         = false
    private val maxCalibrationSamples = 40
    private val calibrationSamples    = mutableListOf<Pair<Double, Double>>()
    private var baselineYaw           = 0.0
    private var baselinePitch         = 0.0

    // ── Frame Throttling ──────────────────────────────────────────────────────
    private var frameCounter  = 0
    private val frameSkipRate = 2   // ~15 FPS على كاميرا 30 FPS

    // ── Performance ───────────────────────────────────────────────────────────
    private var fpsStartTime = 0L
    private var fpsCounter   = 0
    private var actualFps    = 0

    // ─────────────────────────────────────────────────────────────────────────
    // ميزة 1: كشف الغمز (EAR)
    // ─────────────────────────────────────────────────────────────────────────
    var enableBlinkDetection = true
    // EAR = مسافة رأسية / مسافة أفقية — مستقل عن بُعد الوجه
    private val earClose         = 0.20   // عين مغلقة
    private val earOpen          = 0.24   // عين مفتوحة (hysteresis)
    private val minClosedFrames  = 1      // إطار واحد يكفي @ 7-10 FPS في الإضاءة المنخفضة
    private var closedFrameCount = 0
    private var eyesWereClosed   = false
    private var lastBlinkTime    = 0L
    private val blinkDebounceMs  = 1500L

    // ─────────────────────────────────────────────────────────────────────────
    // ميزة 2: رصد القزحية (Iris Gaze)
    // ─────────────────────────────────────────────────────────────────────────
    var enableIrisGaze = true
    // النسبة بين الطرفين: < 0.35 = يسار | > 0.65 = يمين
    private val gazeLeftThreshold  = 0.35f
    private val gazeRightThreshold = 0.65f

    // ─────────────────────────────────────────────────────────────────────────
    // ميزة 3: فتح الفم (Mouth Open — MAR)
    // ─────────────────────────────────────────────────────────────────────────
    var enableMouthGesture = true
    // MAR = Mouth Aspect Ratio = رأسي / أفقي
    // 0.40 تم اختياره ليكون أعلى من الكلام الطبيعي (~0.30) لتقليل التشغيل الخاطئ
    private val marOpen    = 0.40
    private val marClose   = 0.30   // hysteresis
    private var mouthIsOpen = false

    // ─────────────────────────────────────────────────────────────────────────
    // ميزة 4: إمالة الرأس (Tilt — Roll Axis)
    // ─────────────────────────────────────────────────────────────────────────
    var enableTiltGesture = true
    private val tiltLeftEnter  = -20.0;  private val tiltLeftExit  = -8.0
    private val tiltRightEnter =  20.0;  private val tiltRightExit =  8.0
    private var lastTilt = "center"

    // ─────────────────────────────────────────────────────────────────────────
    // ميزة 5: هز الرأس "لا" (Head Shake)
    // ─────────────────────────────────────────────────────────────────────────
    var enableHeadShake = true
    // يحتاج 4 تحولات (يسار-يمين-يسار-يمين) خلال 1.2 ثانية → غير محتمل عرضياً
    private val shakeWindowMs   = 1200L
    private val shakeMinYaw     = 15.0   // يُطابق yawLeftEnter لتجنب التشغيل الخاطئ
    private val shakeMinPeaks   = 4
    private val shakeDebounceMs = 1500L
    private val shakePeaks      = mutableListOf<Pair<Long, Boolean>>()  // (وقت, هليسار؟)
    private var lastShakeZone   = 0      // -1=يسار | 0=مركز | 1=يمين
    private var lastShakeTime   = 0L

    // ==========================================================================
    // Flutter Plugin Lifecycle
    // ==========================================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context       = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME)
        eventChannel  = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        context = null
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding)              { activity = b.activity }
    override fun onDetachedFromActivityForConfigChanges()                    { activity = null }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) { activity = b.activity }
    override fun onDetachedFromActivity()                                    { activity = null }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?)  { eventSink = events }
    override fun onCancel(arguments: Any?)                                   { eventSink = null }

    // ==========================================================================
    // Method Channel — أوامر Flutter
    // ==========================================================================

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start"         -> startHeadPose(result)
            "stop"          -> { stopHeadPose();               result.success(null) }
            "calibrate"     -> { startCalibration();           result.success(null) }
            // تشغيل/إيقاف الميزات الاختيارية
            "enableBlink"   -> { enableBlinkDetection = true;  result.success(null) }
            "disableBlink"  -> { enableBlinkDetection = false; result.success(null) }
            "enableIris"    -> { enableIrisGaze = true;        result.success(null) }
            "disableIris"   -> { enableIrisGaze = false;       result.success(null) }
            "enableMouth"   -> { enableMouthGesture = true;    result.success(null) }
            "disableMouth"  -> { enableMouthGesture = false;   result.success(null) }
            "enableTilt"    -> { enableTiltGesture = true;     result.success(null) }
            "disableTilt"   -> { enableTiltGesture = false;    result.success(null) }
            "enableShake"   -> { enableHeadShake = true;       result.success(null) }
            "disableShake"  -> { enableHeadShake = false;      result.success(null) }
            else            -> result.notImplemented()
        }
    }

    // ==========================================================================
    // Start / Stop
    // ==========================================================================

    private fun startHeadPose(result: MethodChannel.Result) {
        val act = activity ?: run { result.error("NO_ACTIVITY", "Activity is null", null); return }
        val ctx = context  ?: run { result.error("NO_CONTEXT",  "Context is null",  null); return }

        if (ContextCompat.checkSelfPermission(act, Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                act, arrayOf(Manifest.permission.CAMERA), CAMERA_PERM_CODE)
            result.error("PERMISSION_REQUIRED", "Camera permission required", null)
            return
        }
        result.success(null)
        executeStart(ctx, act)
    }

    private fun executeStart(ctx: Context, act: Activity) {
        if (cameraExecutor == null) cameraExecutor = Executors.newSingleThreadExecutor()
        if (faceLandmarker == null) initFaceLandmarker(ctx)

        // استرجاع نقطة الاتزان المحفوظة
        val prefs = ctx.getSharedPreferences("HeadPosePrefs", Context.MODE_PRIVATE)
        baselineYaw   = prefs.getFloat("baseline_yaw",   0f).toDouble()
        baselinePitch = prefs.getFloat("baseline_pitch",  0f).toDouble()

        // تهيئة الفلاتر بالقيمة المحفوظة لتجنب الارتعاش عند البداية
        yawKalman   = Kalman1D(q = 0.05, r = 0.8, x = baselineYaw)
        pitchKalman = Kalman1D(q = 0.05, r = 0.8, x = baselinePitch)
        rollKalman  = Kalman1D(q = 0.03, r = 1.2)

        // إعادة تعيين حالة الإيماءات
        closedFrameCount = 0;   eyesWereClosed = false
        mouthIsOpen      = false
        lastTilt         = "center"
        shakePeaks.clear();     lastShakeZone = 0

        fpsStartTime = System.currentTimeMillis()

        val future = ProcessCameraProvider.getInstance(ctx)
        future.addListener({
            cameraProvider = future.get()
            bindCameraUseCases(act)
        }, ContextCompat.getMainExecutor(ctx))
    }

    private fun stopHeadPose() {
        cameraProvider?.unbindAll()
        cameraExecutor?.shutdown();  cameraExecutor = null
        faceLandmarker?.close();     faceLandmarker = null

        lastDirection = "center";    isCalibrating = false
        calibrationSamples.clear(); frameCounter = 0
        shakePeaks.clear()

        yawKalman   = Kalman1D()
        pitchKalman = Kalman1D()
        rollKalman  = Kalman1D()

        val act = activity; val container = overlayContainer
        if (act != null && container != null)
            mainHandler.post {
                act.findViewById<ViewGroup>(android.R.id.content).removeView(container)
            }
        overlayContainer = null; previewView = null; overlayView = null
    }

    // ==========================================================================
    // FaceLandmarker — GPU أولاً، CPU احتياطياً
    // ==========================================================================

    private fun initFaceLandmarker(ctx: Context) {
        try {
            val builder = BaseOptions.builder().setModelAssetPath("face_landmarker.task")
            try {
                builder.setDelegate(Delegate.GPU)
                faceLandmarker = FaceLandmarker.createFromOptions(ctx, buildOptions(builder.build()))
                Log.d(TAG, "FaceLandmarker → GPU ✓")
            } catch (e: Exception) {
                Log.w(TAG, "GPU فشل — تراجع إلى CPU", e)
                builder.setDelegate(Delegate.CPU)
                faceLandmarker = FaceLandmarker.createFromOptions(ctx, buildOptions(builder.build()))
                Log.d(TAG, "FaceLandmarker → CPU ✓")
            }
        } catch (e: Exception) {
            Log.e(TAG, "FaceLandmarker: فشل كلي في التهيئة", e)
        }
    }

    private fun buildOptions(base: BaseOptions): FaceLandmarker.FaceLandmarkerOptions =
        FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .setOutputFacialTransformationMatrixes(true)
            .setResultListener { result, _ -> handleFaceLandmarkerResult(result) }
            .build()

    // ==========================================================================
    // Camera Setup
    // ==========================================================================

    private fun bindCameraUseCases(activity: Activity) {
        val provider = cameraProvider ?: return
        provider.unbindAll()

        if (previewView == null) {
            val root = activity.findViewById<ViewGroup>(android.R.id.content)
            val container = FrameLayout(activity).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            }
            val preview = PreviewView(activity).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
                scaleType = PreviewView.ScaleType.FILL_CENTER
            }
            val overlay = FaceOverlayView(activity).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
            }
            container.addView(preview); container.addView(overlay)
            mainHandler.post { root.addView(container) }
            previewView = preview; overlayView = overlay; overlayContainer = container
        }

        val targetSize  = android.util.Size(640, 480)
        val previewCase = Preview.Builder().setTargetResolution(targetSize).build()
        val analysisCase = ImageAnalysis.Builder()
            .setTargetResolution(targetSize)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build().also { analysis ->
                analysis.setAnalyzer(cameraExecutor!!) { imageProxy ->
                    frameCounter++
                    if (frameCounter % frameSkipRate == 0) processImageProxy(imageProxy)
                    else imageProxy.close()
                }
            }

        try {
            val lco = activity as? LifecycleOwner
                ?: throw IllegalStateException("Activity is not a LifecycleOwner")
            provider.bindToLifecycle(lco, CameraSelector.DEFAULT_FRONT_CAMERA,
                previewCase, analysisCase)
            previewCase.setSurfaceProvider(previewView!!.surfaceProvider)
        } catch (e: Exception) {
            Log.e(TAG, "Camera binding failed", e)
        }
    }

    // ==========================================================================
    // Frame Processing — الإصلاح الرئيسي لـ Helio G81
    // ==========================================================================

    private fun processImageProxy(imageProxy: ImageProxy) {
        val landmarker = faceLandmarker ?: run { imageProxy.close(); return }
        val startTime  = System.currentTimeMillis()
        try {
            // imageProxy.toBitmap() المدمج في CameraX يتعامل مع pixelStride بشكل صحيح
            // بعكس التحويل اليدوي الذي يفشل على Helio G81
            val rawBitmap = imageProxy.toBitmap()
            val rotDeg    = imageProxy.imageInfo.rotationDegrees.toFloat()
            val matrix    = Matrix().apply {
                postRotate(rotDeg)
                postScale(-1f, 1f)  // عكس أفقي للكاميرا الأمامية
            }
            val bitmap = Bitmap.createBitmap(
                rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true)
            rawBitmap.recycle()

            overlayView?.setImageDimensions(bitmap.width, bitmap.height)
            landmarker.detectAsync(BitmapImageBuilder(bitmap).build(), System.nanoTime() / 1000)
            overlayView?.updateLatency(System.currentTimeMillis() - startTime)

            fpsCounter++
            val now = System.currentTimeMillis()
            if (now - fpsStartTime >= 1000L) {
                actualFps = fpsCounter; fpsCounter = 0; fpsStartTime = now
                overlayView?.updateFps(actualFps)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Frame processing error", e)
        } finally {
            imageProxy.close()
        }
    }

    // ==========================================================================
    // نتائج MediaPipe — القلب
    // ==========================================================================

    private fun handleFaceLandmarkerResult(result: FaceLandmarkerResult) {
        val faces = try { result.faceLandmarks() } catch (_: Exception) { emptyList() }

        if (faces.isNotEmpty()) {
            overlayView?.updateLandmarks(faces[0])
            if (enableBlinkDetection) detectBlink(faces[0])
        } else {
            overlayView?.clearLandmarks()
        }

        val matricesOpt = result.facialTransformationMatrixes()
        if (!matricesOpt.isPresent || matricesOpt.get().isEmpty()) {
            sendHeadPose(0.0, 0.0, 0.0, "center", "none", "center", false, false)
            return
        }
        val data = matricesOpt.get()[0]
        if (data.size < 16) {
            sendHeadPose(0.0, 0.0, 0.0, "center", "none", "center", false, false)
            return
        }

        // عناصر المصفوفة 4×4 (row-major):  data[row*4 + col]
        val m00 = data[0].toDouble();  val m10 = data[4].toDouble()
        val m20 = data[8].toDouble();  val m21 = data[9].toDouble();  val m22 = data[10].toDouble()

        // تحليل ZYX Euler:
        //   rawYaw   → دوران Y (التفاف يمين/يسار)
        //   rawPitch → دوران X (إيماء أعلى/أسفل) ← الصيغة الصحيحة
        //   rawRoll  → دوران Z (إمالة الرأس)
        val rawYaw   = Math.toDegrees(atan2(-m20, sqrt(m00 * m00 + m10 * m10)))
        val rawPitch = Math.toDegrees(atan2( m21,  m22))
        val rawRoll  = Math.toDegrees(atan2( m10,  m00))

        // نعكس Yaw لأن الصورة معكوسة (postScale -1)
        // نعكس Pitch لأن اتجاه محور X في MediaPipe عكس الحدس
        val filteredYaw   = yawKalman.update(-rawYaw)
        val filteredPitch = pitchKalman.update(-rawPitch)
        val filteredRoll  = rollKalman.update(rawRoll)

        // ── المعايرة ──────────────────────────────────────────────────────────
        if (isCalibrating) {
            calibrationSamples.add(Pair(filteredYaw, filteredPitch))
            overlayView?.updatePose(filteredYaw, filteredPitch, filteredRoll, "calibrating")
            if (calibrationSamples.size >= maxCalibrationSamples) {
                val trim = (maxCalibrationSamples * 0.2).toInt()
                baselineYaw = calibrationSamples.map { it.first }
                    .sorted().drop(trim).dropLast(trim).average()
                baselinePitch = calibrationSamples.map { it.second }
                    .sorted().drop(trim).dropLast(trim).average()
                context?.getSharedPreferences("HeadPosePrefs", Context.MODE_PRIVATE)
                    ?.edit()
                    ?.putFloat("baseline_yaw",   baselineYaw.toFloat())
                    ?.putFloat("baseline_pitch",  baselinePitch.toFloat())
                    ?.apply()
                isCalibrating = false
                calibrationSamples.clear()
                sendHeadPose(0.0, 0.0, filteredRoll, "center", "none", "center", false, false)
            }
            return
        }

        val adjYaw   = filteredYaw   - baselineYaw
        val adjPitch = filteredPitch - baselinePitch

        // ── تصنيف الاتجاه الرئيسي ─────────────────────────────────────────────
        val direction = classifyDirection(adjYaw, adjPitch)

        // ── الإيماءات الإضافية (كل واحدة مستقلة) ────────────────────────────
        val gaze  = if (enableIrisGaze    && faces.isNotEmpty()) detectIrisGaze(faces[0])   else "none"
        val mouth = if (enableMouthGesture && faces.isNotEmpty()) detectMouthOpen(faces[0]) else false
        val tilt  = if (enableTiltGesture) classifyTilt(filteredRoll)                       else "center"
        val shake = if (enableHeadShake)   detectHeadShake(adjYaw)                          else false

        overlayView?.updatePose(adjYaw, adjPitch, filteredRoll, direction, mouth)
        sendHeadPose(adjYaw, adjPitch, filteredRoll, direction, gaze, tilt, mouth, shake)
    }

    // ==========================================================================
    // تصنيف الاتجاه الرئيسي (Hysteresis)
    // ==========================================================================

    private fun classifyDirection(yawDeg: Double, pitchDeg: Double): String {
        when (lastDirection) {
            "center" -> when {
                yawDeg   <= yawLeftEnter   -> lastDirection = "left"
                yawDeg   >= yawRightEnter  -> lastDirection = "right"
                pitchDeg <= pitchUpEnter   -> lastDirection = "up"
                pitchDeg >= pitchDownEnter -> lastDirection = "down"
            }
            "left"  -> if (yawDeg   >= yawLeftExit)   lastDirection = decideFromCenter(yawDeg, pitchDeg)
            "right" -> if (yawDeg   <= yawRightExit)  lastDirection = decideFromCenter(yawDeg, pitchDeg)
            "up"    -> if (pitchDeg >= pitchUpExit)   lastDirection = decideFromCenter(yawDeg, pitchDeg)
            "down"  -> if (pitchDeg <= pitchDownExit) lastDirection = decideFromCenter(yawDeg, pitchDeg)
        }
        return lastDirection
    }

    private fun decideFromCenter(yawDeg: Double, pitchDeg: Double): String {
        if (abs(yawDeg) <= centerYawThreshold && abs(pitchDeg) <= centerPitchThreshold)
            return "center"
        return if (abs(yawDeg) > abs(pitchDeg)) {
            if (yawDeg < 0) "left" else "right"
        } else {
            if (pitchDeg < 0) "up" else "down"
        }
    }

    // ==========================================================================
    // ميزة 1: كشف الغمز (EAR)
    // ==========================================================================

    private fun detectBlink(landmarks: List<NormalizedLandmark>) {
        if (landmarks.size < 387) return

        // العين اليسرى: 159(علوي) 145(سفلي) 33(خارج) 133(داخل)
        val lv = abs(landmarks[159].y() - landmarks[145].y())
        val lh = abs(landmarks[33].x()  - landmarks[133].x())
        val leftEAR = if (lh > 0.001f) lv / lh else 0f

        // العين اليمنى: 386(علوي) 374(سفلي) 263(خارج) 362(داخل)
        val rv = abs(landmarks[386].y() - landmarks[374].y())
        val rh = abs(landmarks[263].x()  - landmarks[362].x())
        val rightEAR = if (rh > 0.001f) rv / rh else 0f

        val avgEAR = (leftEAR + rightEAR) / 2.0
        val now    = System.currentTimeMillis()

        when {
            avgEAR < earClose -> {
                closedFrameCount++
                if (closedFrameCount >= minClosedFrames) eyesWereClosed = true
            }
            avgEAR > earOpen && eyesWereClosed -> {
                if (now - lastBlinkTime >= blinkDebounceMs) {
                    lastBlinkTime = now
                    sendBlink()
                }
                eyesWereClosed = false;  closedFrameCount = 0
            }
            avgEAR > earOpen -> closedFrameCount = 0
        }
    }

    private fun sendBlink() {
        overlayView?.updateBlink()
        eventSink?.let { sink ->
            mainHandler.post { sink.success(mapOf("blink" to true)) }
        }
    }

    // ==========================================================================
    // ميزة 2: رصد القزحية (Iris Gaze)
    // ==========================================================================

    private fun detectIrisGaze(landmarks: List<NormalizedLandmark>): String {
        // 468 = قزحية العين اليمنى | 263 و 362 = ركنا العين اليمنى
        if (landmarks.size < 474) return "center"
        val irisX   = landmarks[468].x()
        val cornerA = landmarks[263].x()
        val cornerB = landmarks[362].x()
        val minX    = minOf(cornerA, cornerB)
        val span    = abs(cornerA - cornerB)
        if (span < 0.005f) return "center"
        val ratio = (irisX - minX) / span
        return when {
            ratio < gazeLeftThreshold  -> "gazeLeft"
            ratio > gazeRightThreshold -> "gazeRight"
            else                       -> "center"
        }
    }

    // ==========================================================================
    // ميزة 3: فتح الفم (MAR)
    // ==========================================================================

    private fun detectMouthOpen(landmarks: List<NormalizedLandmark>): Boolean {
        // 13(علوي داخلي) 14(سفلي داخلي) 78(ركن أيسر) 308(ركن أيمن)
        if (landmarks.size < 309) return false
        val mouthV = abs(landmarks[13].y() - landmarks[14].y())
        val mouthH = abs(landmarks[78].x() - landmarks[308].x())
        val mar    = if (mouthH > 0.01f) mouthV / mouthH else 0f
        mouthIsOpen = when {
            mar > marOpen  -> true
            mar < marClose -> false
            else           -> mouthIsOpen   // hysteresis: أبقِ الحالة السابقة
        }
        return mouthIsOpen
    }

    // ==========================================================================
    // ميزة 4: إمالة الرأس (Tilt — Roll Axis)
    // ==========================================================================

    private fun classifyTilt(rollDeg: Double): String {
        lastTilt = when {
            lastTilt == "center"    -> when {
                rollDeg <= tiltLeftEnter  -> "tiltLeft"
                rollDeg >= tiltRightEnter -> "tiltRight"
                else                      -> "center"
            }
            lastTilt == "tiltLeft"  -> if (rollDeg >= tiltLeftExit)  "center" else "tiltLeft"
            lastTilt == "tiltRight" -> if (rollDeg <= tiltRightExit) "center" else "tiltRight"
            else                    -> "center"
        }
        return lastTilt
    }

    // ==========================================================================
    // ميزة 5: هز الرأس "لا" (Head Shake)
    // ==========================================================================

    private fun detectHeadShake(yawDeg: Double): Boolean {
        val now = System.currentTimeMillis()
        // أزل الذروات التي تجاوزت النافذة الزمنية
        shakePeaks.removeAll { now - it.first > shakeWindowMs }

        val newZone = when {
            yawDeg < -shakeMinYaw -> -1  // يسار
            yawDeg >  shakeMinYaw ->  1  // يمين
            else                  ->  0  // مركز
        }

        // سجّل ذروة جديدة فقط عند الدخول لمنطقة (لا عند البقاء فيها)
        if (newZone != 0 && newZone != lastShakeZone) {
            val isLeft = newZone == -1
            // اشترط التناوب (يسار ثم يمين ثم يسار...)
            if (shakePeaks.isEmpty() || shakePeaks.last().second != isLeft)
                shakePeaks.add(Pair(now, isLeft))
        }
        lastShakeZone = newZone

        if (shakePeaks.size >= shakeMinPeaks) {
            val detected = now - lastShakeTime >= shakeDebounceMs
            if (detected) {
                lastShakeTime = now
                overlayView?.updateShake()
            }
            shakePeaks.clear();  lastShakeZone = 0
            return detected
        }
        return false
    }

    // ==========================================================================
    // المعايرة
    // ==========================================================================

    private fun startCalibration() {
        isCalibrating = true
        calibrationSamples.clear()
    }

    // ==========================================================================
    // إرسال البيانات إلى Flutter
    // ==========================================================================

    // الحدث الرئيسي — يُرسل كل إطار
    // هيكل الـ Map:
    //   yaw/pitch/roll : Double (درجات)
    //   direction      : "left"|"right"|"up"|"down"|"center"
    //   gaze           : "gazeLeft"|"gazeRight"|"center"|"none"
    //   tilt           : "tiltLeft"|"tiltRight"|"center"
    //   mouthOpen      : Boolean
    //   headShake      : Boolean (true لإطار واحد فقط عند الكشف)
    private fun sendHeadPose(
        yaw: Double, pitch: Double, roll: Double,
        direction: String,
        gaze: String,
        tilt: String,
        mouthOpen: Boolean,
        headShake: Boolean
    ) {
        eventSink?.let { sink ->
            mainHandler.post {
                sink.success(mapOf(
                    "yaw"       to yaw,
                    "pitch"     to pitch,
                    "roll"      to roll,
                    "direction" to direction,
                    "gaze"      to gaze,
                    "tilt"      to tilt,
                    "mouthOpen" to mouthOpen,
                    "headShake" to headShake
                ))
            }
        }
    }

    // ==========================================================================
    // فلتر كالمان 1D
    // ==========================================================================

    class Kalman1D(
        private var q: Double = 0.02,
        private var r: Double = 1.0,
        private var x: Double = 0.0,
        private var p: Double = 1.0,
        private var k: Double = 0.0
    ) {
        fun update(measurement: Double): Double {
            p += q
            k  = p / (p + r)
            x += k * (measurement - x)
            p *= (1.0 - k)
            return x
        }
    }

    // ==========================================================================
    // واجهة الرسم (FaceOverlayView)
    // ==========================================================================

    private class FaceOverlayView(context: Context) : View(context) {

        private val dotPaint    = Paint().apply {
            color = Color.GREEN; style = Paint.Style.FILL; isAntiAlias = true }
        private val boxPaint    = Paint().apply {
            color = Color.CYAN; style = Paint.Style.STROKE; strokeWidth = 4f; isAntiAlias = true }
        private val textBgPaint = Paint().apply {
            color = Color.argb(150, 0, 0, 0); style = Paint.Style.FILL }
        private val textPaint   = Paint().apply {
            color = Color.WHITE; textSize = 34f; isAntiAlias = true; typeface = Typeface.MONOSPACE }
        private val dirPaint    = Paint().apply {
            textSize = 56f; isFakeBoldText = true; isAntiAlias = true
            typeface = Typeface.DEFAULT_BOLD }

        @Volatile private var landmarks:     List<NormalizedLandmark>? = null
        @Volatile private var yaw           = 0.0
        @Volatile private var pitch         = 0.0
        @Volatile private var roll          = 0.0
        @Volatile private var direction     = "center"
        @Volatile private var mouthOpen     = false
        @Volatile private var imgWidth      = 0
        @Volatile private var imgHeight     = 0
        @Volatile private var latency       = 0L
        @Volatile private var fps           = 0
        @Volatile private var blinkFlashEnd = 0L   // وميض "BLINK ✓"
        @Volatile private var shakeFlashEnd = 0L   // وميض "SHAKE ✓"

        fun setImageDimensions(w: Int, h: Int) { imgWidth = w; imgHeight = h }
        fun updateLatency(ms: Long)            { latency = ms }
        fun updateFps(f: Int)                  { fps = f }
        fun clearLandmarks()                   { landmarks = null; postInvalidateOnAnimation() }

        fun updateBlink() {
            blinkFlashEnd = System.currentTimeMillis() + 1000L
            postInvalidateOnAnimation()
        }
        fun updateShake() {
            shakeFlashEnd = System.currentTimeMillis() + 1000L
            postInvalidateOnAnimation()
        }
        fun updateLandmarks(list: List<NormalizedLandmark>) {
            landmarks = list; postInvalidateOnAnimation()
        }
        fun updatePose(y: Double, p: Double, r: Double, dir: String, mouth: Boolean = false) {
            yaw = y; pitch = p; roll = r; direction = dir; mouthOpen = mouth
            postInvalidateOnAnimation()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val vw = width.toFloat();  val vh = height.toFloat()
            val iw = imgWidth;         val ih = imgHeight
            if (iw <= 0 || ih <= 0) return

            // مقياس FILL_CENTER يطابق PreviewView تماماً
            val scale = max(vw / iw, vh / ih)
            val xOff  = (vw - iw * scale) / 2f
            val yOff  = (vh - ih * scale) / 2f

            // رسم النقاط ومربع الإحاطة
            landmarks?.let { list ->
                var minX =  Float.MAX_VALUE;   var minY =  Float.MAX_VALUE
                var maxX = -Float.MAX_VALUE;   var maxY = -Float.MAX_VALUE
                for (lm in list) {
                    val x = lm.x() * iw * scale + xOff
                    val y = lm.y() * ih * scale + yOff
                    if (x < minX) minX = x;  if (y < minY) minY = y
                    if (x > maxX) maxX = x;  if (y > maxY) maxY = y
                    canvas.drawCircle(x, y, 3.5f, dotPaint)
                }
                // لون مربع الإحاطة يتغير عند فتح الفم
                boxPaint.color = if (mouthOpen) Color.YELLOW else Color.CYAN
                val pad = 22f
                canvas.drawRoundRect(minX-pad, minY-pad, maxX+pad, maxY+pad, 18f, 18f, boxPaint)
            }

            // اتجاه الرأس
            dirPaint.color = when (direction) {
                "left", "right" -> Color.CYAN
                "up",   "down"  -> Color.MAGENTA
                "calibrating"   -> Color.YELLOW
                else            -> Color.GREEN
            }
            canvas.drawText(direction.uppercase(), 20f, 76f, dirPaint)

            // وميض مؤقت للإيماءات
            val now    = System.currentTimeMillis()
            var flashY = 140f

            if (now < blinkFlashEnd) {
                dirPaint.color = Color.WHITE
                canvas.drawText("BLINK ✓", 20f, flashY, dirPaint)
                flashY += 70f
                postInvalidateOnAnimation()
            }
            if (now < shakeFlashEnd) {
                dirPaint.color = Color.rgb(255, 165, 0)  // برتقالي
                canvas.drawText("SHAKE ✓", 20f, flashY, dirPaint)
                postInvalidateOnAnimation()
            }

            // لوحة المعلومات
            val ix = 20f;  val iy = vh - 250f
            canvas.drawRoundRect(ix-10f, iy-44f, 390f, iy+220f, 14f, 14f, textBgPaint)
            canvas.drawText("Yaw  : %+.1f°".format(yaw),   ix, iy,        textPaint)
            canvas.drawText("Pitch: %+.1f°".format(pitch), ix, iy + 46f,  textPaint)
            canvas.drawText("Roll : %+.1f°".format(roll),  ix, iy + 92f,  textPaint)
            canvas.drawText("Delay: ${latency}ms",         ix, iy + 142f, textPaint)
            canvas.drawText("FPS  : $fps",                 ix, iy + 188f, textPaint)
        }
    }
}
