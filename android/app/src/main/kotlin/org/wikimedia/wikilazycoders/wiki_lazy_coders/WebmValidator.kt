package org.wikimedia.wikilazycoders.wiki_lazy_coders

import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer

/**
 * Validates genuine WebM files and checks Wikimedia Commons compliance.
 * 
 * Wikimedia Commons Video Requirements:
 * - Container: WebM (EBML header 0x1A 0x45 0xDF 0xA3 with DocType "webm")
 * - Video Codec: VP8 (video/x-vnd.on2.vp8) or VP9 (video/x-vnd.on2.vp9)
 * - Audio Codec: Opus (audio/opus) or Vorbis (audio/vorbis)
 * 
 * Renamed MP4 files (ftyp isom/mp42) or transcoded non-WebM containers
 * fail this verification.
 */
object WebmValidator {
    private const val TAG = "WebmValidator"

    // EBML header element ID: 0x1A45DFA3
    private val EBML_HEADER_BYTES = byteArrayOf(0x1A.toByte(), 0x45.toByte(), 0xDF.toByte(), 0xA3.toByte())

    data class ValidationResult(
        val isValidWebm: Boolean,
        val hasEbmlHeader: Boolean,
        val docType: String,
        val videoMime: String?,
        val audioMime: String?,
        val width: Int,
        val height: Int,
        val frameRate: Int,
        val durationUs: Long,
        val fileSizeBytes: Long,
        val isCommonsCompliant: Boolean,
        val diagnostics: String
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "isValidWebm" to isValidWebm,
            "hasEbmlHeader" to hasEbmlHeader,
            "docType" to docType,
            "videoMime" to videoMime,
            "audioMime" to audioMime,
            "width" to width,
            "height" to height,
            "frameRate" to frameRate,
            "durationUs" to durationUs,
            "fileSizeBytes" to fileSizeBytes,
            "isCommonsCompliant" to isCommonsCompliant,
            "diagnostics" to diagnostics
        )
    }

    /**
     * Inspects the file at [filePath] at the byte level for EBML header
     * and uses Android MediaExtractor to inspect tracks.
     */
    fun validate(filePath: String): ValidationResult {
        val file = File(filePath)
        if (!file.exists() || !file.canRead()) {
            return ValidationResult(
                isValidWebm = false,
                hasEbmlHeader = false,
                docType = "UNKNOWN",
                videoMime = null,
                audioMime = null,
                width = 0,
                height = 0,
                frameRate = 0,
                durationUs = 0L,
                fileSizeBytes = 0L,
                isCommonsCompliant = false,
                diagnostics = "File does not exist or cannot be read: $filePath"
            )
        }

        val fileSizeBytes = file.length()
        val (hasEbml, docType) = checkEbmlHeaderAndDocType(file)

        if (!hasEbml) {
            val isMp4 = checkIsMp4(file)
            val diag = if (isMp4) {
                "REJECTED: File contains an MP4 container (ftyp box detected). Renaming MP4 to .webm is strictly forbidden."
            } else {
                "REJECTED: Missing EBML signature [0x1A 0x45 0xDF 0xA3]. Not a genuine Matroska/WebM container."
            }
            return ValidationResult(
                isValidWebm = false,
                hasEbmlHeader = false,
                docType = docType,
                videoMime = null,
                audioMime = null,
                width = 0,
                height = 0,
                frameRate = 0,
                durationUs = 0L,
                fileSizeBytes = fileSizeBytes,
                isCommonsCompliant = false,
                diagnostics = diag
            )
        }

        // Now inspect tracks using MediaExtractor
        var videoMime: String? = null
        var audioMime: String? = null
        var width = 0
        var height = 0
        var frameRate = 0
        var durationUs = 0L
        val diagnosticsList = mutableListOf<String>()

        diagnosticsList.add("EBML Header verified (0x1A45DFA3). DocType: '$docType'")

        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(filePath)
            val trackCount = extractor.trackCount
            diagnosticsList.add("Track count: $trackCount")

            for (i in 0 until trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: "unknown"

                if (mime.startsWith("video/")) {
                    videoMime = mime
                    if (format.containsKey(MediaFormat.KEY_WIDTH)) {
                        width = format.getInteger(MediaFormat.KEY_WIDTH)
                    }
                    if (format.containsKey(MediaFormat.KEY_HEIGHT)) {
                        height = format.getInteger(MediaFormat.KEY_HEIGHT)
                    }
                    if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                        frameRate = format.getInteger(MediaFormat.KEY_FRAME_RATE)
                    }
                    if (format.containsKey(MediaFormat.KEY_DURATION)) {
                        durationUs = format.getLong(MediaFormat.KEY_DURATION)
                    }
                    diagnosticsList.add("Video track: $mime (${width}x${height} @ ${frameRate}fps, duration: ${durationUs / 1000}ms)")
                } else if (mime.startsWith("audio/")) {
                    audioMime = mime
                    diagnosticsList.add("Audio track: $mime")
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "MediaExtractor exception: ${e.message}")
            diagnosticsList.add("MediaExtractor warning: ${e.message}")
        } finally {
            try {
                extractor.release()
            } catch (ignored: Exception) {}
        }

        // Commons compliance check:
        // Video must be VP8 or VP9
        val isVideoCompliant = videoMime != null && (
            videoMime.contains("vp8", ignoreCase = true) ||
            videoMime.contains("vp9", ignoreCase = true) ||
            videoMime.contains("x-vnd.on2.vp8", ignoreCase = true) ||
            videoMime.contains("x-vnd.on2.vp9", ignoreCase = true)
        )

        // Audio must be Opus or Vorbis (or absent if muted)
        val isAudioCompliant = audioMime == null || (
            audioMime.contains("opus", ignoreCase = true) ||
            audioMime.contains("vorbis", ignoreCase = true)
        )

        val isDocTypeWebm = docType.equals("webm", ignoreCase = true)
        val isCommonsCompliant = isDocTypeWebm && isVideoCompliant && isAudioCompliant

        if (isCommonsCompliant) {
            diagnosticsList.add("PASS: Compliant with Wikimedia Commons WebM specifications.")
        } else {
            if (!isDocTypeWebm) diagnosticsList.add("WARN: DocType is '$docType', expected 'webm'")
            if (!isVideoCompliant) diagnosticsList.add("WARN: Video codec '$videoMime' is not VP8 or VP9")
            if (!isAudioCompliant) diagnosticsList.add("WARN: Audio codec '$audioMime' is not Opus or Vorbis")
        }

        return ValidationResult(
            isValidWebm = hasEbml && isDocTypeWebm,
            hasEbmlHeader = hasEbml,
            docType = docType,
            videoMime = videoMime,
            audioMime = audioMime,
            width = width,
            height = height,
            frameRate = frameRate,
            durationUs = durationUs,
            fileSizeBytes = fileSizeBytes,
            isCommonsCompliant = isCommonsCompliant,
            diagnostics = diagnosticsList.joinToString("\n")
        )
    }

    /**
     * Checks if the file starts with the EBML header and extracts DocType.
     */
    private fun checkEbmlHeaderAndDocType(file: File): Pair<Boolean, String> {
        val buffer = ByteArray(4096)
        var bytesRead = 0
        try {
            FileInputStream(file).use { fis ->
                bytesRead = fis.read(buffer)
            }
        } catch (e: Exception) {
            return Pair(false, "ERROR")
        }

        if (bytesRead < 4) return Pair(false, "NONE")

        // First 4 bytes must match 0x1A 0x45 0xDF 0xA3
        if (buffer[0] != EBML_HEADER_BYTES[0] ||
            buffer[1] != EBML_HEADER_BYTES[1] ||
            buffer[2] != EBML_HEADER_BYTES[2] ||
            buffer[3] != EBML_HEADER_BYTES[3]) {
            return Pair(false, "NONE")
        }

        // Search for DocType ID: 0x42 0x82 within the first buffer
        var docType = "unknown"
        for (i in 4 until bytesRead - 8) {
            if (buffer[i] == 0x42.toByte() && buffer[i + 1] == 0x82.toByte()) {
                // Length byte follows
                val len = (buffer[i + 2].toInt() and 0x7F)
                if (len in 1..32 && i + 3 + len <= bytesRead) {
                    val strBytes = ByteArray(len)
                    System.arraycopy(buffer, i + 3, strBytes, 0, len)
                    docType = String(strBytes, Charsets.US_ASCII).trim('\u0000', ' ')
                    break
                }
            }
        }

        return Pair(true, docType)
    }

    /**
     * Checks if file has an MP4 ftyp box signature.
     */
    private fun checkIsMp4(file: File): Boolean {
        val buffer = ByteArray(32)
        try {
            FileInputStream(file).use { fis ->
                val read = fis.read(buffer)
                if (read >= 8) {
                    // Check for 'ftyp' at offset 4..7
                    val tag = String(buffer, 4, 4, Charsets.US_ASCII)
                    return tag == "ftyp"
                }
            }
        } catch (ignored: Exception) {}
        return false
    }
}
