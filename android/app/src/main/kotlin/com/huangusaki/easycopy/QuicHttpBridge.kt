package com.huangusaki.easycopy

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import org.chromium.net.CronetEngine
import org.chromium.net.CronetException
import org.chromium.net.UploadDataProviders
import org.chromium.net.UrlRequest
import org.chromium.net.UrlResponseInfo

class QuicHttpBridge(
    context: Context,
    binaryMessenger: BinaryMessenger,
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private val channel = MethodChannel(binaryMessenger, CHANNEL_NAME)
    private val engine: CronetEngine by lazy { buildEngine() }

    init {
        channel.setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        runCatching { engine.shutdown() }
        executor.shutdownNow()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "request" -> executeRequest(call, result)
            else -> result.notImplemented()
        }
    }

    private fun executeRequest(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        if (arguments == null) {
            result.error("bad_args", "Missing request arguments.", null)
            return
        }
        val url = arguments["url"] as? String
        if (url.isNullOrBlank()) {
            result.error("bad_args", "Missing request URL.", null)
            return
        }
        val method = (arguments["method"] as? String)?.ifBlank { "GET" } ?: "GET"
        val headers = parseHeaders(arguments["headers"])
        val body = arguments["body"] as? ByteArray ?: ByteArray(0)
        val followRedirects = arguments["followRedirects"] as? Boolean ?: true
        val maxRedirects = (arguments["maxRedirects"] as? Number)?.toInt() ?: 5

        val callback =
            RequestCallback(
                result = result,
                mainHandler = mainHandler,
                followRedirects = followRedirects,
                maxRedirects = maxRedirects.coerceAtLeast(0),
            )
        try {
            val builder = engine.newUrlRequestBuilder(url, callback, executor)
            builder.setHttpMethod(method)
            for ((name, value) in headers) {
                if (!name.equals("content-length", ignoreCase = true)) {
                    builder.addHeader(name, value)
                }
            }
            if (body.isNotEmpty()) {
                builder.setUploadDataProvider(
                    UploadDataProviders.create(body),
                    executor,
                )
            }
            val request = builder.build()
            callback.attach(request)
            request.start()
        } catch (error: Throwable) {
            result.error("network_error", error.message ?: error.toString(), null)
        }
    }

    private fun buildEngine(): CronetEngine {
        val builder =
            CronetEngine.Builder(appContext)
                .enableQuic(true)
                .enableHttp2(true)
                .enableBrotli(true)
                .enableHttpCache(
                    CronetEngine.Builder.HTTP_CACHE_IN_MEMORY,
                    HTTP_CACHE_MAX_BYTES,
                )
                .setUserAgent(DEFAULT_USER_AGENT)
        for (host in QUIC_HINT_HOSTS) {
            builder.addQuicHint(host, HTTPS_PORT, HTTPS_PORT)
        }
        return builder.build()
    }

    private fun parseHeaders(value: Any?): Map<String, String> {
        val rawHeaders = value as? Map<*, *> ?: return emptyMap()
        return rawHeaders.entries.mapNotNull { entry ->
            val key = entry.key?.toString()?.trim().orEmpty()
            val headerValue = entry.value?.toString()?.trim().orEmpty()
            if (key.isEmpty()) {
                null
            } else {
                key to headerValue
            }
        }.toMap()
    }

    private class RequestCallback(
        private val result: MethodChannel.Result,
        private val mainHandler: Handler,
        private val followRedirects: Boolean,
        private val maxRedirects: Int,
    ) : UrlRequest.Callback() {
        private val completed = AtomicBoolean(false)
        private val responseBytes = ByteArrayOutputStream()
        private var redirectCount = 0
        private var request: UrlRequest? = null

        fun attach(request: UrlRequest) {
            this.request = request
        }

        override fun onRedirectReceived(
            request: UrlRequest,
            info: UrlResponseInfo,
            newLocationUrl: String,
        ) {
            if (followRedirects && redirectCount < maxRedirects) {
                redirectCount += 1
                request.followRedirect()
                return
            }
            complete(info, ByteArray(0))
            request.cancel()
        }

        override fun onResponseStarted(request: UrlRequest, info: UrlResponseInfo) {
            request.read(ByteBuffer.allocateDirect(BUFFER_SIZE))
        }

        override fun onReadCompleted(
            request: UrlRequest,
            info: UrlResponseInfo,
            byteBuffer: ByteBuffer,
        ) {
            byteBuffer.flip()
            val chunk = ByteArray(byteBuffer.remaining())
            byteBuffer.get(chunk)
            responseBytes.write(chunk)
            byteBuffer.clear()
            request.read(byteBuffer)
        }

        override fun onSucceeded(request: UrlRequest, info: UrlResponseInfo) {
            complete(info, responseBytes.toByteArray())
        }

        override fun onFailed(
            request: UrlRequest,
            info: UrlResponseInfo?,
            error: CronetException,
        ) {
            completeError(error.message ?: error.toString())
        }

        override fun onCanceled(request: UrlRequest, info: UrlResponseInfo?) {
            completeError("Request canceled.")
        }

        private fun complete(info: UrlResponseInfo, body: ByteArray) {
            if (!completed.compareAndSet(false, true)) {
                return
            }
            val payload =
                mapOf(
                    "statusCode" to info.httpStatusCode,
                    "reasonPhrase" to info.httpStatusText,
                    "headers" to flattenHeaders(info),
                    "body" to body,
                    "protocol" to info.negotiatedProtocol,
                    "url" to info.url,
                )
            mainHandler.post { result.success(payload) }
        }

        private fun completeError(message: String) {
            if (!completed.compareAndSet(false, true)) {
                return
            }
            request?.cancel()
            mainHandler.post { result.error("network_error", message, null) }
        }

        private fun flattenHeaders(info: UrlResponseInfo): Map<String, String> {
            val headers = linkedMapOf<String, String>()
            for (header in info.allHeadersAsList) {
                val name = header.key.lowercase(Locale.US)
                val value = header.value
                val existing = headers[name]
                headers[name] = if (existing == null) value else "$existing,$value"
            }
            return headers
        }
    }

    companion object {
        private const val CHANNEL_NAME = "easy_copy/quic_http"
        private const val HTTPS_PORT = 443
        private const val HTTP_CACHE_MAX_BYTES = 8L * 1024L * 1024L
        private const val BUFFER_SIZE = 64 * 1024
        private const val DEFAULT_USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        private val QUIC_HINT_HOSTS =
            listOf(
                "www.mangacopy.com",
                "mangacopy.com",
                "api.mangacopy.com",
                "www.2026copy.com",
                "2026copy.com",
                "api.2026copy.com",
                "www.2025copy.com",
                "2025copy.com",
                "www.copy20.com",
                "copy20.com",
                "copy2000.site",
                "www.copy2000.site",
                "copy-manga.com",
                "www.copy-manga.com",
                "api.copy-manga.com",
                "copy2000.online",
                "www.copy2000.online",
                "www.2027copy.com",
                "2027copy.com",
                "www.2024copy.com",
                "2024copy.com",
                "www.copymanga.tv",
                "copymanga.tv",
            )
    }
}
