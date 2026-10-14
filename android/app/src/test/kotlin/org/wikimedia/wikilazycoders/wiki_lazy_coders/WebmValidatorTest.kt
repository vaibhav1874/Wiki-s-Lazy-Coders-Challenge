package org.wikimedia.wikilazycoders.wiki_lazy_coders

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.FileOutputStream

class WebmValidatorTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    @Test
    fun testNonExistentFileReturnsInvalid() {
        val result = WebmValidator.validate("/invalid/non/existent/path.webm")
        assertFalse(result.isValidWebm)
        assertFalse(result.hasEbmlHeader)
        assertTrue(result.diagnostics.contains("does not exist"))
    }

    @Test
    fun testMp4FileWithWebmExtensionIsRejected() {
        val mp4FakeFile = tempFolder.newFile("fake_recording.webm")
        // Fake MP4 ftyp box signature: length 24, "ftypisom..."
        val mp4Bytes = byteArrayOf(
            0x00, 0x00, 0x00, 0x18, // box size
            0x66, 0x74, 0x79, 0x70, // 'ftyp'
            0x69, 0x73, 0x6F, 0x6D, // 'isom'
            0x00, 0x00, 0x02, 0x00,
            0x69, 0x73, 0x6F, 0x6D,
            0x6D, 0x70, 0x34, 0x32
        )
        FileOutputStream(mp4FakeFile).use { it.write(mp4Bytes) }

        val result = WebmValidator.validate(mp4FakeFile.absolutePath)
        assertFalse(result.isValidWebm)
        assertFalse(result.hasEbmlHeader)
        assertTrue(result.diagnostics.contains("MP4 container"))
    }

    @Test
    fun testGenuineEbmlHeaderAndDocTypeWebmDetected() {
        val webmFile = tempFolder.newFile("genuine_sample.webm")
        // Minimal genuine EBML header with DocType "webm"
        val sampleWebmBytes = byteArrayOf(
            0x1A.toByte(), 0x45.toByte(), 0xDF.toByte(), 0xA3.toByte(), // EBML ID
            0x01.toByte(), 0x00.toByte(), 0x00.toByte(), 0x1F.toByte(), // Header size
            0x42.toByte(), 0x86.toByte(), 0x81.toByte(), 0x01.toByte(), // EBMLVersion = 1
            0x42.toByte(), 0xF7.toByte(), 0x81.toByte(), 0x01.toByte(), // EBMLReadVersion = 1
            0x42.toByte(), 0xF2.toByte(), 0x81.toByte(), 0x04.toByte(), // EBMLMaxIDLength = 4
            0x42.toByte(), 0xF3.toByte(), 0x81.toByte(), 0x08.toByte(), // EBMLMaxSizeLength = 8
            0x42.toByte(), 0x82.toByte(), 0x84.toByte(),                 // DocType ID + len 4
            0x77.toByte(), 0x65.toByte(), 0x62.toByte(), 0x6D.toByte(), // "webm"
            0x42.toByte(), 0x87.toByte(), 0x81.toByte(), 0x02.toByte(), // DocTypeVersion = 2
            0x42.toByte(), 0x85.toByte(), 0x81.toByte(), 0x02.toByte()  // DocTypeReadVersion = 2
        )
        FileOutputStream(webmFile).use { it.write(sampleWebmBytes) }

        val result = WebmValidator.validate(webmFile.absolutePath)
        assertTrue(result.hasEbmlHeader)
        assertEquals("webm", result.docType)
    }
}
