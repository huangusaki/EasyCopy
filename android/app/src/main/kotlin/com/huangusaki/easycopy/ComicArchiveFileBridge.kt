package com.huangusaki.easycopy

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors

class ComicArchiveFileBridge(
    private val activity: ComponentActivity,
    binaryMessenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel =
        MethodChannel(binaryMessenger, "easy_copy/comic_archive").also {
            it.setMethodCallHandler(this)
        }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "easycopy-comic-archive")
        }
    private var pending: PendingRequest? = null

    private class PendingRequest(
        val result: MethodChannel.Result,
        val sourcePath: String? = null,
    )

    private val launcher =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { response ->
            val request = pending ?: return@registerForActivityResult
            pending = null
            val uri = response.data?.data
            if (response.resultCode != Activity.RESULT_OK || uri == null) {
                request.result.success(if (request.sourcePath == null) null else false)
                return@registerForActivityResult
            }
            ioExecutor.execute {
                try {
                    val value =
                        if (request.sourcePath == null) {
                            copyPickedArchive(uri)
                        } else {
                            saveArchive(request.sourcePath, uri)
                            true
                        }
                    mainHandler.post { request.result.success(value) }
                } catch (error: Exception) {
                    mainHandler.post {
                        request.result.error("archive_file_failed", error.message, null)
                    }
                }
            }
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "pick" && call.method != "save") {
            result.notImplemented()
            return
        }
        if (pending != null) {
            result.error("archive_picker_busy", "文件选择器已打开。", null)
            return
        }
        try {
            val sourcePath =
                if (call.method == "save") {
                    requireNotNull(call.argument<String>("sourcePath"))
                } else {
                    null
                }
            val intent =
                if (sourcePath == null) {
                    Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(
                            Intent.EXTRA_MIME_TYPES,
                            arrayOf(
                                "application/zip",
                                "application/x-zip-compressed",
                                "application/x-cbz",
                                "application/vnd.comicbook+zip",
                                "application/octet-stream",
                            ),
                        )
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                } else {
                    Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/zip"
                        putExtra(
                            Intent.EXTRA_TITLE,
                            requireNotNull(call.argument<String>("suggestedName")),
                        )
                        addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    }
                }
            pending = PendingRequest(result, sourcePath)
            launcher.launch(intent)
        } catch (error: Exception) {
            pending = null
            result.error("archive_picker_failed", error.message, null)
        }
    }

    private fun copyPickedArchive(uri: Uri): Map<String, String> {
        val resolver = activity.contentResolver
        val name =
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "漫画.zip"
        val directory = File(activity.cacheDir, "comic_archive_${UUID.randomUUID()}")
        if (!directory.mkdir()) throw IOException("无法创建临时目录。")
        try {
            val file = File(directory, if (name.endsWith(".cbz", true)) "archive.cbz" else "archive.zip")
            val input = resolver.openInputStream(uri) ?: throw IOException("无法读取所选文件。")
            input.use { source ->
                file.outputStream().use { destination -> source.copyTo(destination, 64 * 1024) }
            }
            return mapOf("path" to file.absolutePath, "name" to name)
        } catch (error: Exception) {
            directory.deleteRecursively()
            throw error
        }
    }

    private fun saveArchive(sourcePath: String, uri: Uri) {
        File(sourcePath).inputStream().use { source ->
            val output =
                activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IOException("无法写入所选位置。")
            output.use { destination -> source.copyTo(destination, 64 * 1024) }
        }
    }

    fun dispose() {
        pending?.result?.error("archive_picker_cancelled", "文件选择已结束。", null)
        pending = null
        launcher.unregister()
        channel.setMethodCallHandler(null)
        ioExecutor.shutdown()
    }
}
