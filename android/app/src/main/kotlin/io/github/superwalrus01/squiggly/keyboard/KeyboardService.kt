package io.github.superwalrus01.squiggly.keyboard

import android.content.ClipDescription
import android.inputmethodservice.InputMethodService
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputContentInfo
import android.view.inputmethod.InputMethodManager
import io.github.superwalrus01.squiggly.Settings
import io.github.superwalrus01.squiggly.engine.Engine
import io.github.superwalrus01.squiggly.engine.Selection
import io.github.superwalrus01.squiggly.engine.TriggerOutcome
import io.github.superwalrus01.squiggly.render.RenderedImages
import io.github.superwalrus01.squiggly.render.RendererActivity

/**
 * The maths keyboard. Switched to for maths and away again: it does not try to
 * replace the user's own keyboard, and its globe key goes straight back to it.
 *
 * Space after LaTeX converts it, by the same rules as every other platform,
 * from Engine.outcome. Where the desktop apps keep a buffer of typed keys, a
 * keyboard can simply ask the text box what is before the caret, so a
 * replacement is always checked against the text it replaces.
 *
 * Backspace straight after a conversion puts the LaTeX back, as undoing an
 * autocorrection does.
 */
class KeyboardService : InputMethodService() {

    lateinit var settings: Settings
        private set

    private var keyboard: KeyboardView? = null
    private var editor: EditorInfo? = null

    /** Whether space converts in this text box. */
    private var converting = false

    /** The caret, as the text box last reported it. */
    private var caret = -1

    /** The last conversion, while backspace can still undo it. */
    private var undoable: Undo? = null

    /** LaTeX that was put back, which the next space leaves alone. */
    private var putBack: String? = null

    private class Undo(val replace: TriggerOutcome.Replace, val caret: Int)

    override fun onCreate() {
        super.onCreate()
        settings = Settings(this)
    }

    override fun onCreateInputView(): View = KeyboardView(this, this).also { keyboard = it }

    override fun onStartInput(attribute: EditorInfo, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        editor = attribute
        caret = attribute.initialSelStart
        undoable = null
        putBack = null
        converting = settings.convertOnSpace && convertsIn(attribute)
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        val keyboard = keyboard ?: return
        if (!restarting) keyboard.reset()
        keyboard.setEnterLabel(enterLabel(info))
        offerPendingImage(info)
        refreshPreview()
    }

    override fun onUpdateSelection(
        oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int,
        candidatesStart: Int, candidatesEnd: Int,
    ) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        caret = newSelStart
        // Moving the caret anywhere but where the conversion left it ends the
        // chance to undo it, so backspace elsewhere never rewrites other text.
        undoable?.let { if (newSelStart != it.caret || newSelEnd != it.caret) undoable = null }
        refreshPreview()
    }

    // Passwords are never converted or previewed, and neither is the
    // renderer's own box, which wants LaTeX as it was typed. A text box with
    // no type is a terminal or a game, which takes keys, not text.
    private fun convertsIn(info: EditorInfo): Boolean {
        val type = info.inputType
        if (type and InputType.TYPE_MASK_CLASS != InputType.TYPE_CLASS_TEXT) return false
        when (type and InputType.TYPE_MASK_VARIATION) {
            InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD -> return false
        }
        if (info.packageName == packageName && RendererActivity.inFront) return false
        return true
    }

    // MARK: Keys

    fun onText(text: String) {
        undoable = null
        putBack = null
        type(text)
    }

    fun onSpace() {
        val connection = currentInputConnection ?: return
        if (converting && !hasSelection(connection)) {
            val before = textBeforeCaret(connection)
            val pending = putBack
            putBack = null
            if (pending == null || !before.endsWith(pending)) {
                when (val outcome = Engine.outcome(before, ' ')) {
                    is TriggerOutcome.Replace -> if (replace(connection, before, outcome)) return
                    is TriggerOutcome.Refuse -> if (settings.showNotes) keyboard?.note(outcome.reason)
                    TriggerOutcome.None -> Unit
                }
            }
        }
        undoable = null
        type(" ")
    }

    fun onDelete() {
        val connection = currentInputConnection ?: return
        undoable?.let { undo ->
            undoable = null
            val inserted = undo.replace.insert
            if (textBeforeCaret(connection).endsWith(inserted)) {
                connection.beginBatchEdit()
                connection.deleteSurroundingText(inserted.length, 0)
                connection.commitText(undo.replace.source, 1)
                connection.endBatchEdit()
                putBack = undo.replace.source
                return
            }
        }
        putBack = null
        if (hasSelection(connection)) {
            connection.commitText("", 1)
        } else {
            // A key event rather than deleting one code unit, so the text box
            // removes a whole character, emoji and double-struck letters included.
            sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)
        }
    }

    // Return is never a terminator, on any platform: in a chat it sends the
    // message, and a conversion racing a send is how half a symbol gets posted.
    fun onEnter() {
        undoable = null
        putBack = null
        val info = editor
        val connection = currentInputConnection ?: return
        val action = info?.let { it.imeOptions and EditorInfo.IME_MASK_ACTION } ?: EditorInfo.IME_ACTION_NONE
        val noAction = info == null || (info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0
        if (!noAction && action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED) {
            connection.performEditorAction(action)
        } else {
            sendKeyChar('\n')
        }
    }

    fun onSwitchKeyboard() {
        if (!switchToPreviousInputMethod()) showKeyboardPicker()
    }

    fun showKeyboardPicker() {
        getSystemService(InputMethodManager::class.java)?.showInputMethodPicker()
    }

    /**
     * Opens the renderer with the LaTeX at the caret: the selection, else a
     * `$...$` span ending at the caret, else the run since the last space if
     * it looks like LaTeX. With none of those, it opens with its last input.
     */
    fun onRender() {
        val connection = currentInputConnection
        val selected = connection?.getSelectedText(0)?.toString()
        if (!selected.isNullOrEmpty()) {
            RendererActivity.openFromKeyboard(this, Selection.stripDelimiters(selected), replaces = null)
            return
        }
        val before = connection?.let(::textBeforeCaret) ?: ""
        val source = latexAtCaret(before)
        // Nothing to render: the renderer opens with its last input instead.
        RendererActivity.openFromKeyboard(this, source?.let(Selection::stripDelimiters), replaces = source)
    }

    // MARK: Converting

    private fun replace(connection: InputConnection, before: String, outcome: TriggerOutcome.Replace): Boolean {
        // The engine was asked about exactly this text, so this holds; checked
        // anyway, because deleting the wrong characters costs someone's words.
        if (!before.endsWith(outcome.source)) return false
        val start = caret
        connection.beginBatchEdit()
        connection.deleteSurroundingText(outcome.source.length, 0)
        connection.commitText(outcome.insert, 1)
        connection.endBatchEdit()
        undoable = if (start >= 0) Undo(outcome, start - outcome.source.length + outcome.insert.length) else null
        if (outcome.notice != null && settings.showNotes) keyboard?.note(outcome.notice!!)
        return true
    }

    // What space would do, in the strip above the keys. Tapping it converts
    // without the space.
    private fun refreshPreview() {
        val keyboard = keyboard ?: return
        val connection = currentInputConnection
        if (!converting || connection == null || hasSelection(connection)) {
            keyboard.showPreview(null, null)
            return
        }
        val before = textBeforeCaret(connection)
        if (putBack != null && before.endsWith(putBack!!)) {
            keyboard.showPreview("Left as LaTeX", null)
            return
        }
        when (val outcome = Engine.outcome(before, ' ')) {
            is TriggerOutcome.Replace -> {
                val symbols = outcome.insert.dropLast(1)
                keyboard.showPreview("${outcome.source}  →  $symbols") {
                    currentInputConnection?.let { c ->
                        val now = textBeforeCaret(c)
                        replace(c, now, outcome.copy(insert = symbols))
                    }
                }
            }
            is TriggerOutcome.Refuse -> keyboard.showPreview(outcome.reason, null)
            TriggerOutcome.None -> keyboard.showPreview(null, null)
        }
    }

    // MARK: Images

    private fun offerPendingImage(info: EditorInfo) {
        val pending = RenderedImages.pending?.takeIf { it.isFresh } ?: return
        val canInsert = info.contentMimeTypes.orEmpty().any { ClipDescription.compareMimeTypes("image/png", it) }
        keyboard?.offerImage(
            canInsert,
            insert = { insertImage(pending) },
            dismiss = { RenderedImages.clearPending() },
        )
    }

    private fun insertImage(pending: RenderedImages.Pending) {
        RenderedImages.clearPending()
        val connection = currentInputConnection ?: return
        val content = InputContentInfo(pending.uri, ClipDescription(pending.description, arrayOf("image/png")))
        if (!connection.commitContent(content, InputConnection.INPUT_CONTENT_GRANT_READ_URI_PERMISSION, null)) {
            keyboard?.note("This app didn't take the image. It's on the clipboard: hold the text box and tap Paste.")
            return
        }
        // The image stands in for the LaTeX it was made from, if that is
        // still where it was.
        val source = pending.replaces ?: return
        if (textBeforeCaret(connection).endsWith(source)) connection.deleteSurroundingText(source.length, 0)
    }

    // MARK: Helpers

    private fun type(text: String) {
        if (text.length == 1) sendKeyChar(text[0]) else currentInputConnection?.commitText(text, 1)
    }

    private fun hasSelection(connection: InputConnection) = !connection.getSelectedText(0).isNullOrEmpty()

    private fun textBeforeCaret(connection: InputConnection) =
        connection.getTextBeforeCursor(BUFFER, 0)?.toString() ?: ""

    private fun enterLabel(info: EditorInfo): String {
        if (info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0) return "↵"
        return when (info.imeOptions and EditorInfo.IME_MASK_ACTION) {
            EditorInfo.IME_ACTION_SEND -> "Send"
            EditorInfo.IME_ACTION_SEARCH -> "Search"
            EditorInfo.IME_ACTION_GO -> "Go"
            EditorInfo.IME_ACTION_NEXT -> "Next"
            EditorInfo.IME_ACTION_DONE -> "Done"
            else -> "↵"
        }
    }

    private companion object {
        /** As much as the desktop apps keep: the last 64 characters. */
        const val BUFFER = 64

        /** A `$...$` span ending at the caret, or the run since the last space if it has LaTeX in it. */
        fun latexAtCaret(before: String): String? {
            if (before.endsWith("$")) {
                val opening = before.dropLast(1).lastIndexOf('$')
                if (opening >= 0) return before.substring(opening)
            }
            val run = before.takeLastWhile { !it.isWhitespace() }
            return run.takeIf { r -> r.any { it == '\\' || it == '^' || it == '_' } }
        }
    }
}
