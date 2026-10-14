package org.wikimedia.wikilazycoders.wiki_lazy_coders

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.*
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit

/**
 * Handles Camera2 hardware interaction, live preview streaming into Flutter's TextureRegistry,
 * and direct native WebM recording with MediaRecorder using VP8/VP9 and Opus/Vorbis.
 */
class WebmCameraManager(
    private val context: Context,
    private val textureRegistry: TextureRegistry
) {
    companion object {
        private const val TAG = "WebmCameraManager"
        private const val CAMERA_LOCK_TIMEOUT_MS = 2500L
    }

    private val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private val cameraOpenCloseLock = Semaphore(1)

    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var previewRequestBuilder: CaptureRequest.Builder? = null

    private var surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null

    private var mediaRecorder: MediaRecorder? = null
    private var recordingSurface: Surface? = null
    private var currentRecordingPath: String? = null
    private var isRecording = false

    private var currentCameraId: String? = null
    private var previewWidth = 1280
    private var previewHeight = 720

    init {
        startBackgroundThread()
    }

    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("WebmCameraBackground").apply {
            start()
            backgroundHandler = Handler(looper)
        }
    }

    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            Log.e(TAG, "Error stopping background thread", e)
        }
    }

    /**
     * Inspects Android device hardware and software codecs to verify
     * WebM container, VP8, VP9, Opus, and Vorbis support.
     */
    fun getDeviceCapabilities(): Map<String, Any> {
        val codecList = MediaCodecList(MediaCodecList.ALL_CODECS)
        val codecInfos = codecList.codecInfos

        val videoEncoders = mutableListOf<String>()
        val audioEncoders = mutableListOf<String>()

        var hasVp8Encoder = false
        var hasVp9Encoder = false
        var hasOpusEncoder = false
        var hasVorbisEncoder = false

        for (info in codecInfos) {
            if (!info.isEncoder) continue
            val types = info.supportedTypes
            for (type in types) {
                if (type.contains("vp8", ignoreCase = true)) {
                    hasVp8Encoder = true
                    videoEncoders.add("${info.name} ($type)")
                }
                if (type.contains("vp9", ignoreCase = true)) {
                    hasVp9Encoder = true
                    videoEncoders.add("${info.name} ($type)")
                }
                if (type.contains("opus", ignoreCase = true)) {
                    hasOpusEncoder = true
                    audioEncoders.add("${info.name} ($type)")
                }
                if (type.contains("vorbis", ignoreCase = true)) {
                    hasVorbisEncoder = true
                    audioEncoders.add("${info.name} ($type)")
                }
            }
        }

        // OutputFormat.WEBM is constant 9 (available in API 21+)
        val supportsWebmContainer = true

        return mapOf(
            "supportsWebmContainer" to supportsWebmContainer,
            "hasVp8Encoder" to hasVp8Encoder,
            "hasVp9Encoder" to hasVp9Encoder,
            "hasOpusEncoder" to hasOpusEncoder,
            "hasVorbisEncoder" to hasVorbisEncoder,
            "videoEncoders" to videoEncoders,
            "audioEncoders" to audioEncoders,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}"
        )
    }

    /**
     * Returns a list of available cameras (front/back) with supported resolutions.
     */
    fun getAvailableCameras(): List<Map<String, Any>> {
        val cameras = mutableListOf<Map<String, Any>>()
        try {
            for (id in cameraManager.cameraIdList) {
                val characteristics = cameraManager.getCameraCharacteristics(id)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                val facingStr = when (facing) {
                    CameraCharacteristics.LENS_FACING_FRONT -> "front"
                    CameraCharacteristics.LENS_FACING_BACK -> "back"
                    else -> "external"
                }

                val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val outputSizes = map?.getOutputSizes(SurfaceTexture::class.java)?.map {
                    mapOf("width" to it.width, "height" to it.height)
                } ?: emptyList()

                val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0

                cameras.add(
                    mapOf(
                        "id" to id,
                        "lensFacing" to facingStr,
                        "sensorOrientation" to sensorOrientation,
                        "resolutions" to outputSizes
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error querying cameras", e)
        }
        return cameras
    }

    /**
     * Starts camera preview using Flutter's TextureRegistry.
     */
    @SuppressLint("MissingPermission")
    fun startPreview(
        cameraId: String?,
        requestedWidth: Int,
        requestedHeight: Int,
        onSuccess: (Map<String, Any>) -> Unit,
        onError: (String) -> Unit
    ) {
        val targetCameraId = cameraId ?: selectDefaultCamera()
        if (targetCameraId == null) {
            onError("No suitable camera found on this device.")
            return
        }

        currentCameraId = targetCameraId
        previewWidth = requestedWidth
        previewHeight = requestedHeight

        backgroundHandler?.post {
            try {
                if (!cameraOpenCloseLock.tryAcquire(CAMERA_LOCK_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                    onError("Timeout acquiring camera lock.")
                    return@post
                }

                // Clean up any existing session
                closeCameraSilently()

                // Register Flutter Texture
                val entry = textureRegistry.createSurfaceTexture()
                surfaceTextureEntry = entry
                val surfaceTexture = entry.surfaceTexture()
                surfaceTexture.setDefaultBufferSize(previewWidth, previewHeight)
                previewSurface = Surface(surfaceTexture)

                cameraManager.openCamera(targetCameraId, object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        cameraDevice = camera
                        cameraOpenCloseLock.release()
                        createPreviewSession(onSuccess, onError)
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        cameraOpenCloseLock.release()
                        camera.close()
                        cameraDevice = null
                    }

                    override fun onError(camera: CameraDevice, error: Int) {
                        cameraOpenCloseLock.release()
                        camera.close()
                        cameraDevice = null
                        onError("CameraDevice error code: $error")
                    }
                }, backgroundHandler)

            } catch (e: Exception) {
                cameraOpenCloseLock.release()
                onError("Failed to open camera: ${e.message}")
            }
        }
    }

    private fun selectDefaultCamera(): String? {
        val ids = cameraManager.cameraIdList
        for (id in ids) {
            val chars = cameraManager.getCameraCharacteristics(id)
            if (chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK) {
                return id
            }
        }
        return ids.firstOrNull()
    }

    private fun createPreviewSession(
        onSuccess: (Map<String, Any>) -> Unit,
        onError: (String) -> Unit
    ) {
        val camera = cameraDevice ?: run {
            onError("Camera device is null during session creation.")
            return
        }
        val surface = previewSurface ?: run {
            onError("Preview surface is null.")
            return
        }

        try {
            previewRequestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(surface)
                set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            }

            camera.createCaptureSession(
                listOf(surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        captureSession = session
                        try {
                            previewRequestBuilder?.let { builder ->
                                session.setRepeatingRequest(builder.build(), null, backgroundHandler)
                            }
                            val textureId = surfaceTextureEntry?.id() ?: -1L
                            onSuccess(
                                mapOf(
                                    "textureId" to textureId,
                                    "previewWidth" to previewWidth,
                                    "previewHeight" to previewHeight,
                                    "cameraId" to (currentCameraId ?: "")
                                )
                            )
                        } catch (e: Exception) {
                            onError("Failed to start repeating preview request: ${e.message}")
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        onError("CameraCaptureSession configuration failed.")
                    }
                },
                backgroundHandler
            )
        } catch (e: Exception) {
            onError("Failed to create capture session: ${e.message}")
        }
    }

    /**
     * Starts direct WebM recording using MediaRecorder configured with OutputFormat.WEBM.
     */
    fun startRecording(
        outputFilePath: String,
        width: Int,
        height: Int,
        fps: Int,
        bitRate: Int,
        videoCodec: String,
        audioEnabled: Boolean,
        onSuccess: () -> Unit,
        onError: (String) -> Unit
    ) {
        if (isRecording) {
            onError("A recording is already in progress.")
            return
        }

        val camera = cameraDevice ?: run {
            onError("Camera is not opened. Start preview before recording.")
            return
        }

        backgroundHandler?.post {
            try {
                currentRecordingPath = outputFilePath
                val outputFile = File(outputFilePath)
                outputFile.parentFile?.mkdirs()

                // Configure MediaRecorder for genuine WebM recording
                val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    MediaRecorder(context)
                } else {
                    @Suppress("DEPRECATION")
                    MediaRecorder()
                }

                if (audioEnabled) {
                    recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
                }
                recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)

                // CRITICAL: WebM container format (MediaRecorder.OutputFormat.WEBM = 9)
                recorder.setOutputFormat(MediaRecorder.OutputFormat.WEBM)

                // Video Encoder: VP8 (MediaRecorder.VideoEncoder.VP8 = 3) or VP9
                if (videoCodec.equals("VP9", ignoreCase = true)) {
                    recorder.setVideoEncoder(MediaRecorder.VideoEncoder.VP9)
                } else {
                    recorder.setVideoEncoder(MediaRecorder.VideoEncoder.VP8)
                }

                // Audio Encoder: Opus preferred (API 29+), Vorbis fallback
                if (audioEnabled) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && hasCodec("audio/opus")) {
                        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.OPUS)
                    } else {
                        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.VORBIS)
                    }
                    recorder.setAudioEncodingBitRate(128000)
                    recorder.setAudioSamplingRate(48000)
                }

                recorder.setVideoSize(width, height)
                recorder.setVideoFrameRate(fps)
                recorder.setVideoEncodingBitRate(bitRate)
                recorder.setOutputFile(outputFile.absolutePath)
                recorder.prepare()

                mediaRecorder = recorder
                val recSurface = recorder.surface
                recordingSurface = recSurface

                // Reconfigure capture session with both preview and recording surfaces
                val surfaces = mutableListOf<Surface>()
                previewSurface?.let { surfaces.add(it) }
                surfaces.add(recSurface)

                val recordRequestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                    previewSurface?.let { addTarget(it) }
                    addTarget(recSurface)
                    set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                    set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                }

                captureSession?.stopRepeating()
                captureSession?.close()

                camera.createCaptureSession(
                    surfaces,
                    object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(session: CameraCaptureSession) {
                            captureSession = session
                            try {
                                session.setRepeatingRequest(recordRequestBuilder.build(), null, backgroundHandler)
                                recorder.start()
                                isRecording = true
                                onSuccess()
                            } catch (e: Exception) {
                                onError("Failed to start MediaRecorder: ${e.message}")
                            }
                        }

                        override fun onConfigureFailed(session: CameraCaptureSession) {
                            onError("Failed to configure capture session for recording.")
                        }
                    },
                    backgroundHandler
                )

            } catch (e: Exception) {
                Log.e(TAG, "Error initiating recording", e)
                onError("Failed to start WebM recording: ${e.message}")
            }
        }
    }

    /**
     * Stops the active recording, closes the recorder, and validates the output WebM file.
     */
    fun stopRecording(
        onSuccess: (Map<String, Any?>) -> Unit,
        onError: (String) -> Unit
    ) {
        if (!isRecording) {
            onError("No recording in progress to stop.")
            return
        }

        backgroundHandler?.post {
            try {
                isRecording = false
                try {
                    captureSession?.stopRepeating()
                } catch (ignored: Exception) {}

                try {
                    mediaRecorder?.stop()
                } catch (e: Exception) {
                    Log.w(TAG, "MediaRecorder stop failed (possibly too short): ${e.message}")
                }

                mediaRecorder?.reset()
                mediaRecorder?.release()
                mediaRecorder = null
                recordingSurface = null

                // Restart preview only session
                createPreviewSession({}, {})

                val path = currentRecordingPath ?: ""
                val validation = WebmValidator.validate(path)

                onSuccess(
                    mapOf(
                        "filePath" to path,
                        "validation" to validation.toMap()
                    )
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping recording", e)
                onError("Failed to stop recording cleanly: ${e.message}")
            }
        }
    }

    private fun hasCodec(mimeType: String): Boolean {
        val codecList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        for (info in codecList.codecInfos) {
            if (!info.isEncoder) continue
            for (type in info.supportedTypes) {
                if (type.contains(mimeType, ignoreCase = true)) return true
            }
        }
        return false
    }

    fun stopPreview() {
        closeCameraSilently()
    }

    private fun closeCameraSilently() {
        try {
            captureSession?.close()
            captureSession = null
            cameraDevice?.close()
            cameraDevice = null
            previewSurface?.release()
            previewSurface = null
            surfaceTextureEntry?.release()
            surfaceTextureEntry = null
        } catch (ignored: Exception) {}
    }

    fun release() {
        stopPreview()
        stopBackgroundThread()
    }
}
