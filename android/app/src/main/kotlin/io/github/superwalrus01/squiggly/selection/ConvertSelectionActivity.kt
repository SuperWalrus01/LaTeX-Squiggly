package io.github.superwalrus01.squiggly.selection

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import io.github.superwalrus01.squiggly.engine.ConversionResult
import io.github.superwalrus01.squiggly.engine.Selection
import io.github.superwalrus01.squiggly.render.RendererActivity

/**
 * "Convert LaTeX" in another app's selection menu. The selected text comes
 * in, and its conversion goes back to replace it. No window appears unless
 * there is something to say: an approximation is a toast, a refusal is a
 * dialog that offers the renderer instead.
 *
 * Where the selection cannot be replaced, such as text on a web page, the
 * result is copied instead.
 */
class ConvertSelectionActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val selected = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        if (selected == null) {
            finish()
            return
        }
        val readOnly = intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, false)

        when (val result = Selection.convert(selected)) {
            is ConversionResult.Converted -> deliver(result.text, readOnly, note = null)
            is ConversionResult.Fallback -> deliver(result.text, readOnly, note = result.reason)
            is ConversionResult.Unsupported -> refuse(selected, result.reason)
        }
    }

    private fun deliver(text: String, readOnly: Boolean, note: String?) {
        if (readOnly) {
            getSystemService(ClipboardManager::class.java)
                ?.setPrimaryClip(ClipData.newPlainText("Converted LaTeX", text))
            // Android 13 and later say so themselves when something is copied.
            Toast.makeText(this, note ?: "Copied $text", Toast.LENGTH_LONG).show()
        } else {
            setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, text))
            if (note != null) Toast.makeText(this, note, Toast.LENGTH_LONG).show()
        }
        finish()
    }

    // Nothing is changed. The renderer can draw what plain text cannot hold,
    // so it is offered rather than left for the user to find.
    private fun refuse(selected: String, reason: String) {
        AlertDialog.Builder(this)
            .setTitle("Can't convert this to text")
            .setMessage(reason)
            .setPositiveButton("Render as image") { _, _ ->
                RendererActivity.open(this, Selection.stripDelimiters(selected))
                finish()
            }
            .setNegativeButton(android.R.string.cancel) { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }
}
