package com.shifa.shifa_management

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.MediaScannerConnection
import android.content.ContentValues
import android.provider.MediaStore
import android.os.Build
import android.os.Environment

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.shifa.shifa_management/media_scanner"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scanFile") {
                val path = call.argument<String>("path")
                if (path != null) {
                    MediaScannerConnection.scanFile(
                        applicationContext,
                        arrayOf(path),
                        null
                    ) { _, uri ->
                        result.success(uri?.toString())
                    }
                } else {
                    result.error("INVALID_PATH", "Path cannot be null", null)
                }
            } else if (call.method == "saveImageToGallery") {
                val bytes = call.argument<ByteArray>("bytes")
                val filename = call.argument<String>("filename") ?: "invoice_${System.currentTimeMillis()}.png"
                
                if (bytes != null) {
                    try {
                        val savedUri = saveImageToMediaStore(bytes, filename)
                        result.success(savedUri)
                    } catch (e: Exception) {
                        result.error("SAVE_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_BYTES", "Bytes cannot be null", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveImageToMediaStore(bytes: ByteArray, filename: String): String {
        val resolver = applicationContext.contentResolver
        val imageCollection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val contentValues = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
            put(MediaStore.Images.Media.MIME_TYPE, if (filename.endsWith(".jpg") || filename.endsWith(".jpeg")) "image/jpeg" else "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/ShifaInvoices")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(imageCollection, contentValues)
            ?: throw Exception("Failed to create MediaStore entry")

        resolver.openOutputStream(uri)?.use { stream ->
            stream.write(bytes)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            contentValues.clear()
            contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
        }

        return uri.toString()
    }
}
