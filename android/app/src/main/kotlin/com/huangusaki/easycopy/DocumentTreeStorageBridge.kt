package com.huangusaki.easycopy

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Environment
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.DocumentsContract
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

class DocumentTreeStorageBridge(
    private val activity: ComponentActivity,
    binaryMessenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val methodChannel =
        MethodChannel(binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val foregroundIoExecutor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "easycopy-document-tree-foreground")
        }
    private val transferIoExecutor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "easycopy-document-tree-transfer")
        }
    private val debugLoggingEnabled =
        (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private var pendingPickResult: MethodChannel.Result? = null
    private val documentCommitLock = Any()

    private val openDocumentTreeLauncher =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val pendingResult = pendingPickResult ?: return@registerForActivityResult
            pendingPickResult = null
            if (result.resultCode != Activity.RESULT_OK) {
                pendingResult.success(null)
                return@registerForActivityResult
            }

            val data = result.data
            val treeUri = data?.data
            if (treeUri == null) {
                pendingResult.success(null)
                return@registerForActivityResult
            }

            try {
                val grantedFlags =
                    (data.flags and
                        (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
                activity.contentResolver.takePersistableUriPermission(
                    treeUri,
                    if (grantedFlags == 0) {
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    } else {
                        grantedFlags
                    },
                )
                pendingResult.success(
                    mapOf(
                        "treeUri" to treeUri.toString(),
                        "displayName" to buildDisplayPath(treeUri),
                    ),
                )
            } catch (error: Throwable) {
                pendingResult.error(
                    "pick_directory_failed",
                    error.message ?: "Failed to open directory picker.",
                    null,
                )
            }
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "pickDirectory" -> handlePickDirectory(call, result)
                "resolveDirectory" -> handleResolveDirectory(call, result)
                "writeBytes" -> handleWriteBytes(call, result)
                "writeText" -> handleWriteText(call, result)
                "importDirectoryFromPath" -> handleImportDirectoryFromPath(call, result)
                "exportDirectoryToPath" -> handleExportDirectoryToPath(call, result)
                "copyDirectoryToTree" -> handleCopyDirectoryToTree(call, result)
                "readText" -> handleReadText(call, result)
                "readBytes" -> handleReadBytes(call, result)
                "readBytesFromUri" -> handleReadBytesFromUri(call, result)
                "listEntries" -> handleListEntries(call, result)
                "exists" -> handleExists(call, result)
                "deletePath" -> handleDeletePath(call, result)
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error(
                "document_tree_error",
                error.message ?: error.toString(),
                null,
            )
        }
    }

    fun dispose() {
        pendingPickResult?.error(
            "pick_directory_cancelled",
            "Directory picker was cancelled.",
            null,
        )
        pendingPickResult = null
        methodChannel.setMethodCallHandler(null)
        foregroundIoExecutor.shutdown()
        transferIoExecutor.shutdown()
    }

    private fun handlePickDirectory(call: MethodCall, result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error(
                "pick_directory_busy",
                "Another directory picker request is already running.",
                null,
            )
            return
        }
        pendingPickResult = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }
        try {
            openDocumentTreeLauncher.launch(intent)
        } catch (error: Throwable) {
            pendingPickResult = null
            throw error
        }
    }

    private fun handleResolveDirectory(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
        val verifyWritable = call.argument<Boolean>("verifyWritable") ?: true
        runAsyncLogged(
            method = "resolveDirectory",
            result = result,
            relativePath = relativePath,
            recursive = false,
            extra = "verifyWritable=$verifyWritable",
        ) {
            val tree = requireTree(treeUri)
            val basePath = buildDisplayPath(Uri.parse(treeUri)).ifBlank { treeUri }
            val rootDirectory =
                if (relativePath.isEmpty()) {
                    tree
                } else {
                    ensureDirectory(tree, splitRelativePath(relativePath))
                }
            val rootPath =
                if (relativePath.isBlank()) {
                    basePath
                } else {
                    "$basePath/$relativePath"
                }
            var errorMessage = ""
            var isWritable = rootDirectory.canWrite()

            if (verifyWritable) {
                try {
                    writeProbe(rootDirectory)
                    isWritable = true
                } catch (error: Throwable) {
                    isWritable = false
                    errorMessage = error.message ?: error.toString()
                }
            }

            mapOf(
                "basePath" to basePath,
                "rootPath" to rootPath,
                "isWritable" to isWritable,
                "errorMessage" to errorMessage,
                "storageIdentity" to storageIdentity(rootDirectory),
                "comparablePath" to comparableDocumentPath(rootDirectory).orEmpty(),
            )
        }
    }

    private fun handleWriteBytes(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
        runAsyncLogged(
            method = "writeBytes",
            result = result,
            relativePath = relativePath,
            recursive = false,
            extra = "byteCount=${bytes.size}",
        ) {
            writeBytes(treeUri, relativePath, bytes)
            null
        }
    }

    private fun handleWriteText(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        val text = call.argument<String>("text") ?: ""
        runAsyncLogged(
            method = "writeText",
            result = result,
            relativePath = relativePath,
            recursive = false,
            extra = "charCount=${text.length}",
        ) {
            writeBytes(treeUri, relativePath, text.toByteArray(Charsets.UTF_8))
            null
        }
    }

    private fun handleImportDirectoryFromPath(call: MethodCall, result: MethodChannel.Result) {
        runAsyncLogged(
            method = "importDirectoryFromPath",
            result = result,
            executor = transferIoExecutor,
            relativePath = call.argument<String>("relativePath")?.trim().orEmpty(),
            recursive = true,
            extra = "operationId=${call.argument<String>("operationId")?.trim().orEmpty()}",
        ) {
            val treeUri = call.requireString("treeUri")
            val sourcePath = call.requireString("sourcePath")
            val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
            val operationId = call.argument<String>("operationId")?.trim().orEmpty()
            val sourceDirectory = File(sourcePath)
            require(sourceDirectory.exists()) { "Source directory does not exist: $sourcePath" }
            require(sourceDirectory.isDirectory) { "Source path is not a directory: $sourcePath" }
            val verifyOnly = call.argument<Boolean>("verifyOnly") ?: false
            val targetRoot = if (verifyOnly) resolveSourceDirectory(treeUri, relativePath)
                else resolveTargetDirectory(treeUri, relativePath)
            ensureNonOverlappingMigrationRoots(sourceDirectory, targetRoot)
            transferFiles(
                paths = transferPaths(call),
                operationId = operationId,
                verifyOnly = verifyOnly,
                source = { path -> FileInputStream(resolveFile(sourceDirectory, path)) },
                target = { path -> openDocumentInput(targetRoot, path) },
                write = { path, input -> writeDocumentPath(targetRoot, path, false) { output -> copyStreams(input, output) } },
            )
            null
        }
    }

    private fun handleExportDirectoryToPath(call: MethodCall, result: MethodChannel.Result) {
        runAsyncLogged(
            method = "exportDirectoryToPath",
            result = result,
            executor = transferIoExecutor,
            relativePath = call.argument<String>("relativePath")?.trim().orEmpty(),
            recursive = true,
            extra = "operationId=${call.argument<String>("operationId")?.trim().orEmpty()}",
        ) {
            val treeUri = call.requireString("treeUri")
            val destinationPath = call.requireString("destinationPath")
            val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
            val operationId = call.argument<String>("operationId")?.trim().orEmpty()
            val sourceRoot = resolveSourceDirectory(treeUri, relativePath)
            val destinationDirectory = File(destinationPath)
            val verifyOnly = call.argument<Boolean>("verifyOnly") ?: false
            if (!verifyOnly) destinationDirectory.mkdirs()
            require(destinationDirectory.exists()) {
                "Destination directory could not be created: $destinationPath"
            }
            require(destinationDirectory.isDirectory) {
                "Destination path is not a directory: $destinationPath"
            }
            ensureNonOverlappingMigrationRoots(sourceRoot, destinationDirectory)
            transferFiles(
                paths = transferPaths(call),
                operationId = operationId,
                verifyOnly = verifyOnly,
                source = { path -> openDocumentInput(sourceRoot, path) ?: throw FileNotFoundException(path) },
                target = { path -> resolveFile(destinationDirectory, path).let { if (it.exists()) FileInputStream(it) else null } },
                write = { path, input -> writeFileAtomically(resolveFile(destinationDirectory, path), input) },
            )
            null
        }
    }

    private fun handleCopyDirectoryToTree(call: MethodCall, result: MethodChannel.Result) {
        runAsyncLogged(
            method = "copyDirectoryToTree",
            result = result,
            executor = transferIoExecutor,
            relativePath = call.argument<String>("sourceRelativePath")?.trim().orEmpty(),
            recursive = true,
            extra = "operationId=${call.argument<String>("operationId")?.trim().orEmpty()}",
        ) {
            val sourceTreeUri = call.requireString("sourceTreeUri")
            val targetTreeUri = call.requireString("targetTreeUri")
            val sourceRelativePath =
                call.argument<String>("sourceRelativePath")?.trim().orEmpty()
            val targetRelativePath =
                call.argument<String>("targetRelativePath")?.trim().orEmpty()
            val operationId = call.argument<String>("operationId")?.trim().orEmpty()
            val sourceRoot = resolveSourceDirectory(sourceTreeUri, sourceRelativePath)
            val verifyOnly = call.argument<Boolean>("verifyOnly") ?: false
            val targetRoot = if (verifyOnly) resolveSourceDirectory(targetTreeUri, targetRelativePath)
                else resolveTargetDirectory(targetTreeUri, targetRelativePath)
            ensureNonOverlappingMigrationRoots(sourceRoot, targetRoot)
            transferFiles(
                paths = transferPaths(call),
                operationId = operationId,
                verifyOnly = verifyOnly,
                source = { path -> openDocumentInput(sourceRoot, path) ?: throw FileNotFoundException(path) },
                target = { path -> openDocumentInput(targetRoot, path) },
                write = { path, input -> writeDocumentPath(targetRoot, path, false) { output -> copyStreams(input, output) } },
            )
            null
        }
    }

    private fun handleReadText(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        runAsyncLogged(
            method = "readText",
            result = result,
            relativePath = relativePath,
            recursive = false,
        ) {
            val document = requireDocument(treeUri, relativePath)
            activity.contentResolver.openInputStream(document.uri)?.bufferedReader(
                Charsets.UTF_8,
            )?.use {
                it.readText()
            } ?: throw FileNotFoundException("Document not found: $relativePath")
        }
    }

    private fun handleReadBytes(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        runAsyncLogged(
            method = "readBytes",
            result = result,
            relativePath = relativePath,
            recursive = false,
        ) {
            val document = requireDocument(treeUri, relativePath)
            activity.contentResolver.openInputStream(document.uri)?.use { input ->
                input.readBytes()
            } ?: throw FileNotFoundException("Document not found: $relativePath")
        }
    }

    private fun handleReadBytesFromUri(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = call.requireString("documentUri")
        runAsyncLogged(
            method = "readBytesFromUri",
            result = result,
            relativePath = "",
            recursive = false,
            extra = "documentUri=${summarizeForLog(documentUri)}",
        ) {
            activity.contentResolver.openInputStream(Uri.parse(documentUri))?.use { input ->
                input.readBytes()
            } ?: throw FileNotFoundException("Document not found: $documentUri")
        }
    }

    private fun handleListEntries(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
        val recursive = call.argument<Boolean>("recursive") ?: false
        runAsyncLogged(
            method = "listEntries",
            result = result,
            relativePath = relativePath,
            recursive = recursive,
        ) {
            val tree = requireTree(treeUri)
            val baseDocument = resolveDocument(tree, splitRelativePath(relativePath))
            if (baseDocument == null || !baseDocument.exists()) {
                return@runAsyncLogged emptyList<Map<String, Any?>>()
            }

            val baseSegments = splitRelativePath(relativePath)
            val results = mutableListOf<Map<String, Any?>>()
            if (baseDocument.isDirectory) {
                collectEntries(
                    directory = baseDocument,
                    prefixSegments = baseSegments,
                    recursive = recursive,
                    results = results,
                )
            } else {
                results.add(
                    entryMap(
                        relativePath = baseSegments.joinToString("/"),
                        document = baseDocument,
                    ),
                )
            }
            results
        }
    }

    private fun handleExists(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        runAsyncLogged(
            method = "exists",
            result = result,
            relativePath = relativePath,
            recursive = false,
        ) {
            val tree = requireTree(treeUri)
            val document = resolveDocument(tree, splitRelativePath(relativePath))
            document?.exists() == true
        }
    }

    private fun handleDeletePath(call: MethodCall, result: MethodChannel.Result) {
        val operationId = call.argument<String>("operationId")?.trim().orEmpty()
        runAsyncLogged(
            method = "deletePath",
            result = result,
            executor = if (operationId.isBlank()) foregroundIoExecutor else transferIoExecutor,
            relativePath = call.argument<String>("relativePath")?.trim().orEmpty(),
            recursive = false,
            extra = "operationId=$operationId",
        ) {
            val treeUri = call.requireString("treeUri")
            val relativePath = call.requireString("relativePath")
            if (relativePath.isBlank()) {
                return@runAsyncLogged false
            }
            val tree = requireTree(treeUri)
            val document = resolveDocument(tree, splitRelativePath(relativePath))
            if (document == null || !document.exists()) {
                return@runAsyncLogged false
            }
            if (operationId.isBlank()) {
                return@runAsyncLogged document.delete()
            }
            val progressReporter =
                ProgressReporter(
                    operationId = operationId,
                    totalCount = countFilesForDeletion(document),
                )
            progressReporter.dispatch(force = true)
            val deleted = deleteDocumentRecursively(document, relativePath, progressReporter)
            progressReporter.complete()
            deleted
        }
    }

    private inline fun <T> runAsyncLogged(
        method: String,
        result: MethodChannel.Result,
        executor: java.util.concurrent.Executor = foregroundIoExecutor,
        relativePath: String = "",
        recursive: Boolean = false,
        extra: String = "",
        crossinline block: () -> T,
    ) {
        executor.execute {
            val startedAt = SystemClock.elapsedRealtime()
            val threadName = Thread.currentThread().name
            try {
                val value = block()
                postSuccess(result, value)
                logAsyncOperation(
                    method = method,
                    relativePath = relativePath,
                    recursive = recursive,
                    elapsedMs = SystemClock.elapsedRealtime() - startedAt,
                    threadName = threadName,
                    success = true,
                    extra = extra,
                )
            } catch (error: Throwable) {
                postError(result, error)
                logAsyncOperation(
                    method = method,
                    relativePath = relativePath,
                    recursive = recursive,
                    elapsedMs = SystemClock.elapsedRealtime() - startedAt,
                    threadName = threadName,
                    success = false,
                    extra = extra,
                    error = error,
                )
            }
        }
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: MethodChannel.Result, error: Throwable) {
        mainHandler.post {
            result.error(
                "document_tree_error",
                error.message ?: error.toString(),
                null,
            )
        }
    }

    private fun logAsyncOperation(
        method: String,
        relativePath: String,
        recursive: Boolean,
        elapsedMs: Long,
        threadName: String,
        success: Boolean,
        extra: String = "",
        error: Throwable? = null,
    ) {
        if (!debugLoggingEnabled) {
            return
        }
        val message =
            buildString {
                append("method=").append(method)
                append(" relativePath=").append(quoteLogValue(relativePath))
                append(" recursive=").append(recursive)
                append(" elapsedMs=").append(elapsedMs)
                append(" threadName=").append(quoteLogValue(threadName))
                append(" status=").append(if (success) "ok" else "error")
                if (extra.isNotBlank()) {
                    append(' ').append(extra)
                }
                if (error != null) {
                    append(" error=").append(quoteLogValue(error.javaClass.simpleName))
                    append(" message=").append(quoteLogValue(error.message ?: error.toString()))
                }
            }
        if (success) {
            Log.d(TAG, message)
        } else {
            Log.w(TAG, message)
        }
    }

    private fun quoteLogValue(value: String): String {
        return "\"${value.replace("\"", "\\\"").replace("\n", " ").replace("\r", " ")}\""
    }

    private fun summarizeForLog(value: String, maxLength: Int = 80): String {
        val trimmed = value.trim().replace("\n", " ").replace("\r", " ")
        return if (trimmed.length <= maxLength) {
            trimmed
        } else {
            "${trimmed.take(maxLength - 3)}..."
        }
    }

    private fun writeBytes(treeUri: String, relativePath: String, bytes: ByteArray) {
        writeDocumentPath(requireTree(treeUri), relativePath, true) { output -> output.write(bytes) }
    }

    private fun writeDocumentPath(
        tree: DocumentFile,
        relativePath: String,
        replaceExisting: Boolean,
        write: (OutputStream) -> Unit,
    ) {
        val segments = splitRelativePath(relativePath)
        require(segments.isNotEmpty()) { "relativePath must not be empty." }
        val parent =
            ensureDirectory(
                tree,
                if (segments.size == 1) {
                    emptyList()
                } else {
                    segments.dropLast(1)
                },
            )
        val fileName = segments.last()
        val temporary = parent.createFile("application/octet-stream", ".easycopy.$fileName.${UUID.randomUUID()}.part")
            ?: throw IOException("无法创建临时缓存文件：$fileName")
        var committed = false
        try {
            activity.contentResolver.openOutputStream(temporary.uri, "rwt")?.use { output ->
                write(output)
                output.flush()
            } ?: throw IOException("无法写入缓存文件：$fileName")
            synchronized(documentCommitLock) {
                val existing = recoverDocument(parent, fileName)
                if (existing != null && (!replaceExisting || !existing.isFile)) {
                    throw IOException("目标已有同名文件，未覆盖：$relativePath")
                }
                val backupName = ".easycopy.$fileName.migrate_tmp"
                val oldBackup = parent.findFile(backupName)
                if (oldBackup != null && !oldBackup.delete()) throw IOException("无法提交缓存文件：$fileName")
                if (existing != null && !existing.renameTo(backupName)) {
                    throw IOException("此目录不支持安全写入，请选择其他目录。")
                }
                try {
                    if (!temporary.renameTo(fileName)) {
                        throw IOException("此目录不支持安全写入，请选择其他目录。")
                    }
                    committed = true
                    if (temporary.name != fileName) throw IOException("无法提交缓存文件：$fileName")
                } catch (error: Throwable) {
                    if (!committed) existing?.renameTo(fileName)
                    throw error
                }
                existing?.delete()
            }
        } finally {
            if (!committed) temporary.delete()
        }
    }

    private fun resolveTargetDirectory(treeUri: String, relativePath: String): DocumentFile {
        val tree = requireTree(treeUri)
        return if (relativePath.isBlank()) {
            tree
        } else {
            ensureDirectory(tree, splitRelativePath(relativePath))
        }
    }

    private fun resolveSourceDirectory(treeUri: String, relativePath: String): DocumentFile {
        val tree = requireTree(treeUri)
        val document =
            if (relativePath.isBlank()) {
                tree
            } else {
                resolveDocument(tree, splitRelativePath(relativePath))
            }
        require(document != null && document.exists()) {
            "Source directory is no longer available."
        }
        require(document.isDirectory) { "Source path is not a directory." }
        return document
    }

    private fun transferPaths(call: MethodCall): List<String> {
        val paths = call.argument<List<String>>("relativePaths")
            ?: throw IllegalArgumentException("Missing cache file list.")
        return paths.map { path ->
            val segments = splitRelativePath(path)
            require(segments.isNotEmpty()) { "Cache file path must not be empty." }
            segments.joinToString("/")
        }.distinct()
    }

    private fun transferFiles(
        paths: List<String>,
        operationId: String,
        verifyOnly: Boolean,
        source: (String) -> InputStream,
        target: (String) -> InputStream?,
        write: (String, InputStream) -> Unit,
    ) {
        val digests = linkedMapOf<String, ByteArray>()
        val missing = mutableSetOf<String>()
        // Check every conflict before creating any destination file.
        for (path in paths) {
            val sourceDigest = source(path).use { digest(it) }
            digests[path] = sourceDigest
            val existing = target(path)
            if (existing == null) {
                if (verifyOnly) throw IOException("目标缺少缓存文件，原缓存已保留：$path")
                missing.add(path)
            } else if (!existing.use { digest(it) }.contentEquals(sourceDigest)) {
                throw IOException("目标已有不同内容的同名文件，未覆盖：$path")
            }
        }
        val progress = ProgressReporter(operationId = operationId, totalCount = paths.size)
        progress.dispatch(force = true)
        for (path in paths) {
            if (path in missing) source(path).use { input -> write(path, input) }
            val copied = target(path) ?: throw IOException("目标缓存文件不可读：$path")
            if (!copied.use { digest(it) }.contentEquals(digests.getValue(path))) {
                throw IOException("缓存文件校验失败，原缓存已保留：$path")
            }
            progress.advance(path)
        }
        progress.complete()
    }

    private fun digest(input: InputStream): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (count > 0) digest.update(buffer, 0, count)
        }
        return digest.digest()
    }

    private fun openDocumentInput(root: DocumentFile, path: String): InputStream? {
        val document = resolveDocument(root, splitRelativePath(path)) ?: return null
        require(document.isFile) { "目标路径不是文件：$path" }
        return activity.contentResolver.openInputStream(document.uri)
            ?: throw IOException("无法读取文件：$path")
    }

    private fun resolveFile(root: File, path: String): File {
        val result = File(root, splitRelativePath(path).joinToString(File.separator)).canonicalFile
        val prefix = root.canonicalFile.path + File.separator
        require(result.path.startsWith(prefix)) { "缓存文件路径超出所选目录。" }
        return result
    }

    private fun writeFileAtomically(target: File, input: InputStream) {
        val parent = target.parentFile ?: throw IOException("缓存目录不可用。")
        parent.mkdirs()
        val temporary = File.createTempFile(".${target.name}.", ".part", parent)
        try {
            FileOutputStream(temporary).use { output ->
                copyStreams(input, output)
                output.fd.sync()
            }
            if (target.exists()) throw IOException("目标已有同名文件，未覆盖：${target.name}")
            if (!temporary.renameTo(target)) throw IOException("无法提交缓存文件：${target.name}")
        } finally {
            temporary.delete()
        }
    }

    private fun recoverDocument(parent: DocumentFile, name: String): DocumentFile? =
        synchronized(documentCommitLock) {
            val existing = parent.findFile(name)
            if (existing != null) return@synchronized existing
            val backup = parent.findFile(".easycopy.$name.migrate_tmp") ?: return@synchronized null
            if (!backup.renameTo(name)) throw IOException("无法恢复缓存文件：$name")
            backup
        }

    private fun copyStreams(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) {
                break
            }
            output.write(buffer, 0, read)
        }
        output.flush()
    }

    private fun ensureNonOverlappingMigrationRoots(sourceDirectory: File, targetDirectory: DocumentFile) {
        ensureNonOverlappingMigrationRoots(
            sourceComparablePath = comparableFilePath(sourceDirectory),
            targetComparablePath = comparableDocumentPath(targetDirectory),
        )
    }

    private fun ensureNonOverlappingMigrationRoots(sourceDirectory: DocumentFile, targetDirectory: File) {
        ensureNonOverlappingMigrationRoots(
            sourceComparablePath = comparableDocumentPath(sourceDirectory),
            targetComparablePath = comparableFilePath(targetDirectory),
        )
    }

    private fun ensureNonOverlappingMigrationRoots(
        sourceDirectory: DocumentFile,
        targetDirectory: DocumentFile,
    ) {
        require(storageIdentity(sourceDirectory) != storageIdentity(targetDirectory)) {
            "来源和目标是同一缓存目录。"
        }
        if (comparableDocumentPath(sourceDirectory) == null &&
            comparableDocumentPath(targetDirectory) == null &&
            sourceDirectory.uri.authority == targetDirectory.uri.authority) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                throw IOException("此目录在当前系统上不支持安全迁移，请选择本机目录。")
            }
            val overlaps = try {
                DocumentsContract.isChildDocument(activity.contentResolver, sourceDirectory.uri, targetDirectory.uri) ||
                    DocumentsContract.isChildDocument(activity.contentResolver, targetDirectory.uri, sourceDirectory.uri)
            } catch (error: Exception) {
                throw IOException("无法确认目录关系，请选择其他缓存目录。", error)
            }
            require(!overlaps) { "目标缓存目录不能位于当前缓存目录内部，也不能包含当前缓存目录。" }
        }
        ensureNonOverlappingMigrationRoots(
            sourceComparablePath = comparableDocumentPath(sourceDirectory),
            targetComparablePath = comparableDocumentPath(targetDirectory),
        )
    }

    private fun ensureNonOverlappingMigrationRoots(
        sourceComparablePath: String?,
        targetComparablePath: String?,
    ) {
        if (sourceComparablePath.isNullOrBlank() || targetComparablePath.isNullOrBlank()) {
            return
        }
        require(
            !isNestedComparablePath(sourceComparablePath, targetComparablePath) &&
                !isNestedComparablePath(targetComparablePath, sourceComparablePath),
        ) {
            "目标缓存目录不能位于当前缓存目录内部，也不能包含当前缓存目录。"
        }
    }

    private fun comparableFilePath(directory: File): String? {
        return runCatching { normalizeComparablePath(directory.canonicalFile.absolutePath) }.getOrNull()
    }

    private fun comparableDocumentPath(document: DocumentFile): String? {
        val authority = document.uri.authority
        if (authority != "com.android.externalstorage.documents" &&
            authority != "com.android.providers.downloads.documents") return null
        val documentId =
            runCatching { DocumentsContract.getDocumentId(document.uri) }
                .getOrElse {
                    runCatching { DocumentsContract.getTreeDocumentId(document.uri) }.getOrNull()
                }?.trim().orEmpty()
        if (documentId.isEmpty()) {
            return null
        }
        if (authority == "com.android.providers.downloads.documents" &&
            !documentId.startsWith("raw:")) return null
        return comparablePathFromDocumentId(documentId)
    }

    private fun storageIdentity(document: DocumentFile): String {
        val path = comparableDocumentPath(document)
        if (path != null) return "file:$path"
        val documentId = DocumentsContract.getDocumentId(document.uri)
        return "document:${document.uri.authority}:$documentId"
    }

    private fun comparablePathFromDocumentId(documentId: String): String? {
        val normalizedId = documentId.trim()
        if (normalizedId.isEmpty()) {
            return null
        }
        if (normalizedId.startsWith("raw:", ignoreCase = true)) {
            return normalizeComparablePath(normalizedId.substringAfter(':'))
        }
        val volumeId = normalizedId.substringBefore(':').trim()
        val relativePath =
            normalizedId
                .substringAfter(':', "")
                .trim()
                .replace('\\', '/')
        if (volumeId.isEmpty()) {
            return null
        }
        val basePath =
            when {
                volumeId.equals("primary", ignoreCase = true) ->
                    Environment.getExternalStorageDirectory().absolutePath
                volumeId.equals("home", ignoreCase = true) ->
                    File(Environment.getExternalStorageDirectory(), "Documents").path
                else -> File("/storage/$volumeId").path
            }
        val combinedPath =
            if (relativePath.isEmpty()) {
                basePath
            } else {
                File(basePath, relativePath.replace('/', File.separatorChar)).path
            }
        return normalizeComparablePath(combinedPath)
    }

    private fun normalizeComparablePath(path: String): String {
        return path
            .trim()
            .replace('\\', '/')
            .trimEnd('/')
    }

    private fun isNestedComparablePath(candidate: String, parent: String): Boolean {
        return candidate == parent || candidate.startsWith("$parent/")
    }

    private fun countFilesForDeletion(document: DocumentFile): Int {
        if (document.isFile) {
            return 1
        }
        var count = 0
        for (child in document.listFiles()) {
            val childName = child.name?.trim().orEmpty()
            if (childName.isEmpty()) {
                continue
            }
            count += countFilesForDeletion(child)
        }
        return count
    }

    private fun deleteDocumentRecursively(
        document: DocumentFile,
        relativePath: String,
        progressReporter: ProgressReporter,
    ): Boolean {
        if (document.isDirectory) {
            for (child in document.listFiles()) {
                val childName = child.name?.trim().orEmpty()
                if (childName.isEmpty()) {
                    continue
                }
                val childRelativePath =
                    if (relativePath.isEmpty()) {
                        childName
                    } else {
                        "$relativePath/$childName"
                    }
                if (!deleteDocumentRecursively(child, childRelativePath, progressReporter)) {
                    return false
                }
            }
            return document.delete()
        }

        val deleted = document.delete()
        if (deleted) {
            progressReporter.advance(relativePath)
        }
        return deleted
    }

    private fun requireTree(treeUri: String): DocumentFile {
        val documentFile =
            DocumentFile.fromTreeUri(activity, Uri.parse(treeUri))
                ?: throw FileNotFoundException("Invalid tree URI: $treeUri")
        require(documentFile.exists()) { "Storage location is no longer available." }
        require(documentFile.isDirectory) { "Selected storage location is not a directory." }
        return documentFile
    }

    private fun requireDocument(treeUri: String, relativePath: String): DocumentFile {
        val tree = requireTree(treeUri)
        return resolveDocument(tree, splitRelativePath(relativePath))
            ?: throw FileNotFoundException("Document not found: $relativePath")
    }

    private fun ensureDirectory(root: DocumentFile, segments: List<String>): DocumentFile {
        var current = root
        for (segment in segments) {
            val child = current.findFile(segment)
            current =
                when {
                    child == null ->
                        current.createDirectory(segment)
                            ?: throw IOException("Failed to create directory: $segment")
                    child.isDirectory -> child
                    else -> throw IOException("Path segment is not a directory: $segment")
                }
        }
        return current
    }

    private fun resolveDocument(root: DocumentFile, segments: List<String>): DocumentFile? {
        var current = root
        for ((index, segment) in segments.withIndex()) {
            val child = (if (index == segments.lastIndex) recoverDocument(current, segment)
                else current.findFile(segment)) ?: return null
            current = child
            if (index < segments.lastIndex && !current.isDirectory) {
                return null
            }
        }
        return current
    }

    private fun collectEntries(
        directory: DocumentFile,
        prefixSegments: List<String>,
        recursive: Boolean,
        results: MutableList<Map<String, Any?>>,
    ) {
        val children = synchronized(documentCommitLock) {
            val entries = directory.listFiles()
            var recovered = false
            for (entry in entries) {
                val name = entry.name.orEmpty()
                if (name.startsWith(".easycopy.") && name.endsWith(".migrate_tmp") && entry.isFile) {
                    val originalName = name.removePrefix(".easycopy.").removeSuffix(".migrate_tmp")
                    if (originalName.isNotEmpty() && directory.findFile(originalName) == null) {
                        recoverDocument(directory, originalName)
                        recovered = true
                    }
                }
            }
            if (recovered) directory.listFiles() else entries
        }
        for (child in children) {
            val childName = child.name?.trim().orEmpty()
            if (childName.isEmpty()) {
                continue
            }
            val relativeSegments = prefixSegments + childName
            val relativePath = relativeSegments.joinToString("/")
            results.add(entryMap(relativePath = relativePath, document = child))
            if (recursive && child.isDirectory) {
                collectEntries(child, relativeSegments, true, results)
            }
        }
    }

    private fun entryMap(relativePath: String, document: DocumentFile): Map<String, Any?> {
        return mapOf(
            "relativePath" to relativePath,
            "name" to (document.name ?: ""),
            "isDirectory" to document.isDirectory,
            "size" to document.length(),
        )
    }

    private fun writeProbe(rootDirectory: DocumentFile) {
        val probeName = ".storage_probe_${System.currentTimeMillis()}"
        val probe =
            rootDirectory.createFile("application/octet-stream", probeName)
                ?: throw IOException("Failed to create probe file.")
        try {
            activity.contentResolver.openOutputStream(probe.uri, "rwt")?.use { output ->
                output.write(byteArrayOf(1))
                output.flush()
            } ?: throw IOException("Failed to write probe file.")
        } finally {
            probe.delete()
        }
    }

    private fun splitRelativePath(relativePath: String): List<String> {
        val normalized = relativePath.replace('\\', '/')
        require(!normalized.startsWith('/')) { "缓存文件路径必须是相对路径。" }
        val segments = normalized.split('/').map { it.trim() }.filter { it.isNotEmpty() }
        require(segments.none { it == "." || it == ".." || it.contains('\u0000') }) {
            "缓存文件路径无效。"
        }
        return segments
    }

    private fun buildDisplayPath(treeUri: Uri): String {
        val documentFile = DocumentFile.fromTreeUri(activity, treeUri)
        val name = documentFile?.name?.trim().orEmpty()
        if (name.isNotEmpty()) {
            return name
        }

        val documentId =
            runCatching { DocumentsContract.getTreeDocumentId(treeUri) }.getOrNull().orEmpty()
        if (documentId.equals("primary:", ignoreCase = true) || documentId.equals("primary", ignoreCase = true)) {
            return "内部存储"
        }
        if (documentId.startsWith("primary:", ignoreCase = true)) {
            val suffix = documentId.substringAfter(':').trim()
            return if (suffix.isEmpty()) "内部存储" else "内部存储/$suffix"
        }
        return if (documentId.isNotEmpty()) documentId else treeUri.toString()
    }

    private fun MethodCall.requireString(name: String): String {
        return argument<String>(name)?.trim().orEmpty().also { value ->
            require(value.isNotEmpty()) { "Missing argument: $name" }
        }
    }

    private inner class ProgressReporter(
        private val operationId: String,
        private val totalCount: Int,
    ) {
        private var completedCount = 0
        private var lastDispatchedAtMillis = 0L
        private var lastDispatchedCompletedCount = 0

        fun advance(currentItemPath: String) {
            completedCount += 1
            dispatch(currentItemPath)
        }

        fun complete() {
            if (completedCount < totalCount) {
                completedCount = totalCount
            }
            dispatch(force = true)
        }

        fun dispatch(currentItemPath: String = "", force: Boolean = false) {
            if (operationId.isBlank()) {
                return
            }
            val now = SystemClock.uptimeMillis()
            val dispatchStep =
                when {
                    totalCount >= 4096 -> 320
                    totalCount >= 1024 -> 192
                    totalCount >= 256 -> 96
                    else -> 24
                }
            val dispatchIntervalMillis =
                when {
                    totalCount >= 1024 -> 900L
                    totalCount >= 256 -> 600L
                    else -> 320L
                }
            val shouldDispatch =
                force ||
                    completedCount >= totalCount ||
                    completedCount <= 1 ||
                    completedCount - lastDispatchedCompletedCount >= dispatchStep ||
                    now - lastDispatchedAtMillis >= dispatchIntervalMillis
            if (!shouldDispatch) {
                return
            }
            lastDispatchedAtMillis = now
            lastDispatchedCompletedCount = completedCount
            emitProgress(
                operationId = operationId,
                completedCount = completedCount,
                totalCount = totalCount,
                currentItemPath = currentItemPath,
            )
        }
    }

    private fun emitProgress(
        operationId: String,
        completedCount: Int,
        totalCount: Int,
        currentItemPath: String,
    ) {
        mainHandler.post {
            methodChannel.invokeMethod(
                "documentTreeProgress",
                mapOf(
                    "operationId" to operationId,
                    "completedCount" to completedCount,
                    "totalCount" to totalCount,
                    "currentItemPath" to currentItemPath.replace('\\', '/'),
                ),
            )
        }
    }

    companion object {
        private const val CHANNEL_NAME = "easy_copy/download_storage/methods"
        private const val TAG = "DocumentTreeStorageBridge"
    }
}
