package com.example.homesync

// =============================================================================
//  IrisGazePlugin — تتبع العين المستقل (مفصول عن HeadPosePlugin)
//  Redmi 15C / Helio G81
//
//  يُرسل الاتجاهات: gazeUp | gazeDown | gazeLeft | gazeRight | center
//                   calibrating | noFace
//
//  ⭐ إصلاح مهم: تصحيح إحداثيات القزحية (كانت 468 و 473 مبادلتان)
//     الصحيح:
//       468 = قزحية العين اليسرى → مع حدود العين اليسرى (33, 133, 159, 145)
//       473 = قزحية العين اليمنى → مع حدود العين اليمنى (362, 263, 386, 374)
// =============================================================================

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
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

class IrisGazePlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG            = "IrisGazePlugin"
        private const val METHOD_CHANNEL = "iris_gaze_channel"
        private const val EVENT_CHANNEL  = "iris_gaze_events"

        // ── landmarks القزحية ─────────────────────────────────────────────────
        // ⚠️ 468 = العين اليسرى (تظهر يساراً في الصورة المعكوسة)
        // ⚠️ 473 = العين اليمنى (تظهر يميناً في الصورة المعكوسة)
        private const val LEFT_IRIS  = 468
        private const val RIGHT_IRIS = 473

        // حدود العين اليسرى
        private const val L_OUTER = 33    // ركن خارجي (نحو الأذن اليسرى)
        private const val L_INNER = 133   // ركن داخلي  (نحو الأنف)
        private const val L_TOP   = 159   // حافة عليا
        private const val L_BOT   = 145   // حافة سفلى

        // حدود العين اليمنى
        private const val R_INNER = 362   // ركن داخلي  (نحو الأنف)
        private const val R_OUTER = 263   // ركن خارجي (نحو الأذن اليمنى)
        private const val R_TOP   = 386   // حافة عليا
        private const val R_BOT   = 374   // حافة سفلى

        // ── عتبات الانحراف عن المحايد (بعد المعايرة) ────────────────────────
        private const val THRESHOLD_H    = 0.10f   // يمين / يسار
        private const val THRESHOLD_V_UP = 0.09f   // أعلى  (أصغر قليلاً = أكثر حساسية)
        private const val THRESHOLD_V_DN = 0.11f   // أسفل

        // ── الحد الأدنى لحجم فتحة العين (لتجاهل إطارات العيون المغلقة) ─────
        private const val MIN_SPAN_H = 0.008f
        private const val MIN_SPAN_V = 0.003f

        // ── معايرة ──────────────────────────────────────────────────────────
        private const val CALIB_FRAMES = 40          // إطارات التهيئة
        private const val ADAPTIVE_RATE = 0.02f      // سرعة التكيّف التلقائي

        // ── Hysteresis ───────────────────────────────────────────────────────
        private const val STABLE_REQUIRED = 4        // إطارات متتالية لتأكيد الاتجاه

        // ── كاميرا ───────────────────────────────────────────────────────────
        private const val FRAME_SKIP     = 2         // معالجة إطار كل FRAME_SKIP إطار
        private const val CAMERA_PERM    = 2001
    }

    // ── Flutter ───────────────────────────────────────────────────────────────
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel:  EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Android ───────────────────────────────────────────────────────────────
    private var context:  Context?  = null
    private var activity: Activity? = null

    // ── Camera & MediaPipe ────────────────────────────────────────────────────
    private var cameraProvider: ProcessCameraProvider? = null
    private var cameraExecutor: ExecutorService?       = null
    private var faceLandmarker: FaceLandmarker?        = null

    // ── State ─────────────────────────────────────────────────────────────────
    var isRunning = false
        private set
    private var frameCounter = 0

    // ── Calibration ───────────────────────────────────────────────────────────
    private var calibrated = false
    private val calibH = mutableListOf<Float>()
    private val calibV = mutableListOf<Float>()
    private var neutralH = 0.5f
    private var neutralV = 0.5f

    // ── Hysteresis ────────────────────────────────────────────────────────────
    private var pendingGaze   = "center"
    private var confirmedGaze = "center"
    private var stableCount   = 0

    // ==========================================================================
    // Flutter Plugin Lifecycle
    // ==========================================================================

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        context       = b.applicationContext
        methodChannel = MethodChannel(b.binaryMessenger, METHOD_CHANNEL)
        eventChannel  = EventChannel(b.binaryMessenger, EVENT_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        stopGaze()
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding)                    { activity = b.activity }
    override fun onDetachedFromActivityForConfigChanges()                          {}
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding)  { activity = b.activity }
    override fun onDetachedFromActivity()                                          { activity = null; stopGaze() }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?)        { eventSink = events }
    override fun onCancel(arguments: Any?)                                         { eventSink = null }

    // ==========================================================================
    // Method Channel
    // ==========================================================================

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startIrisGaze"  -> startGaze(result)
            "stopIrisGaze"   -> { stopGaze();          result.success(null) }
            "recalibrate"    -> { resetCalibration();  result.success(null) }
            "isRunning"      -> result.success(isRunning)
            else             -> result.notImplemented()
        }
    }

    // ==========================================================================
    // Start / Stop
    // ==========================================================================

    private fun startGaze(result: MethodChannel.Result) {
        val act = activity ?: run { result.error("NO_ACTIVITY", "Activity is null", null); return }
        val ctx = context  ?: run { result.error("NO_CONTEXT",  "Context is null",  null); return }

        if (ContextCompat.checkSelfPermission(act, Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                act, arrayOf(Manifest.permission.CAMERA), CAMERA_PERM)
            result.error("PERMISSION", "Camera permission required", null)
            return
        }

        if (isRunning) { result.success(null); return }

        cameraExecutor = Executors.newSingleThreadExecutor()
        initFaceLandmarker(ctx)
        resetCalibration()

        ProcessCameraProvider.getInstance(ctx).also { future ->
            future.addListener({
                cameraProvider = future.get()
                bindCamera(act)
                result.success(null)
            }, ContextCompat.getMainExecutor(ctx))
        }
    }

    fun stopGaze() {
        isRunning = false
        cameraProvider?.unbindAll()
        faceLandmarker?.close();  faceLandmarker = null
        cameraExecutor?.shutdown(); cameraExecutor = null
        frameCounter = 0
        pendingGaze = "center"; confirmedGaze = "center"; stableCount = 0
    }

    private fun resetCalibration() {
        calibrated = false
        calibH.clear(); calibV.clear()
        neutralH = 0.5f; neutralV = 0.5f
        pendingGaze = "center"; confirmedGaze = "center"; stableCount = 0
    }

    // ==========================================================================
    // FaceLandmarker — GPU أولاً، CPU احتياطياً
    // ==========================================================================

    private fun initFaceLandmarker(ctx: Context) {
        try {
            val base = BaseOptions.builder().setModelAssetPath("face_landmarker.task")
            try {
                base.setDelegate(Delegate.GPU)
                faceLandmarker = FaceLandmarker.createFromOptions(ctx, buildOptions(base.build()))
                Log.d(TAG, "IrisGaze → GPU ✓")
            } catch (e: Exception) {
                Log.w(TAG, "GPU فشل → CPU", e)
                base.setDelegate(Delegate.CPU)
                faceLandmarker = FaceLandmarker.createFromOptions(ctx, buildOptions(base.build()))
                Log.d(TAG, "IrisGaze → CPU ✓")
            }
        } catch (e: Exception) {
            Log.e(TAG, "FaceLandmarker init failed", e)
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
            // لا نحتاج مصفوفة التحويل هنا — توفير موارد
            .setOutputFacialTransformationMatrixes(false)
            .setResultListener { result, _ -> onFaceResult(result) }
            .build()

    // ==========================================================================
    // Camera Binding
    // ==========================================================================

    private fun bindCamera(activity: Activity) {
        val provider = cameraProvider ?: return

        // ⚠️ مهم: unbindAll يوقف أي كاميرا أخرى (HeadPosePlugin مثلاً)
        provider.unbindAll()

        val analysis = ImageAnalysis.Builder()
            .setTargetResolution(android.util.Size(640, 480))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
            .also { ia ->
                ia.setAnalyzer(cameraExecutor!!) { proxy ->
                    frameCounter++
                    if (frameCounter % FRAME_SKIP == 0) processFrame(proxy)
                    else proxy.close()
                }
            }

        try {
            val lco = activity as? LifecycleOwner
                ?: throw IllegalStateException("Activity ليست LifecycleOwner")
            provider.bindToLifecycle(lco, CameraSelector.DEFAULT_FRONT_CAMERA, analysis)
            isRunning = true
            Log.d(TAG, "IrisGaze Camera ✓")
        } catch (e: Exception) {
            Log.e(TAG, "Camera bind failed", e)
        }
    }

    // ==========================================================================
    // Frame Processing — مطابق لأسلوب HeadPosePlugin لضمان التوافق مع Helio G81
    // ==========================================================================

    private fun processFrame(imageProxy: ImageProxy) {
        val lm = faceLandmarker ?: run { imageProxy.close(); return }
        try {
            // imageProxy.toBitmap() آمن على Helio G81 (يتعامل مع pixelStride تلقائياً)
            val raw   = imageProxy.toBitmap()
            val rotDeg = imageProxy.imageInfo.rotationDegrees.toFloat()
            val matrix = Matrix().apply {
                postRotate(rotDeg)
                postScale(-1f, 1f)   // عكس أفقي للكاميرا الأمامية
            }
            val bmp = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true)
            raw.recycle()

            // LIVE_STREAM: detectAsync لا يحجب الخيط — يُعيد النتيجة عبر resultListener
            lm.detectAsync(BitmapImageBuilder(bmp).build(), System.nanoTime() / 1000)
        } catch (e: Exception) {
            Log.e(TAG, "processFrame error", e)
        } finally {
            imageProxy.close()
        }
    }

    // ==========================================================================
    // نتائج MediaPipe
    // ==========================================================================

    private fun onFaceResult(result: FaceLandmarkerResult) {
        val faces = try { result.faceLandmarks() } catch (_: Exception) { emptyList() }

        if (faces.isEmpty()) {
            sendRaw("noFace")
            return
        }

        val lm = faces[0]
        if (lm.size < 478) { sendRaw("center"); return }

        val normH = calcHorizontal(lm) ?: run { sendRaw("center"); return }
        val normV = calcVertical(lm)   ?: run { sendRaw("center"); return }

        // ── معايرة تلقائية (أول CALIB_FRAMES إطاراً) ─────────────────────
        if (!calibrated) {
            calibH.add(normH)
            calibV.add(normV)
            if (calibH.size >= CALIB_FRAMES) {
                neutralH = trimmedMean(calibH)
                neutralV = trimmedMean(calibV)
                calibrated = true
                calibH.clear(); calibV.clear()
                Log.d(TAG, "Iris calibrated ✓  H=${"%.3f".format(neutralH)}  V=${"%.3f".format(neutralV)}")
            }
            sendRaw("calibrating")
            return
        }

        // ── انحراف عن المحايد ─────────────────────────────────────────────
        //   offsetH > 0 → يمين    offsetH < 0 → يسار
        //   offsetV > 0 → أسفل    offsetV < 0 → أعلى
        val offsetH = normH - neutralH
        val offsetV = normV - neutralV
        val absH    = abs(offsetH)
        val absV    = abs(offsetV)

        // ── تصنيف الاتجاه: العمودي والأفقي بنفس الأولوية ────────────────
        val gaze = when {
            absV >= absH && offsetV < -THRESHOLD_V_UP  -> "gazeUp"
            absV >= absH && offsetV >  THRESHOLD_V_DN  -> "gazeDown"
            absH >  absV && offsetH < -THRESHOLD_H     -> "gazeLeft"
            absH >  absV && offsetH >  THRESHOLD_H     -> "gazeRight"
            else                                       -> "center"
        }

        // ── تحديث محايد تكيفي (Adaptive Neutral) ─────────────────────────
        if (gaze == "center") {
            neutralH = neutralH * (1f - ADAPTIVE_RATE) + normH * ADAPTIVE_RATE
            neutralV = neutralV * (1f - ADAPTIVE_RATE) + normV * ADAPTIVE_RATE
        }

        updateHysteresis(gaze)
    }

    // ==========================================================================
    // حسابات وضعية القزحية
    // ==========================================================================

    /**
     * وضعية القزحية أفقياً (0.0=أقصى يسار ، 0.5=مركز ، 1.0=أقصى يمين)
     *
     * ⭐ الإصلاح المهم:
     *   - 468 (يسار)  مع حدود العين اليسرى  (33, 133)
     *   - 473 (يمين) مع حدود العين اليمنى  (362, 263)
     */
    private fun calcHorizontal(lm: List<NormalizedLandmark>): Float? {
        // العين اليسرى ─────────────────────────────
        val lIrisX  = lm[LEFT_IRIS].x()
        val lOuterX = lm[L_OUTER].x()
        val lInnerX = lm[L_INNER].x()
        val lSpan   = abs(lOuterX - lInnerX)
        val lNorm   = if (lSpan > MIN_SPAN_H)
            (lIrisX - minOf(lOuterX, lInnerX)) / lSpan else null

        // العين اليمنى ─────────────────────────────
        val rIrisX  = lm[RIGHT_IRIS].x()
        val rInnerX = lm[R_INNER].x()
        val rOuterX = lm[R_OUTER].x()
        val rSpan   = abs(rOuterX - rInnerX)
        val rNorm   = if (rSpan > MIN_SPAN_H)
            (rIrisX - minOf(rInnerX, rOuterX)) / rSpan else null

        val vals = listOfNotNull(lNorm, rNorm)
        return if (vals.isEmpty()) null else vals.average().toFloat()
    }

    /**
     * وضعية القزحية عمودياً (0.0=أعلى الفتحة ، 0.5=مركز ، 1.0=أسفل الفتحة)
     *
     * ⭐ الإصلاح المهم:
     *   - 468 (يسار)  مع حدود العين اليسرى  (159_أعلى, 145_أسفل)
     *   - 473 (يمين) مع حدود العين اليمنى  (386_أعلى, 374_أسفل)
     */
    private fun calcVertical(lm: List<NormalizedLandmark>): Float? {
        // العين اليسرى ─────────────────────────────
        val lIrisY = lm[LEFT_IRIS].y()
        val lTopY  = lm[L_TOP].y()
        val lBotY  = lm[L_BOT].y()
        val lSpan  = abs(lBotY - lTopY)
        val lNorm  = if (lSpan > MIN_SPAN_V)
            (lIrisY - minOf(lTopY, lBotY)) / lSpan else null

        // العين اليمنى ─────────────────────────────
        val rIrisY = lm[RIGHT_IRIS].y()
        val rTopY  = lm[R_TOP].y()
        val rBotY  = lm[R_BOT].y()
        val rSpan  = abs(rBotY - rTopY)
        val rNorm  = if (rSpan > MIN_SPAN_V)
            (rIrisY - minOf(rTopY, rBotY)) / rSpan else null

        val vals = listOfNotNull(lNorm, rNorm)
        return if (vals.isEmpty()) null else vals.average().toFloat()
    }

    // ==========================================================================
    // Hysteresis — لمنع التذبذب
    // ==========================================================================

    private fun updateHysteresis(newGaze: String) {
        if (newGaze == pendingGaze) {
            stableCount++
            if (stableCount >= STABLE_REQUIRED && newGaze != confirmedGaze) {
                confirmedGaze = newGaze
                sendRaw(confirmedGaze)
            }
        } else {
            pendingGaze = newGaze
            stableCount = 1
        }
    }

    private fun sendRaw(data: String) {
        mainHandler.post { eventSink?.success(data) }
    }

    // ==========================================================================
    // متوسط مقلّص (يتجاهل أعلى/أدنى 20% للدقة)
    // ==========================================================================

    private fun trimmedMean(values: List<Float>, trim: Float = 0.2f): Float {
        if (values.isEmpty()) return 0.5f
        val sorted = values.sorted()
        val cut    = (values.size * trim).toInt()
        val core   = sorted.drop(cut).dropLast(cut)
        return if (core.isEmpty()) sorted.average().toFloat()
        else core.average().toFloat()
    }
}
