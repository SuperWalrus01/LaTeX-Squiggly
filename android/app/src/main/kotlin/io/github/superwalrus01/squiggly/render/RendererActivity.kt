package io.github.superwalrus01.squiggly.render

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import io.github.superwalrus01.squiggly.engine.Selection
import java.io.ByteArrayInputStream
import java.io.IOException
import org.json.JSONObject

/**
 * The renderer: LaTeX in, an image out, to paste or insert where LaTeX is not
 * understood. The same renderer as the Chrome extension's and the Mac app's,
 * its page in a WebView, with the app doing what a page cannot: the
 * clipboard, saving, and keeping its settings. See RendererBridge.
 *
 * Opened three ways: from the app, from "Render LaTeX" in another app's
 * selection menu, and from the keyboard's render key, which passes the LaTeX
 * before the caret and gets the image back to insert in its place.
 */
class RendererActivity : Activity() {

    private lateinit var webView: WebView
    private var fromKeyboard = false
    private val saves = HashMap<Int, Pair<Int, ByteArray>>()
    private var nextRequest = 1

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Other apps reach this only through the selection menu's alias, and
        // from there only the selected text is taken. The app's own extras
        // count only when the app opened this activity itself.
        val own = intent.component?.className == RendererActivity::class.java.name
        val selected = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        val input = selected?.let(Selection::stripDelimiters) ?: if (own) intent.getStringExtra(EXTRA_LATEX) else null
        fromKeyboard = own && intent.getBooleanExtra(EXTRA_FROM_KEYBOARD, false)
        val replaces = if (fromKeyboard) intent.getStringExtra(EXTRA_REPLACES) else null

        webView = WebView(this)
        webView.settings.apply {
            javaScriptEnabled = true
            // The page needs nothing from the device's files, and gets nothing.
            allowFileAccess = false
            allowContentAccess = false
            setSupportZoom(false)
        }
        webView.addJavascriptInterface(RendererBridge(this, input, replaces), "SquigglyAndroid")
        webView.webViewClient = PageServer(this)
        setContentView(webView)
        padForSystemBars(webView)

        webView.loadUrl(PAGE)
    }

    override fun onResume() {
        super.onResume()
        // The keyboard leaves LaTeX alone while this is in front: the renderer
        // wants the source, not its symbols.
        inFront = true
    }

    override fun onPause() {
        inFront = false
        super.onPause()
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }

    /** Called once the image is on the clipboard. */
    fun copied() {
        if (fromKeyboard) {
            Toast.makeText(this, "Copied. Tap Insert on the keyboard to put it in.", Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    // MARK: Saving

    fun save(id: Int, name: String, mimeType: String, data: ByteArray) {
        val request = nextRequest++
        saves[request] = id to data
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mimeType)
            .putExtra(Intent.EXTRA_TITLE, name)
        @Suppress("DEPRECATION")
        startActivityForResult(intent, request)
    }

    @Deprecated("The platform's own, kept to need no support library.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val (id, bytes) = saves.remove(requestCode) ?: return
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            reply(id, false, null)
            return
        }
        try {
            contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IOException("The file could not be opened.")
            reply(id, true, null)
        } catch (e: IOException) {
            reply(id, false, e.message ?: "The file could not be written.")
        }
    }

    fun reply(id: Int, ok: Boolean, error: String?) {
        val message = if (error == null) "null" else JSONObject.quote(error)
        runOnUiThread { webView.evaluateJavascript("globalThis.squigglyAndroidReply($id, $ok, $message)", null) }
    }

    // Targeting Android 15 draws the window under the status and navigation
    // bars, and the keyboard over it, so the page is padded clear of all three.
    private fun padForSystemBars(view: View) {
        view.setOnApplyWindowInsetsListener { v, insets ->
            if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            } else {
                @Suppress("DEPRECATION")
                v.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
            }
            insets
        }
    }

    /**
     * Serves the page and its scripts from the app's assets at a fixed https
     * address, because a WebView will not load ES modules or `fetch` from
     * file:// pages, and the renderer needs both. Every other request is
     * refused, so the page cannot reach the network even by mistake.
     */
    private class PageServer(private val context: Context) : WebViewClient() {

        private val types = mapOf(
            "html" to "text/html",
            "js" to "text/javascript",
            "css" to "text/css",
            "json" to "application/json",
            "svg" to "image/svg+xml",
            "png" to "image/png",
            "woff" to "font/woff",
            "woff2" to "font/woff2",
        )

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
            val url = request.url
            if (url.scheme != "https" || url.host != HOST) return refused()
            val path = url.path?.trimStart('/')?.ifEmpty { "index.html" } ?: return refused()
            if (".." in path.split('/')) return refused()
            val type = types[path.substringAfterLast('.', "")] ?: "application/octet-stream"
            return try {
                WebResourceResponse(type, "utf-8", context.assets.open("web/$path"))
            } catch (_: IOException) {
                WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))
            }
        }

        // Links in the page, if any, never navigate the renderer away.
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = true

        private fun refused() =
            WebResourceResponse("text/plain", "utf-8", 403, "Forbidden", emptyMap(), ByteArrayInputStream(ByteArray(0)))
    }

    companion object {
        // The address androidx.webkit's asset loader uses, which is reserved
        // for this and never a real site.
        private const val HOST = "appassets.androidplatform.net"
        private const val PAGE = "https://$HOST/index.html"

        const val EXTRA_LATEX = "io.github.superwalrus01.squiggly.LATEX"
        const val EXTRA_REPLACES = "io.github.superwalrus01.squiggly.REPLACES"
        const val EXTRA_FROM_KEYBOARD = "io.github.superwalrus01.squiggly.FROM_KEYBOARD"

        @Volatile
        var inFront = false
            private set

        fun open(context: Context, latex: String?) {
            context.startActivity(Intent(context, RendererActivity::class.java).putExtra(EXTRA_LATEX, latex))
        }

        /** From the keyboard, which is a service, so the renderer gets a task of its own. */
        fun openFromKeyboard(context: Context, latex: String?, replaces: String?) {
            context.startActivity(
                Intent(context, RendererActivity::class.java)
                    .putExtra(EXTRA_LATEX, latex)
                    .putExtra(EXTRA_REPLACES, replaces)
                    .putExtra(EXTRA_FROM_KEYBOARD, true)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
            )
        }

    }
}
