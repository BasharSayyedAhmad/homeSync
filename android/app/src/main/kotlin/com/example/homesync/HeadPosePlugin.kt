package com.example.homesync

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.*
import android.os.Handler
import android.os.HandlerThread
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
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.sqrt

class HeadPosePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL_NAME = "head_pose_channel"
        private const val EVENT_CHANNEL_NAME = "head_pose_events"
        private const val TAG = "HeadPosePlugin"
        private const val CAMERA_PERMISSION_REQUEST_CODE = 1001
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var cameraExecutor: ExecutorService? = null
    private var analysisUseCase: ImageAnalysis? = null
    private var faceLandmarker: FaceLandmarker? = null
    private var backgroundHandlerThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    // Kalman filters
    private var yawKalman = Kalman1D(q = 0.05, r = 0.8)
    private var pitchKalman = Kalman1D(q = 0.05, r = 0.8)
    private var rollKalman = Kalman1D(q = 0.03, r = 1.2)

    private var lastDirection: String = "center"
    private val yawLeftEnter = -15.0; private val yawLeftExit = -7.0
    private val yawRightEnter = 15.0; private val yawRightExit = 7.0
    private val pitchUpEnter = -13.0; private val pitchUpExit = -6.0
    private val pitchDownEnter = 13.0; private val pitchDownExit = 6.0
    private val centerYawThreshold = 10.0; private val centerPitchThreshold = 10.0

    private var previewView: PreviewView? = null
    private var overlayView: FaceOverlayView? = null
    private var overlayContainer: FrameLayout? = null

    // Calibration (Trimmed Mean)
    private var isCalibrating = false
    private val maxCalibrationSamples = 40
    private val calibrationSamples = mutableListOf<Pair<Double, Double>>()
    private var baselineYaw = 0.0
    private var baselinePitch = 0.0

    // Frame throttling
    private var frameCounter = 0
    private val frameSkipRate = 2

    // Performance counters
    private var fpsStartTime = 0L
    private var fpsCounter = 0
    private var actualFps = 0

    // ---------- Flutter lifecycle ----------
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    // ---------- Method Channel ----------
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> startHeadPose(result)
            "stop" -> {
                stopHeadPose()
                result.success(null)
            }
            "calibrate" -> {
                startCalibration()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
    override fun onCancel(arguments: Any?) { eventSink = null }

    // ---------- Core Logic ----------
    private fun startHeadPose(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.error("NO_ACTIVITY", "Activity is null", null)
            return
        }
        val ctx = context ?: run {
            result.error("NO_CONTEXT", "Context is null", null)
            return
        }

        // ✅ طلب الصلاحية إذا لم تكن موجودة
        if (ContextCompat.checkSelfPermission(act, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            // نطلب الصلاحية عبر الـ Activity
            ActivityCompat.requestPermissions(act,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST_CODE
            )
            // ننتظر الرد في onRequestPermissionsResult – لكن لا يمكننا ذلك مباشرة في plugin.
            // لذا نعيد خطأ مؤقتاً، ويجب على Flutter إعادة المحاولة بعد منح الصلاحية.
            result.error("PERMISSION_REQUIRED", "Camera permission not granted. Please grant it and call start again.", null)
            return
        }

        // الصلاحية موجودة → متابعة التشغيل
        result.success(null)  // ننجز الـ method call بنجاح
        executeStart(ctx, act)
    }

    private fun executeStart(ctx: Context, act: Activity) {
        if (cameraExecutor == null) {
            cameraExecutor = Executors.newSingleThreadExecutor()
        }
        if (backgroundHandlerThread == null) {
            backgroundHandlerThread = HandlerThread("HeadPoseBackground").apply { start() }
            backgroundHandler = Handler(backgroundHandlerThread!!.looper)
        }
        if (faceLandmarker == null) {
            initFaceLandmarker(ctx)
        }

        val prefs = ctx.getSharedPreferences("HeadPosePrefs", Context.MODE_PRIVATE)
        baselineYaw = prefs.getFloat("baseline_yaw", 0.0f).toDouble()
        baselinePitch = prefs.getFloat("baseline_pitch", 0.0f).toDouble()

        yawKalman = Kalman1D(q = 0.05, r = 0.8, x = baselineYaw)
        pitchKalman = Kalman1D(q = 0.05, r = 0.8, x = baselinePitch)

        val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()
            bindCameraUseCases(act)
        }, ContextCompat.getMainExecutor(ctx))

        fpsStartTime = System.currentTimeMillis()
    }

    private fun stopHeadPose() {
        cameraProvider?.unbindAll()
        cameraExecutor?.shutdown()
        cameraExecutor = null
        faceLandmarker?.close()
        faceLandmarker = null
        backgroundHandlerThread?.quitSafely()
        backgroundHandlerThread = null
        backgroundHandler = null

        lastDirection = "center"
        isCalibrating = false
        calibrationSamples.clear()
        frameCounter = 0

        yawKalman = Kalman1D()
        pitchKalman = Kalman1D()
        rollKalman = Kalman1D()

        val act = activity
        val container = overlayContainer
        if (act != null && container != null) {
            Handler(Looper.getMainLooper()).post {
                val root = act.findViewById<ViewGroup>(android.R.id.content)
                root.removeView(container)
            }
        }
        overlayContainer = null
        previewView = null
        overlayView = null
    }

    private fun initFaceLandmarker(ctx: Context) {
        try {
            val baseOptionsBuilder = BaseOptions.builder().setModelAssetPath("face_landmarker.task")
            try {
                baseOptionsBuilder.setDelegate(Delegate.GPU)
                val options = buildOptions(baseOptionsBuilder.build())
                faceLandmarker = FaceLandmarker.createFromOptions(ctx, options)
                Log.d(TAG, "FaceLandmarker on GPU")
            } catch (gpuEx: Exception) {
                Log.w(TAG, "GPU failed, fallback to CPU", gpuEx)
                baseOptionsBuilder.setDelegate(Delegate.CPU)
                val options = buildOptions(baseOptionsBuilder.build())
                faceLandmarker = FaceLandmarker.createFromOptions(ctx, options)
            }
        } catch (e: Exception) {
            Log.e(TAG, "FaceLandmarker init failed", e)
        }
    }

    private fun buildOptions(baseOptions: BaseOptions): FaceLandmarker.FaceLandmarkerOptions {
        return FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumFaces(1)
            .setOutputFacialTransformationMatrixes(true)
            .setResultListener { result: FaceLandmarkerResult, _: MPImage ->
                handleFaceLandmarkerResult(result)
            }
            .build()
    }

    private fun bindCameraUseCases(activity: Activity) {
        val cameraProvider = cameraProvider ?: return
        cameraProvider.unbindAll()

        if (previewView == null || overlayView == null || overlayContainer == null) {
            val root = activity.findViewById<ViewGroup>(android.R.id.content)
            val container = FrameLayout(activity).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
            val preview = PreviewView(activity).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
                scaleType = PreviewView.ScaleType.FILL_CENTER
            }
            val overlay = FaceOverlayView(activity).apply {
                layoutParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            }
            container.addView(preview)
            container.addView(overlay)
            Handler(Looper.getMainLooper()).post { root.addView(container) }
            previewView = preview
            overlayView = overlay
            overlayContainer = container
        }

        val previewUseCase = Preview.Builder()
            .setTargetResolution(android.util.Size(640, 480))
            .build()

        val analysis = ImageAnalysis.Builder()
            .setTargetResolution(android.util.Size(640, 480))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()

        analysis.setAnalyzer(cameraExecutor!!) { imageProxy ->
            frameCounter++
            if (frameCounter % frameSkipRate == 0) {
                processImageProxy(imageProxy)
            } else {
                imageProxy.close()
            }
        }

        val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA
        try {
            val lifecycleOwner = activity as? LifecycleOwner
                ?: throw IllegalStateException("Activity is not LifecycleOwner")
            cameraProvider.bindToLifecycle(lifecycleOwner, cameraSelector, previewUseCase, analysis)
            previewUseCase.setSurfaceProvider(previewView!!.surfaceProvider)
        } catch (e: Exception) {
            Log.e(TAG, "Bind failed", e)
        }
        analysisUseCase = analysis
    }


    private fun processImageProxy(imageProxy: ImageProxy) {
        val landmarker = faceLandmarker ?: run { imageProxy.close(); return }
        val startTime = System.currentTimeMillis()
        try {
            val bitmap = toBitmap(imageProxy) ?: run { imageProxy.close(); return }
            overlayView?.setImageDimensions(bitmap.width, bitmap.height)
            val mpImage = BitmapImageBuilder(bitmap).build()
            landmarker.detectAsync(mpImage, System.nanoTime() / 1000)

            val latency = System.currentTimeMillis() - startTime
            overlayView?.updateLatency(latency)

            fpsCounter++
            val now = System.currentTimeMillis()
            if (now - fpsStartTime >= 1000) {
                actualFps = fpsCounter
                fpsCounter = 0
                fpsStartTime = now
                overlayView?.updateFps(actualFps)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Process error", e)
        } finally {
            imageProxy.close()
        }
    }

    private fun toBitmap(imageProxy: ImageProxy): Bitmap? {
        return try {
            val yBuffer = imageProxy.planes[0].buffer
            val uBuffer = imageProxy.planes[1].buffer
            val vBuffer = imageProxy.planes[2].buffer
            val ySize = yBuffer.remaining()
            val uSize = uBuffer.remaining()
            val vSize = vBuffer.remaining()
            val nv21 = ByteArray(ySize + uSize + vSize)
            yBuffer.get(nv21, 0, ySize)
            vBuffer.get(nv21, ySize, vSize)
            uBuffer.get(nv21, ySize + vSize, uSize)

            val yuvImage = YuvImage(nv21, ImageFormat.NV21, imageProxy.width, imageProxy.height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, imageProxy.width, imageProxy.height), 90, out)
            val raw = BitmapFactory.decodeByteArray(out.toByteArray(), 0, out.size())
            val matrix = Matrix().apply {
                postRotate(imageProxy.imageInfo.rotationDegrees.toFloat())
                postScale(-1f, 1f) // mirror for front camera
            }
            Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true)
        } catch (e: Exception) {
            Log.e(TAG, "toBitmap error", e)
            null
        }
    }

    private fun handleFaceLandmarkerResult(result: FaceLandmarkerResult) {
        try {
            val faces = result.faceLandmarks()
            if (faces.isNotEmpty()) overlayView?.updateLandmarks(faces[0])
            else overlayView?.clearLandmarks()
        } catch (_: Exception) {}

        val matricesOpt = result.facialTransformationMatrixes()
        if (!matricesOpt.isPresent || matricesOpt.get().isEmpty()) {
            sendHeadPose(0.0, 0.0, 0.0, "center")
            return
        }
        val data = matricesOpt.get()[0]
        if (data.size < 16) {
            sendHeadPose(0.0, 0.0, 0.0, "center")
            return
        }
        val m00 = data[0]; val m10 = data[4]; val m20 = data[8]; val m21 = data[9]; val m22 = data[10]
        val yaw = atan2(-m20.toDouble(), sqrt((m00 * m00 + m10 * m10).toDouble()))
        val pitch = atan2(m10.toDouble(), m00.toDouble())
        val roll = atan2(m21.toDouble(), m22.toDouble())
        val yawDeg = Math.toDegrees(yaw)
        val pitchDeg = Math.toDegrees(pitch)
        val rollDeg = Math.toDegrees(roll)

        val filteredYaw = yawKalman.update(yawDeg)
        val filteredPitch = pitchKalman.update(pitchDeg)
        val filteredRoll = rollKalman.update(rollDeg)

        if (isCalibrating) {
            calibrationSamples.add(Pair(filteredYaw, filteredPitch))
            overlayView?.updatePose(filteredYaw, filteredPitch, filteredRoll, "calibrating")
            if (calibrationSamples.size >= maxCalibrationSamples) {
                val sortedYaw = calibrationSamples.map { it.first }.sorted()
                val sortedPitch = calibrationSamples.map { it.second }.sorted()
                val trimCount = (maxCalibrationSamples * 0.2).toInt()
                baselineYaw = sortedYaw.drop(trimCount).dropLast(trimCount).average()
                baselinePitch = sortedPitch.drop(trimCount).dropLast(trimCount).average()
                context?.getSharedPreferences("HeadPosePrefs", Context.MODE_PRIVATE)?.edit()?.apply {
                    putFloat("baseline_yaw", baselineYaw.toFloat())
                    putFloat("baseline_pitch", baselinePitch.toFloat())
                    apply()
                }
                isCalibrating = false
                calibrationSamples.clear()
                sendHeadPose(0.0, 0.0, filteredRoll, "center")
            }
            return
        }

        val adjYaw = filteredYaw - baselineYaw
        val adjPitch = filteredPitch - baselinePitch
        val direction = classifyDirection(adjYaw, adjPitch)
        overlayView?.updatePose(adjYaw, adjPitch, filteredRoll, direction)
        sendHeadPose(adjYaw, adjPitch, filteredRoll, direction)
    }

    private fun classifyDirection(yawDeg: Double, pitchDeg: Double): String {
        when (lastDirection) {
            "center" -> {
                when {
                    yawDeg <= yawLeftEnter -> lastDirection = "left"
                    yawDeg >= yawRightEnter -> lastDirection = "right"
                    pitchDeg <= pitchUpEnter -> lastDirection = "up"
                    pitchDeg >= pitchDownEnter -> lastDirection = "down"
                }
                return lastDirection
            }
            "left" -> if (yawDeg >= yawLeftExit) lastDirection = decideFromCenter(yawDeg, pitchDeg)
            "right" -> if (yawDeg <= yawRightExit) lastDirection = decideFromCenter(yawDeg, pitchDeg)
            "up" -> if (pitchDeg >= pitchUpExit) lastDirection = decideFromCenter(yawDeg, pitchDeg)
            "down" -> if (pitchDeg <= pitchDownExit) lastDirection = decideFromCenter(yawDeg, pitchDeg)
        }
        return lastDirection
    }

    private fun decideFromCenter(yawDeg: Double, pitchDeg: Double): String {
        if (abs(yawDeg) <= centerYawThreshold && abs(pitchDeg) <= centerPitchThreshold) return "center"
        return if (abs(yawDeg) > abs(pitchDeg)) {
            if (yawDeg < 0) "left" else "right"
        } else {
            if (pitchDeg < 0) "up" else "down"
        }
    }

    private fun sendHeadPose(yaw: Double, pitch: Double, roll: Double, direction: String) {
        eventSink?.let { sink ->
            Handler(Looper.getMainLooper()).post {
                sink.success(mapOf("yaw" to yaw, "pitch" to pitch, "roll" to roll, "direction" to direction))
            }
        }
    }

    private fun startCalibration() {
        isCalibrating = true
        calibrationSamples.clear()
    }

    // ---------- Kalman 1D ----------
    class Kalman1D(
        private var q: Double = 0.02,
        private var r: Double = 1.0,
        private var x: Double = 0.0,
        private var p: Double = 1.0,
        private var k: Double = 0.0
    ) {
        fun update(measurement: Double): Double {
            p += q
            k = p / (p + r)
            x += k * (measurement - x)
            p *= (1 - k)
            return x
        }
    }

    // ---------- FaceOverlayView (as before, but fixed scaling) ----------
    private class FaceOverlayView(context: Context) : View(context) {
        private val dotPaint = Paint().apply { color = Color.GREEN; style = Paint.Style.FILL; isAntiAlias = true }
        private val boxPaint = Paint().apply { color = Color.CYAN; style = Paint.Style.STROKE; strokeWidth = 4f; isAntiAlias = true }
        private val textBgPaint = Paint().apply { color = Color.argb(140, 0, 0, 0); style = Paint.Style.FILL }
        private val textPaint = Paint().apply { color = Color.WHITE; textSize = 34f; isAntiAlias = true; typeface = Typeface.MONOSPACE }
        private val dirPaint = Paint().apply { color = Color.YELLOW; textSize = 52f; isFakeBoldText = true; isAntiAlias = true; typeface = Typeface.DEFAULT_BOLD }
        private var landmarks: List<NormalizedLandmark>? = null
        private var yaw = 0.0; private var pitch = 0.0; private var roll = 0.0
        private var direction = "center"
        private var imgWidth = 0; private var imgHeight = 0
        private var currentLatency = 0L; private var currentFps = 0

        fun setImageDimensions(w: Int, h: Int) { imgWidth = w; imgHeight = h }
        fun updateLandmarks(list: List<NormalizedLandmark>) { landmarks = list; postInvalidateOnAnimation() }
        fun clearLandmarks() { landmarks = null; postInvalidateOnAnimation() }
        fun updatePose(yaw: Double, pitch: Double, roll: Double, direction: String) {
            this.yaw = yaw; this.pitch = pitch; this.roll = roll; this.direction = direction
            postInvalidateOnAnimation()
        }
        fun updateLatency(ms: Long) { currentLatency = ms }
        fun updateFps(fps: Int) { currentFps = fps }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (imgWidth <= 0 || imgHeight <= 0) return

            val viewRatio = w / h
            val imgRatio = imgWidth.toFloat() / imgHeight.toFloat()
            val scale = if (viewRatio > imgRatio) w / imgWidth.toFloat() else h / imgHeight.toFloat()
            val xOffset = if (viewRatio > imgRatio) 0f else (w - imgWidth * scale) / 2f
            val yOffset = if (viewRatio > imgRatio) (h - imgHeight * scale) / 2f else 0f

            landmarks?.let { list ->
                var minX = Float.MAX_VALUE; var minY = Float.MAX_VALUE
                var maxX = Float.MIN_VALUE; var maxY = Float.MIN_VALUE
                for (lm in list) {
                    val x = lm.x() * imgWidth.toFloat() * scale + xOffset
                    val y = lm.y() * imgHeight.toFloat() * scale + yOffset
                    if (x < minX) minX = x; if (y < minY) minY = y
                    if (x > maxX) maxX = x; if (y > maxY) maxY = y
                    canvas.drawCircle(x, y, 3.5f, dotPaint)
                }
                val pad = 20f
                canvas.drawRoundRect(minX - pad, minY - pad, maxX + pad, maxY + pad, 16f, 16f, boxPaint)
            }

            val infoX = 20f
            val infoY = h - 240f
            canvas.drawRoundRect(infoX - 10f, infoY - 40f, 380f, infoY + 210f, 12f, 12f, textBgPaint)
            canvas.drawText("Yaw  : %+.1f°".format(yaw), infoX, infoY, textPaint)
            canvas.drawText("Pitch: %+.1f°".format(pitch), infoX, infoY + 44f, textPaint)
            canvas.drawText("Roll : %+.1f°".format(roll), infoX, infoY + 88f, textPaint)
            canvas.drawText("Delay: ${currentLatency}ms", infoX, infoY + 135f, textPaint)
            canvas.drawText("Proc  : ${currentFps} FPS", infoX, infoY + 180f, textPaint)

            val dirColor = when (direction) {
                "left", "right" -> Color.CYAN
                "up", "down" -> Color.MAGENTA
                "calibrating" -> Color.YELLOW
                else -> Color.GREEN
            }
            dirPaint.color = dirColor
            canvas.drawText(direction.uppercase(), 20f, 70f, dirPaint)
        }
    }
}