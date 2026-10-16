package org.wikimedia.wikilazycoders.wiki_lazy_coders

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "org.wikimedia.wikilazycoders/camera"
    private val AUTH_CHANNEL = "org.wikimedia.wikilazycoders/auth"

    private var cameraManager: WebmCameraManager? = null
    private var authChannel: MethodChannel? = null
    private var initialIntentData: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val data: Uri? = intent?.data
        if (data != null && data.scheme == "wikilazycoders" && data.host == "oauth") {
            val uriString = data.toString()
            initialIntentData = uriString
            authChannel?.invokeMethod("onOAuthCallback", uriString)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        cameraManager = WebmCameraManager(
            context = applicationContext,
            textureRegistry = flutterEngine.renderer
        )

        authChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTH_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialAuthUri" -> {
                        val uri = initialIntentData
                        initialIntentData = null
                        result.success(uri)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceCapabilities" -> {
                    try {
                        val capabilities = cameraManager?.getDeviceCapabilities() ?: emptyMap()
                        result.success(capabilities)
                    } catch (e: Exception) {
                        result.error("CAPABILITY_ERROR", e.message, null)
                    }
                }

                "getAvailableCameras" -> {
                    try {
                        val cameras = cameraManager?.getAvailableCameras() ?: emptyList()
                        result.success(cameras)
                    } catch (e: Exception) {
                        result.error("CAMERA_LIST_ERROR", e.message, null)
                    }
                }

                "startPreview" -> {
                    val cameraId = call.argument<String>("cameraId")
                    val width = call.argument<Int>("width") ?: 1280
                    val height = call.argument<Int>("height") ?: 720

                    cameraManager?.startPreview(
                        cameraId = cameraId,
                        requestedWidth = width,
                        requestedHeight = height,
                        onSuccess = { data ->
                            Handler(Looper.getMainLooper()).post {
                                result.success(data)
                            }
                        },
                        onError = { error ->
                            Handler(Looper.getMainLooper()).post {
                                result.error("PREVIEW_ERROR", error, null)
                            }
                        }
                    )
                }

                "stopPreview" -> {
                    cameraManager?.stopPreview()
                    result.success(true)
                }

                "startRecording" -> {
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    val width = call.argument<Int>("width") ?: 1280
                    val height = call.argument<Int>("height") ?: 720
                    val fps = call.argument<Int>("fps") ?: 30
                    val bitRate = call.argument<Int>("bitRate") ?: 2500000
                    val videoCodec = call.argument<String>("videoCodec") ?: "VP8"
                    val audioEnabled = call.argument<Boolean>("audioEnabled") ?: true

                    cameraManager?.startRecording(
                        outputFilePath = outputPath,
                        width = width,
                        height = height,
                        fps = fps,
                        bitRate = bitRate,
                        videoCodec = videoCodec,
                        audioEnabled = audioEnabled,
                        onSuccess = {
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        },
                        onError = { error ->
                            Handler(Looper.getMainLooper()).post {
                                result.error("RECORDING_START_ERROR", error, null)
                            }
                        }
                    )
                }

                "stopRecording" -> {
                    cameraManager?.stopRecording(
                        onSuccess = { data ->
                            Handler(Looper.getMainLooper()).post {
                                result.success(data)
                            }
                        },
                        onError = { error ->
                            Handler(Looper.getMainLooper()).post {
                                result.error("RECORDING_STOP_ERROR", error, null)
                            }
                        }
                    )
                }

                "takePhoto" -> {
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    cameraManager?.takePhoto(
                        outputPath = outputPath,
                        onSuccess = { path ->
                            result.success(path)
                        },
                        onError = { error ->
                            result.error("TAKE_PHOTO_ERROR", error, null)
                        }
                    )
                }

                "validateWebm" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val validation = WebmValidator.validate(filePath)
                    result.success(validation.toMap())
                }

                "createSampleWebm" -> {
                    // Generates a verified EBML WebM test sample with genuine EBML header
                    // for unit testing container parsing without hardware camera access
                    val filePath = call.argument<String>("filePath") ?: ""
                    try {
                        val file = File(filePath)
                        file.parentFile?.mkdirs()
                        // Minimal valid EBML WebM header bytes:
                        // EBML Header [0x1A, 0x45, 0xDF, 0xA3]
                        // DocType tag [0x42, 0x82], length 4, "webm"
                        val sampleBytes = byteArrayOf(
                            0x1A.toByte(), 0x45.toByte(), 0xDF.toByte(), 0xA3.toByte(), // EBML ID
                            0x01.toByte(), 0x00.toByte(), 0x00.toByte(), 0x1F.toByte(), // Header size
                            0x42.toByte(), 0x86.toByte(), 0x81.toByte(), 0x01.toByte(), // EBMLVersion = 1
                            0x42.toByte(), 0xF7.toByte(), 0x81.toByte(), 0x01.toByte(), // EBMLReadVersion = 1
                            0x42.toByte(), 0xF2.toByte(), 0x81.toByte(), 0x04.toByte(), // EBMLMaxIDLength = 4
                            0x42.toByte(), 0xF3.toByte(), 0x81.toByte(), 0x08.toByte(), // EBMLMaxSizeLength = 8
                            0x42.toByte(), 0x82.toByte(), 0x84.toByte(),                 // DocType ID + len 4
                            0x77.toByte(), 0x65.toByte(), 0x62.toByte(), 0x6D.toByte(), // "webm"
                            0x42.toByte(), 0x87.toByte(), 0x81.toByte(), 0x02.toByte(), // DocTypeVersion = 2
                            0x42.toByte(), 0x85.toByte(), 0x81.toByte(), 0x02.toByte(), // DocTypeReadVersion = 2
                            0x18.toByte(), 0x53.toByte(), 0x80.toByte(), 0x67.toByte(), // Segment ID
                            0x01.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte()  // Unknown size
                        )
                        FileOutputStream(file).use { fos ->
                            fos.write(sampleBytes)
                        }
                        result.success(mapOf("success" to true, "filePath" to file.absolutePath))
                    } catch (e: Exception) {
                        result.error("SAMPLE_CREATION_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        cameraManager?.release()
        cameraManager = null
        super.onDestroy()
    }
}
