package com.huangusaki.easycopy

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
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
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private var pendingPickResult: MethodChannel.Result? = null

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
        ioExecutor.shutdown()
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
        openDocumentTreeLauncher.launch(intent)
    }

    private fun handleResolveDirectory(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
        val verifyWritable = call.argument<Boolean>("verifyWritable") ?: true
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

        result.success(
            mapOf(
                "basePath" to basePath,
                "rootPath" to rootPath,
                "isWritable" to isWritable,
                "errorMessage" to errorMessage,
            ),
        )
    }

    private fun handleWriteBytes(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
        writeBytes(treeUri, relativePath, bytes)
        result.success(null)
    }

    private fun handleWriteText(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        val text = call.argument<String>("text") ?: ""
        writeBytes(treeUri, relativePath, text.toByteArray(Charsets.UTF_8))
        result.success(null)
    }

    private fun handleImportDirectoryFromPath(call: MethodCall, result: MethodChannel.Result) {
        runAsync(result) {
            val treeUri = call.requireString("treeUri")
            val sourcePath = call.requireString("sourcePath")
            val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
            val operationId = call.argument<String>("operationId")?.trim().orEmpty()
            val sourceDirectory = File(sourcePath)
            require(sourceDirectory.exists()) { "Source directory does not exist: $sourcePath" }
            require(sourceDirectory.isDirectory) { "Source path is not a directory: $sourcePath" }
            val targetRoot = resolveTargetDirectory(treeUri, relativePath)
            val progressReporter =
                ProgressReporter(
                    operationId = operationId,
                    totalCount = countMigratableFilesInDirectory(sourceDirectory),
                )
            progressReporter.dispatch(force = true)
            copyFileSystemDirectoryToDocumentTree(sourceDirectory, targetRoot, progressReporter)
            progressReporter.complete()
            null
        }
    }

    private fun handleExportDirectoryToPath(call: MethodCall, result: MethodChannel.Result) {
        runAsync(result) {
            val treeUri = call.requireString("treeUri")
            val destinationPath = call.requireString("destinationPath")
            val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
            val operationId = call.argument<String>("operationId")?.trim().orEmpty()
            val sourceRoot = resolveSourceDirectory(treeUri, relativePath)
            val destinationDirectory = File(destinationPath)
            destinationDirectory.mkdirs()
            require(destinationDirectory.exists()) {
                "Destination directory could not be created: $destinationPath"
            }
            require(destinationDirectory.isDirectory) {
                "Destination path is not a directory: $destinationPath"
            }
            val progressReporter =
                ProgressReporter(
                    operationId = operationId,
                    totalCount = countMigratableFilesInDocumentTree(sourceRoot),
                )
            progressReporter.dispatch(force = true)
            copyDocumentTreeDirectoryToFileSystem(sourceRoot, destinationDirectory, progressReporter)
            progressReporter.complete()
            null
        }
    }

    private fun handleCopyDirectoryToTree(call: MethodCall, result: MethodChannel.Result) {
        runAsync(result) {
            val sourceTreeUri = call.requireString("sourceTreeUri")
            val targetTreeUri = call.requireString("targetTreeUri")
            val sourceRelativePath =
                call.argument<String>("sourceRelativePath")?.trim().orEmpty()
            val targetRelativePath =
                call.argument<String>("targetRelativePath")?.trim().orEmpty()
            val operationId = call.argument<String>("operationId")?.trim().orEmpty()
            val sourceRoot = resolveSourceDirectory(sourceTreeUri, sourceRelativePath)
            val targetRoot = resolveTargetDirectory(targetTreeUri, targetRelativePath)
            val progressReporter =
                ProgressReporter(
                    operationId = operationId,
                    totalCount = countMigratableFilesInDocumentTree(sourceRoot),
                )
            progressReporter.dispatch(force = true)
            copyDocumentTreeDirectoryToDocumentTree(sourceRoot, targetRoot, progressReporter)
            progressReporter.complete()
            null
        }
    }

    private fun handleReadText(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        val document = requireDocument(treeUri, relativePath)
        val text =
            activity.contentResolver.openInputStream(document.uri)?.bufferedReader(Charsets.UTF_8)?.use {
                it.readText()
            } ?: throw FileNotFoundException("Document not found: $relativePath")
        result.success(text)
    }

    private fun handleReadBytes(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        val document = requireDocument(treeUri, relativePath)
        val bytes =
            activity.contentResolver.openInputStream(document.uri)?.use { input ->
                input.readBytes()
            } ?: throw FileNotFoundException("Document not found: $relativePath")
        result.success(bytes)
    }

    private fun handleReadBytesFromUri(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = call.requireString("documentUri")
        val bytes =
            activity.contentResolver.openInputStream(Uri.parse(documentUri))?.use { input ->
                input.readBytes()
            } ?: throw FileNotFoundException("Document not found: $documentUri")
        result.success(bytes)
    }

    private fun handleListEntries(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.argument<String>("relativePath")?.trim().orEmpty()
        val recursive = call.argument<Boolean>("recursive") ?: false
        val tree = requireTree(treeUri)
        val baseDocument = resolveDocument(tree, splitRelativePath(relativePath))
        if (baseDocument == null || !baseDocument.exists()) {
            result.success(emptyList<Map<String, Any?>>())
            return
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
            results.add(entryMap(relativePath = baseSegments.joinToString("/"), document = baseDocument))
        }
        result.success(results)
    }

    private fun handleExists(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.requireString("treeUri")
        val relativePath = call.requireString("relativePath")
        val tree = requireTree(treeUri)
        val document = resolveDocument(tree, splitRelativePath(relativePath))
        result.success(document?.exists() == true)
    }

    private fun handleDeletePath(call: MethodCall, result: MethodChannel.Result) {
        runAsync(result) {
            val treeUri = call.requireString("treeUri")
            val relativePath = call.requireString("relativePath")
            val operationId = call.argument<String>("operationId")?.trim().orEmpty()
            if (relativePath.isBlank()) {
                return@runAsync false
            }
            val tree = requireTree(treeUri)
            val document = resolveDocument(tree, splitRelativePath(relativePath))
            if (document == null || !document.exists()) {
                return@runAsync false
            }
            if (operationId.isBlank()) {
                return@runAsync document.delete()
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

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        ioExecutor.execute {
            try {
                val value = block()
                postSuccess(result, value)
            } catch (error: Throwable) {
                postError(result, error)
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

    private fun writeBytes(treeUri: String, relativePath: String, bytes: ByteArray) {
        val tree = requireTree(treeUri)
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
        val existing = parent.findFile(fileName)
        require(existing == null || existing.isFile) {
            "Target path is not a file: $relativePath"
        }
        val file =
            existing
                ?: parent.createFile(detectMimeType(fileName), fileName)
                ?: throw IOException("Failed to create document: $relativePath")
        activity.contentResolver.openOutputStream(file.uri, "rwt")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: throw IOException("Failed to open document for writing: $relativePath")
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

    private fun copyFileSystemDirectoryToDocumentTree(
        source: File,
        target: DocumentFile,
        progressReporter: ProgressReporter,
        relativePath: String = "",
    ) {
        val children = source.listFiles()?.sortedBy { it.name.lowercase() } ?: emptyList()
        for (child in children) {
            if (shouldSkipMigrationFile(child.name)) {
                continue
            }
            val childRelativePath =
                if (relativePath.isEmpty()) {
                    child.name
                } else {
                    "$relativePath/${child.name}"
                }
            if (child.isDirectory) {
                val targetDirectory = ensureChildDirectory(target, child.name)
                copyFileSystemDirectoryToDocumentTree(
                    child,
                    targetDirectory,
                    progressReporter,
                    childRelativePath,
                )
                continue
            }
            if (child.isFile) {
                copyFileToDocumentTree(child, target)
                progressReporter.advance(childRelativePath)
            }
        }
    }

    private fun copyDocumentTreeDirectoryToFileSystem(
        source: DocumentFile,
        target: File,
        progressReporter: ProgressReporter,
        relativePath: String = "",
    ) {
        val children = source.listFiles().sortedBy { it.name?.lowercase().orEmpty() }
        for (child in children) {
            val childName = child.name?.trim().orEmpty()
            if (childName.isEmpty() || shouldSkipMigrationFile(childName)) {
                continue
            }
            val childRelativePath =
                if (relativePath.isEmpty()) {
                    childName
                } else {
                    "$relativePath/$childName"
                }
            if (child.isDirectory) {
                val targetDirectory = File(target, childName)
                targetDirectory.mkdirs()
                copyDocumentTreeDirectoryToFileSystem(
                    child,
                    targetDirectory,
                    progressReporter,
                    childRelativePath,
                )
                continue
            }
            copyDocumentTreeFileToFileSystem(child, File(target, childName))
            progressReporter.advance(childRelativePath)
        }
    }

    private fun copyDocumentTreeDirectoryToDocumentTree(
        source: DocumentFile,
        target: DocumentFile,
        progressReporter: ProgressReporter,
        relativePath: String = "",
    ) {
        val children = source.listFiles().sortedBy { it.name?.lowercase().orEmpty() }
        for (child in children) {
            val childName = child.name?.trim().orEmpty()
            if (childName.isEmpty() || shouldSkipMigrationFile(childName)) {
                continue
            }
            val childRelativePath =
                if (relativePath.isEmpty()) {
                    childName
                } else {
                    "$relativePath/$childName"
                }
            if (child.isDirectory) {
                val targetDirectory = ensureChildDirectory(target, childName)
                copyDocumentTreeDirectoryToDocumentTree(
                    child,
                    targetDirectory,
                    progressReporter,
                    childRelativePath,
                )
                continue
            }
            copyDocumentTreeFileToDocumentTree(child, target)
            progressReporter.advance(childRelativePath)
        }
    }

    private fun copyFileToDocumentTree(source: File, targetDirectory: DocumentFile) {
        val targetFile = ensureChildFile(targetDirectory, source.name)
        FileInputStream(source).use { input ->
            activity.contentResolver.openOutputStream(targetFile.uri, "rwt")?.use { output ->
                copyStreams(input, output)
            } ?: throw IOException("Failed to open destination document: ${source.name}")
        }
    }

    private fun copyDocumentTreeFileToFileSystem(source: DocumentFile, target: File) {
        target.parentFile?.mkdirs()
        activity.contentResolver.openInputStream(source.uri)?.use { input ->
            FileOutputStream(target, false).use { output ->
                copyStreams(input, output)
            }
        } ?: throw IOException("Failed to open source document: ${source.name ?: source.uri}")
    }

    private fun copyDocumentTreeFileToDocumentTree(
        source: DocumentFile,
        targetDirectory: DocumentFile,
    ) {
        val sourceName = source.name?.trim().orEmpty()
        require(sourceName.isNotEmpty()) { "Source document name is empty." }
        val targetFile = ensureChildFile(targetDirectory, sourceName)
        activity.contentResolver.openInputStream(source.uri)?.use { input ->
            activity.contentResolver.openOutputStream(targetFile.uri, "rwt")?.use { output ->
                copyStreams(input, output)
            } ?: throw IOException("Failed to open destination document: $sourceName")
        } ?: throw IOException("Failed to open source document: $sourceName")
    }

    private fun ensureChildDirectory(parent: DocumentFile, name: String): DocumentFile {
        val existing = parent.findFile(name)
        return when {
            existing == null ->
                parent.createDirectory(name)
                    ?: throw IOException("Failed to create directory: $name")
            existing.isDirectory -> existing
            else -> throw IOException("Path segment is not a directory: $name")
        }
    }

    private fun ensureChildFile(parent: DocumentFile, fileName: String): DocumentFile {
        val existing = parent.findFile(fileName)
        return when {
            existing == null ->
                parent.createFile(detectMimeType(fileName), fileName)
                    ?: throw IOException("Failed to create document: $fileName")
            existing.isFile -> existing
            else -> throw IOException("Target path is not a file: $fileName")
        }
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

    private fun countMigratableFilesInDirectory(directory: File): Int {
        var count = 0
        val children = directory.listFiles() ?: return 0
        for (child in children) {
            if (shouldSkipMigrationFile(child.name)) {
                continue
            }
            count +=
                when {
                    child.isDirectory -> countMigratableFilesInDirectory(child)
                    child.isFile -> 1
                    else -> 0
                }
        }
        return count
    }

    private fun countMigratableFilesInDocumentTree(directory: DocumentFile): Int {
        var count = 0
        for (child in directory.listFiles()) {
            val childName = child.name?.trim().orEmpty()
            if (childName.isEmpty() || shouldSkipMigrationFile(childName)) {
                continue
            }
            count +=
                when {
                    child.isDirectory -> countMigratableFilesInDocumentTree(child)
                    child.isFile -> 1
                    else -> 0
                }
        }
        return count
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

    private fun shouldSkipMigrationFile(fileName: String): Boolean {
        val normalized = fileName.trim().lowercase()
        if (normalized.isEmpty()) {
            return false
        }
        return normalized.endsWith(".part") ||
            normalized.endsWith(".migrate_tmp") ||
            normalized.startsWith(".storage_probe_")
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
            val child = current.findFile(segment) ?: return null
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
        for (child in directory.listFiles()) {
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
            "uri" to document.uri.toString(),
            "isDirectory" to document.isDirectory,
            "size" to document.length(),
            "lastModifiedMillis" to document.lastModified(),
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
        return relativePath
            .replace('\\', '/')
            .split('/')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
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

    private fun detectMimeType(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        if (extension.isBlank()) {
            return "application/octet-stream"
        }
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: when (extension) {
                "json" -> "application/json"
                "txt" -> "text/plain"
                else -> "application/octet-stream"
            }
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
            val now = System.currentTimeMillis()
            val shouldDispatch =
                force ||
                    completedCount >= totalCount ||
                    completedCount <= 3 ||
                    completedCount % 16 == 0 ||
                    now - lastDispatchedAtMillis >= 80
            if (!shouldDispatch) {
                return
            }
            lastDispatchedAtMillis = now
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
    }
}
