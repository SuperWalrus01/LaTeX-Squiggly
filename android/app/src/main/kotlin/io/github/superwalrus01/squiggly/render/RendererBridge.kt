package io.github.superwalrus01.squiggly.render

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Base64
import android.webkit.JavascriptInterface
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the renderer page asks of the app, as `SquigglyAndroid` in the page:
 * storage, the clipboard, saving and closing. chrome/renderer/host.js is the
 * other side, and every value crosses as JSON.
 *
 * The page is the app's own, served from its assets, and the WebView loads
 * nothing else, so no other page can reach these methods. They run on the
 * WebView's bridge thread, not the main one.
 */
class RendererBridge(
    private val activity: RendererActivity,
    private val input: String?,
    /** The LaTeX the keyboard took from the text box, which the image replaces. */
    private val replaces: String?,
) {
    private val context: Context = activity.applicationContext

    // The page's two storage areas, as the extension has them: sync for the
    // settings, local for the last input and the history. One JSON object each.
    private val storage = context.getSharedPreferences("renderer", Context.MODE_PRIVATE)

    private fun area(name: String) = JSONObject(storage.getString(name, null) ?: "{}")

    @JavascriptInterface
    fun initialInput(): String = if (input == null) "null" else JSONObject.quote(input)

    @JavascriptInterface
    fun get(area: String, names: String): String {
        val stored = area(area)
        val keys = JSONArray(names)
        val out = JSONObject()
        for (i in 0 until keys.length()) {
            val key = keys.getString(i)
            if (stored.has(key)) out.put(key, stored.get(key))
        }
        return out.toString()
    }

    @JavascriptInterface
    fun set(area: String, items: String) {
        synchronized(storage) {
            val stored = area(area)
            val changes = JSONObject(items)
            for (key in changes.keys()) stored.put(key, changes.get(key))
            storage.edit().putString(area, stored.toString()).apply()
        }
    }

    /** Returns an error to show, or an empty string. */
    @JavascriptInterface
    fun copyImage(png: String, width: Double, height: Double): String {
        val bytes = try {
            Base64.decode(png, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            return "The image could not be read."
        }
        // The page saves its input to the local area as it is typed.
        val latex = area("local").optString("rendererInput", input ?: "")
        val uri = RenderedImages.store(context, bytes, latex, replaces)
        activity.runOnUiThread {
            val clipboard = context.getSystemService(ClipboardManager::class.java)
            clipboard?.setPrimaryClip(ClipData.newUri(context.contentResolver, "Equation", uri))
            activity.copied()
        }
        return ""
    }

    @JavascriptInterface
    fun copyText(text: String): String {
        activity.runOnUiThread {
            val clipboard = context.getSystemService(ClipboardManager::class.java)
            clipboard?.setPrimaryClip(ClipData.newPlainText("Equation", text))
        }
        return ""
    }

    /** Answered later, through squigglyAndroidReply, once the user has chosen where. */
    @JavascriptInterface
    fun save(id: Int, name: String, mimeType: String, data: String) {
        val bytes = try {
            Base64.decode(data, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            activity.reply(id, false, "Nothing to save.")
            return
        }
        activity.runOnUiThread { activity.save(id, name, mimeType, bytes) }
    }

    @JavascriptInterface
    fun close() {
        activity.runOnUiThread { activity.finish() }
    }
}
