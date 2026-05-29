package com.example.homesync

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
import com.google.mediapipe.framework.image.MPImage
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

// =============================================================================
//  HeadPosePlugin — نسخة Redmi 15 / Helio G81 المحسّنة
//  الإصلاحات الأساسية:
//  1. imageProxy.toBitmap() بدلاً من تحويل YUV يدوي (يصلح Helio G81)
//  2. صيغة pitch الصحيحة رياضياً: atan2(m21, m22) بدلاً من atan2(m10, m00)
//  3. centerPitchThreshold مُصحّحة لمنع الاهتزاز
//  4. مقياس الـ overlay يطابق PreviewView.FILL_CENTER بدقة
//  5. @Volatile على حقول الـ overlay للسلامة بين الخيوط
//  6. mainHandler كـ field دائم — بدلاً من إنشاء Handler جديد كل إطار
// =============================================================================

class HeadPosePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL_NAME        = "head_pose_channel"
        private const val EVENT_CHANNEL_NAME         = "head_pose_events"
        private const val TAG                        = "HeadPosePlugin"
        private const val CAMERA_PERMISSION_CODE     = 1001
    }

    // ── Flutter / Android context ──────────────────────────────────────────────
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel:  EventChannel
    private var context:   Context?  = null
    private var activity:  Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    // ── Camera ─────────────────────────────────────────────────────────────────
    private var cameraProvider:  ProcessCameraProvider? = null
    private var cameraExecutor:  ExecutorService?       = null
    private var faceLandmarker:  FaceLandmarker?        = null

    // ── Handler دائم على الـ Main Thread (يُنشأ مرة واحدة فقط) ───────────────
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── فلاتر كالمان ──────────────────────────────────────────────────────────
    // q = ضجيج العملية  (أعلى = أسرع استجابة، أقل نعومة)
    // r = ضجيج القياس   (أعلى = أكثر نعومة، أبطأ استجابة)
    private var yawKalman   = Kalman1D(q = 0.05, r = 0.8)
    private var pitchKalman = Kalman1D(q = 0.05, r = 0.8)
    private var rollKalman  = Kalman1D(q = 0.03, r = 1.2)

    // ── منطق الاتجاهات (Hysteresis) ───────────────────────────────────────────
    private var lastDirection = "center"

    // يمين / يسار
    private val yawLeftEnter  = -15.0;  private val yawLeftExit  = -7.0
    private val yawRightEnter =  15.0;  private val yawRightExit =  7.0

    // أعلى / أسفل
    private val pitchUpEnter   = -8.0;  private val pitchUpExit   = -4.0
    private val pitchDownEnter =  8.0;  private val pitchDownExit =  4.0

    // حدود منطقة المركز — يجب أن تكون بين Exit و Enter لكل محور
    //   Yaw  : Exit=7.0  < centerYaw=10.0   < Enter=15.0  ✓
    //   Pitch: Exit=4.0  < centerPitch=5.5  < Enter=8.0   ✓
    private val centerYawThreshold   = 10.0
    private val centerPitchThreshold =  5.5   // كانت 10.0 → خطأ كان يسبب اهتزازاً

    // ── واجهة المعاينة ─────────────────────────────────────────────────────────
    private var previewView:      PreviewView?    = null
    private var overlayView:      FaceOverlayView? = null
    private var overlayContainer: FrameLayout?    = null

    // ── المعايرة (Trimmed Mean) ────────────────────────────────────────────────
    private var isCalibrating          = false
    private val maxCalibrationSamples  = 40
    private val calibrationSamples     = mutableListOf<Pair<Double, Double>>()
    private var baselineYaw            = 0.0
    private var baselinePitch          = 0.0

    // ── كشف الغمز (Blink Detection) ───────────────────────────────────────────
    // غيّر هذا المتغير لتشغيل/إيقاف الكشف دون لمس أي شيء آخر
    var enableBlinkDetection = true

    // EAR = نسبة المسافة العمودية / الأفقية للعين
    // أقل من earClose → العين مغلقة | أعلى من earOpen → العين مفتوحة (hysteresis)
    private val earClose         = 0.20
    private val earOpen          = 0.25

    // الغمزة الصحيحة تحتاج إغلاقاً لمدة إطارين متتاليين على الأقل (~130ms @ 15fps)
    // هذا يمنع الضجيج العارض من التشغيل الخاطئ
    private val minClosedFrames  = 2
    private var closedFrameCount = 0
    private var eyesWereClosed   = false
    private var lastBlinkTime    = 0L
    private val blinkDebounceMs  = 1500L   // 1.5 ثانية بين كل غمزة وأخرى

    // ── تقليص الإطارات ────────────────────────────────────────────────────────
    private var frameCounter   = 0
    private val frameSkipRate  = 2   // يعالج 1 من كل 2 إطار ≈ 15 FPS

    // ── عدادات الأداء ─────────────────────────────────────────────────────────
    private var fpsStartTime = 0L
    private var fpsCounter   = 0
    private var actualFps    = 0

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

    override fun onAttachedToActivity(binding: ActivityPluginBinding)   { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges()               { activity = null }
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) { activity = b.activity }
    override fun onDetachedFromActivity()                               { activity = null }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null }

    // ==========================================================================
    // Method Channel
    // ==========================================================================

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start"     -> startHeadPose(result)
            "stop"      -> { stopHeadPose();      result.success(null) }
            "calibrate"     -> { startCalibration();          result.success(null) }
            "enableBlink"   -> { enableBlinkDetection = true;  result.success(null) }
            "disableBlink"  -> { enableBlinkDetection = false; result.success(null) }
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
                act, arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_CODE)
            result.error("PERMISSION_REQUIRED",
                "Camera permission not granted — grant it and call start() again.", null)
            return
        }

        result.success(null)
        executeStart(ctx, act)
    }

    private fun executeStart(ctx: Context, act: Activity) {
        if (cameraExecutor == null) {
            cameraExecutor = Executors.newSingleThreadExecutor()
        }
        if (faceLandmarker == null) {
            initFaceLandmarker(ctx)
        }

        // استرجاع نقطة الاتزان المحفوظة لراحة المستخدم عند إعادة التشغيل
        val prefs = ctx.getSharedPreferences("HeadPosePrefs", Context.MODE_PRIVATE)
        baselineYaw   = prefs.getFloat("baseline_yaw",   0f).toDouble()
        baselinePitch = prefs.getFloat("baseline_pitch",  0f).toDouble()

        // تهيئة الفلاتر بالقيمة المحفوظة لتجنب الارتعاش عند البداية
        yawKalman   = Kalman1D(q = 0.05, r = 0.8, x = baselineYaw)
        pitchKalman = Kalman1D(q = 0.05, r = 0.8, x = baselinePitch)
        rollKalman  = Kalman1D(q = 0.03, r = 1.2)

        fpsStartTime = System.currentTimeMillis()

        val future = ProcessCameraProvider.getInstance(ctx)
        future.addListener({
            cameraProvider = future.get()
            bindCameraUseCases(act)
        }, ContextCompat.getMainExecutor(ctx))
    }

    private fun stopHeadPose() {
        cameraProvider?.unbindAll()
        cameraExecutor?.shutdown()
        cameraExecutor = null

        faceLandmarker?.close()
        faceLandmarker = null

        lastDirection = "center"
        isCalibrating = false
        calibrationSamples.clear()
        frameCounter = 0

        yawKalman   = Kalman1D()
        pitchKalman = Kalman1D()
        rollKalman  = Kalman1D()

        val act = activity; val container = overlayContainer
        if (act != null && container != null) {
            mainHandler.post {
                act.findViewById<ViewGroup>(android.R.id.content).removeView(container)
            }
        }
        overlayContainer = null
        previewView      = null
        overlayView      = null
    }

    // ==========================================================================
    // FaceLandmarker — GPU أولاً مع تراجع آمن إلى CPU
    // ==========================================================================

    private fun initFaceLandmarker(ctx: Context) {
        try {
            val baseBuilder = BaseOptions.builder().setModelAssetPath("face_landmarker.task")
            try {
                baseBuilder.setDelegate(Delegate.GPU)
                faceLandmarker = FaceLandmarker.createFromOptions(ctx, buildOptions(baseBuilder.build()))
                Log.d(TAG, "FaceLandmarker → GPU ✓")
            } catch (gpuEx: Exception) {
                Log.w(TAG, "GPU delegate فشل — تراجع إلى CPU", gpuEx)
                baseBuilder.setDelegate(Delegate.CPU)
                faceLandmarker = FaceLandmarker.createFromOptions(ctx, buildOptions(baseBuilder.build()))
                Log.d(TAG, "FaceLandmarker → CPU ✓")
            }
        } catch (e: Exception) {
            Log.e(TAG, "FشGLandmarker: فشل كلي في التهيئة", e)
        }
    }

    private fun buildOptions(baseOptions: BaseOptions): FaceLandmarker.FaceLandmarkerOptions =
        FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumFaces(1)
            .setMinFaceDetectionConfidence(0.5f)   // تحسين ثبات الكشف
            .setMinFacePresenceConfidence(0.5f)    // تحسين ثبات التتبع
            .setMinTrackingConfidence(0.5f)        // تحسين استمرارية التتبع
            .setOutputFacialTransformationMatrixes(true)
            .setResultListener { result, _ -> handleFaceLandmarkerResult(result) }
            .build()

    // ==========================================================================
    // ربط الكاميرا
    // ==========================================================================

    private fun bindCameraUseCases(activity: Activity) {
        val provider = cameraProvider ?: return
        provider.unbindAll()

        if (previewView == null) {
            val root = activity.findViewById<ViewGroup>(android.R.id.content)

            val container = FrameLayout(activity).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT)
            }
            val preview = PreviewView(activity).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT)
                scaleType = PreviewView.ScaleType.FILL_CENTER
            }
            val overlay = FaceOverlayView(activity).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT)
            }

            container.addView(preview)
            container.addView(overlay)
            mainHandler.post { root.addView(container) }

            previewView      = preview
            overlayView      = overlay
            overlayContainer = container
        }

        val targetSize = android.util.Size(640, 480)

        val previewUseCase = Preview.Builder()
            .setTargetResolution(targetSize)
            .build()

        val analysisUseCase = ImageAnalysis.Builder()
            .setTargetResolution(targetSize)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { analysis ->
                analysis.setAnalyzer(cameraExecutor!!) { imageProxy ->
                    frameCounter++
                    if (frameCounter % frameSkipRate == 0) processImageProxy(imageProxy)
                    else imageProxy.close()
                }
            }

        try {
            val lifecycleOwner = activity as? LifecycleOwner
                ?: throw IllegalStateException("Activity ليس LifecycleOwner")
            provider.bindToLifecycle(lifecycleOwner,
                CameraSelector.DEFAULT_FRONT_CAMERA,
                previewUseCase, analysisUseCase)
            previewUseCase.setSurfaceProvider(previewView!!.surfaceProvider)
        } catch (e: Exception) {
            Log.e(TAG, "فشل ربط الكاميرا", e)
        }
    }

    // ==========================================================================
    // ✅ معالجة الإطار — الإصلاح الرئيسي لـ Helio G81
    // ==========================================================================

    private fun processImageProxy(imageProxy: ImageProxy) {
        val landmarker = faceLandmarker ?: run { imageProxy.close(); return }
        val startTime  = System.currentTimeMillis()
        try {
            // ✅ imageProxy.toBitmap() المدمجة في CameraX تتعامل مع pixelStride بشكل صحيح
            //    وهي متوافقة مع Helio G81 (وكل معالجات Mediatek)
            //    بعكس التحويل اليدوي الذي يفشل عليها
            val rawBitmap = imageProxy.toBitmap()
            val rotDeg    = imageProxy.imageInfo.rotationDegrees.toFloat()

            // تطبيق التدوير الصحيح + عكس الكاميرا الأمامية
            val matrix = Matrix().apply {
                postRotate(rotDeg)      // تصحيح اتجاه الجهاز (portrait/landscape)
                postScale(-1f, 1f)     // عكس أفقي للكاميرا الأمامية
            }
            val bitmap = Bitmap.createBitmap(
                rawBitmap, 0, 0, rawBitmap.width, rawBitmap.height, matrix, true)
            rawBitmap.recycle()  // تحرير الذاكرة فوراً

            // إعلام الـ overlay بأبعاد الصورة الحقيقية بعد التحويل
            overlayView?.setImageDimensions(bitmap.width, bitmap.height)

            landmarker.detectAsync(
                BitmapImageBuilder(bitmap).build(),
                System.nanoTime() / 1000)

            overlayView?.updateLatency(System.currentTimeMillis() - startTime)

            fpsCounter++
            val now = System.currentTimeMillis()
            if (now - fpsStartTime >= 1000L) {
                actualFps    = fpsCounter
                fpsCounter   = 0
                fpsStartTime = now
                overlayView?.updateFps(actualFps)
            }
        } catch (e: Exception) {
            Log.e(TAG, "خطأ في معالجة الإطار", e)
        } finally {
            imageProxy.close()
        }
    }

    // ==========================================================================
    // معالجة نتائج MediaPipe
    // ==========================================================================

    private fun handleFaceLandmarkerResult(result: FaceLandmarkerResult) {
        // تحديث نقاط الوجه على الشاشة
        try {
            val faces = result.faceLandmarks()
            if (faces.isNotEmpty()) {
                overlayView?.updateLandmarks(faces[0])
                // كشف الغمز — رخيص جداً، لا يؤثر على الأداء
                if (enableBlinkDetection) detectBlink(faces[0])
            } else {
                overlayView?.clearLandmarks()
            }
        } catch (_: Exception) {}

        // استخراج زوايا الرأس من مصفوفة التحويل
        val matricesOpt = result.facialTransformationMatrixes()
        if (!matricesOpt.isPresent || matricesOpt.get().isEmpty()) {
            sendHeadPose(0.0, 0.0, 0.0, "center"); return
        }
        val data = matricesOpt.get()[0]
        if (data.size < 16) {
            sendHeadPose(0.0, 0.0, 0.0, "center"); return
        }

        // عناصر المصفوفة 4×4 بترتيب row-major:  data[row*4 + col]
        val m00 = data[0].toDouble()
        val m10 = data[4].toDouble()
        val m20 = data[8].toDouble()
        val m21 = data[9].toDouble()
        val m22 = data[10].toDouble()

        // ── تحليل ZYX Euler الصحيح ──────────────────────────────────────────
        //
        //  rawYaw   = atan2(-m20, √(m00²+m10²)) → دوران محور Y (يمين/يسار)
        //  rawPitch = atan2( m21,  m22)          → دوران محور X (أعلى/أسفل) ← الصيغة الصحيحة
        //  rawRoll  = atan2( m10,  m00)          → دوران محور Z (إمالة الرأس)
        //
        //  ملاحظة: الكود السابق كان يستخدم atan2(m10, m00) للـ pitch
        //           وهي تعطي دوران Z وليس X، لذا كانت أعلى/أسفل تعمل بصورة خاطئة
        // ────────────────────────────────────────────────────────────────────

        val rawYaw   = Math.toDegrees(atan2(-m20, sqrt(m00 * m00 + m10 * m10)))
        val rawPitch = Math.toDegrees(atan2( m21,  m22))   // ✅ دوران X = الإيماء
        val rawRoll  = Math.toDegrees(atan2( m10,  m00))   // دوران Z = الإمالة

        // نعكس إشارة Yaw لأن الصورة المرسلة لـ MediaPipe معكوسة (postScale -1)
        val filteredYaw   = yawKalman.update(-rawYaw)
        val filteredPitch = pitchKalman.update(rawPitch)
        val filteredRoll  = rollKalman.update(rawRoll)

        // ── المعايرة ──────────────────────────────────────────────────────────
        if (isCalibrating) {
            calibrationSamples.add(Pair(filteredYaw, filteredPitch))
            overlayView?.updatePose(filteredYaw, filteredPitch, filteredRoll, "calibrating")

            if (calibrationSamples.size >= maxCalibrationSamples) {
                val trimCount = (maxCalibrationSamples * 0.2).toInt()

                baselineYaw = calibrationSamples.map { it.first }.sorted()
                    .drop(trimCount).dropLast(trimCount).average()
                baselinePitch = calibrationSamples.map { it.second }.sorted()
                    .drop(trimCount).dropLast(trimCount).average()

                context?.getSharedPreferences("HeadPosePrefs", Context.MODE_PRIVATE)
                    ?.edit()
                    ?.putFloat("baseline_yaw",   baselineYaw.toFloat())
                    ?.putFloat("baseline_pitch",  baselinePitch.toFloat())
                    ?.apply()

                isCalibrating = false
                calibrationSamples.clear()
                sendHeadPose(0.0, 0.0, filteredRoll, "center")
            }
            return
        }

        // ── تطبيق نقطة الاتزان وتصنيف الاتجاه ───────────────────────────────
        val adjYaw   = filteredYaw   - baselineYaw
        val adjPitch = filteredPitch - baselinePitch
        val direction = classifyDirection(adjYaw, adjPitch)

        overlayView?.updatePose(adjYaw, adjPitch, filteredRoll, direction)
        sendHeadPose(adjYaw, adjPitch, filteredRoll, direction)
    }

    // ==========================================================================
    // تصنيف الاتجاه مع Hysteresis
    // ==========================================================================

    private fun classifyDirection(yawDeg: Double, pitchDeg: Double): String {
        when (lastDirection) {
            "center" -> {
                when {
                    yawDeg   <= yawLeftEnter   -> lastDirection = "left"
                    yawDeg   >= yawRightEnter  -> lastDirection = "right"
                    pitchDeg <= pitchUpEnter   -> lastDirection = "up"
                    pitchDeg >= pitchDownEnter -> lastDirection = "down"
                }
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
    // إرسال النتيجة إلى Flutter
    // ==========================================================================

    private fun sendHeadPose(yaw: Double, pitch: Double, roll: Double, direction: String) {
        eventSink?.let { sink ->
            mainHandler.post {
                sink.success(mapOf(
                    "yaw"       to yaw,
                    "pitch"     to pitch,
                    "roll"      to roll,
                    "direction" to direction
                ))
            }
        }
    }

    // ==========================================================================
    // كشف الغمز — EAR (Eye Aspect Ratio)
    // ==========================================================================

    /**
     * EAR = مسافة_رأسية / مسافة_أفقية للعين
     *
     * النقاط المستخدمة:
     *   العين اليسرى : 159 (علوي) ، 145 (سفلي) ، 33 (خارج) ، 133 (داخل)
     *   العين اليمنى : 386 (علوي) ، 374 (سفلي) ، 263 (خارج) ، 362 (داخل)
     *
     * التطبيع بالعرض الأفقي يُلغي تأثير المسافة من الكاميرا.
     * الغمزة = إغلاق ثم فتح، مع اشتراط إغلاق لـ minClosedFrames إطارات.
     */
    private fun detectBlink(landmarks: List<NormalizedLandmark>) {
        if (landmarks.size < 387) return  // FaceLandmarker يعطي 478 نقطة

        // ── العين اليسرى ──
        val lv = abs(landmarks[159].y() - landmarks[145].y())  // رأسي
        val lh = abs(landmarks[33].x()  - landmarks[133].x())  // أفقي
        val leftEAR = if (lh > 0.001f) lv / lh else 0f

        // ── العين اليمنى ──
        val rv = abs(landmarks[386].y() - landmarks[374].y())  // رأسي
        val rh = abs(landmarks[263].x()  - landmarks[362].x()) // أفقي
        val rightEAR = if (rh > 0.001f) rv / rh else 0f

        val avgEAR = (leftEAR + rightEAR) / 2.0

        val now = System.currentTimeMillis()

        when {
            // العينان مغلقتان — نحسب الإطارات المتتالية
            avgEAR < earClose -> {
                closedFrameCount++
                if (closedFrameCount >= minClosedFrames) eyesWereClosed = true
            }
            // العينان مفتوحتان بعد إغلاق حقيقي → غمزة مكتملة
            avgEAR > earOpen && eyesWereClosed -> {
                if (now - lastBlinkTime >= blinkDebounceMs) {
                    lastBlinkTime = now
                    sendBlink()
                }
                eyesWereClosed   = false
                closedFrameCount = 0
            }
            // لا إغلاق — إعادة تصفير العداد
            avgEAR > earOpen -> {
                closedFrameCount = 0
            }
        }
    }

    // إرسال حدث الغمزة إلى Flutter عبر نفس الـ EventChannel
    private fun sendBlink() {
        eventSink?.let { sink ->
            mainHandler.post {
                sink.success(mapOf("blink" to true))
            }
        }
    }

    private fun startCalibration() {
        isCalibrating = true
        calibrationSamples.clear()
    }

    // ==========================================================================
    // فلتر كالمان 1D
    // ==========================================================================

    class Kalman1D(
        private var q: Double = 0.02,  // process noise
        private var r: Double = 1.0,   // measurement noise
        private var x: Double = 0.0,   // state estimate
        private var p: Double = 1.0,   // estimate uncertainty
        private var k: Double = 0.0    // Kalman gain
    ) {
        fun update(measurement: Double): Double {
            p += q                          // Predict: uncertainty grows
            k  = p / (p + r)               // Kalman gain
            x += k * (measurement - x)     // Update: blend estimate and measurement
            p *= (1.0 - k)                 // Update: reduce uncertainty
            return x
        }
    }

    // ==========================================================================
    // واجهة عرض نقاط الوجه والمعلومات
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
            color = Color.YELLOW; textSize = 56f; isFakeBoldText = true
            isAntiAlias = true; typeface = Typeface.DEFAULT_BOLD }

        // ✅ @Volatile لضمان رؤية التغييرات من خيط الكاميرا إلى خيط الرسم
        @Volatile private var landmarks: List<NormalizedLandmark>? = null
        @Volatile private var yaw       = 0.0
        @Volatile private var pitch     = 0.0
        @Volatile private var roll      = 0.0
        @Volatile private var direction = "center"
        @Volatile private var imgWidth  = 0
        @Volatile private var imgHeight = 0
        @Volatile private var latency   = 0L
        @Volatile private var fps       = 0

        fun setImageDimensions(w: Int, h: Int)    { imgWidth = w; imgHeight = h }
        fun updateLatency(ms: Long)               { latency = ms }
        fun updateFps(f: Int)                     { fps = f }
        fun clearLandmarks()                      { landmarks = null; postInvalidateOnAnimation() }

        fun updateLandmarks(list: List<NormalizedLandmark>) {
            landmarks = list
            postInvalidateOnAnimation()
        }
        fun updatePose(y: Double, p: Double, r: Double, dir: String) {
            yaw = y; pitch = p; roll = r; direction = dir
            postInvalidateOnAnimation()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val vw = width.toFloat();  val vh = height.toFloat()
            val iw = imgWidth;         val ih = imgHeight
            if (iw <= 0 || ih <= 0) return

            // ✅ مقياس FILL_CENTER (يطابق PreviewView تماماً)
            //    يُكبّر الصورة حتى تملأ أحد البُعدين مع اقتصاص البُعد الآخر
            val scale = max(vw / iw, vh / ih)
            val xOff  = (vw - iw * scale) / 2f
            val yOff  = (vh - ih * scale) / 2f

            // رسم نقاط الوجه ومربع الإحاطة
            landmarks?.let { list ->
                var minX =  Float.MAX_VALUE;   var minY =  Float.MAX_VALUE
                var maxX = -Float.MAX_VALUE;   var maxY = -Float.MAX_VALUE   // ✅ إصلاح: Float.MIN_VALUE > 0

                for (lm in list) {
                    val x = lm.x() * iw * scale + xOff
                    val y = lm.y() * ih * scale + yOff
                    if (x < minX) minX = x;  if (y < minY) minY = y
                    if (x > maxX) maxX = x;  if (y > maxY) maxY = y
                    canvas.drawCircle(x, y, 3.5f, dotPaint)
                }

                val pad = 22f
                canvas.drawRoundRect(
                    minX - pad, minY - pad, maxX + pad, maxY + pad,
                    18f, 18f, boxPaint)
            }

            // لوحة معلومات الزوايا
            val ix = 20f;  val iy = vh - 250f
            canvas.drawRoundRect(ix - 10f, iy - 44f, 390f, iy + 220f, 14f, 14f, textBgPaint)
            canvas.drawText("Yaw  : %+.1f°".format(yaw),   ix, iy,        textPaint)
            canvas.drawText("Pitch: %+.1f°".format(pitch), ix, iy + 46f,  textPaint)
            canvas.drawText("Roll : %+.1f°".format(roll),  ix, iy + 92f,  textPaint)
            canvas.drawText("Delay: ${latency}ms",         ix, iy + 142f, textPaint)
            canvas.drawText("FPS  : $fps",                 ix, iy + 188f, textPaint)

            // عرض الاتجاه بخط كبير
            dirPaint.color = when (direction) {
                "left", "right"  -> Color.CYAN
                "up",   "down"   -> Color.MAGENTA
                "calibrating"    -> Color.YELLOW
                else             -> Color.GREEN
            }
            canvas.drawText(direction.uppercase(), 20f, 76f, dirPaint)
        }
    }
}
