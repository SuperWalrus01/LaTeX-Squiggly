package io.github.superwalrus01.squiggly.keyboard

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.github.superwalrus01.squiggly.engine.Engine
import io.github.superwalrus01.squiggly.engine.SymbolEntry

/**
 * The keyboard's window: a strip along the top that says what space will do,
 * or why it will not, and the keys below it. Built in code from Layouts, with
 * platform views only.
 *
 * Everything a key does is the service's business; this only draws, and
 * remembers the page and the shift state.
 */
@SuppressLint("ViewConstructor")
class KeyboardView(context: Context, private val service: KeyboardService) : LinearLayout(context) {

    private enum class Shift { OFF, ONCE, LOCKED }

    private val palette = Palette.of(context)
    private val density = resources.displayMetrics.density
    private fun dp(value: Float) = (value * density + 0.5f).toInt()
    private val keyHeight = dp(48f)
    private val handler = Handler(Looper.getMainLooper())

    // MARK: The strip

    private val stripText = TextView(context).apply {
        setTextColor(palette.text)
        textSize = 15f
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(12f), 0, dp(8f), 0)
    }
    private val stripAction = TextView(context).apply {
        setTextColor(palette.accent)
        typeface = Typeface.DEFAULT_BOLD
        textSize = 15f
        gravity = Gravity.CENTER
        setPadding(dp(12f), 0, dp(12f), 0)
        visibility = GONE
    }
    private val stripDismiss = TextView(context).apply {
        text = "✕"
        contentDescription = "Dismiss"
        setTextColor(palette.muted)
        textSize = 15f
        gravity = Gravity.CENTER
        setPadding(dp(12f), 0, dp(12f), 0)
        visibility = GONE
    }
    private val strip = LinearLayout(context).apply {
        orientation = HORIZONTAL
        addView(stripText, LayoutParams(0, LayoutParams.MATCH_PARENT, 1f))
        addView(stripAction, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
        addView(stripDismiss, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
    }

    /** A note outranks the preview for a few seconds, then the preview comes back. */
    private var noteShowing = false
    private var offerShowing = false
    private var preview: Pair<String, (() -> Unit)?>? = null
    private val endNote = Runnable { noteShowing = false; drawStrip() }

    // MARK: The keys

    private val pages = FrameLayout(context)
    private var page = Page.LETTERS
    private var shift = Shift.OFF
    private var lastShiftTap = 0L
    private val letterKeys = ArrayList<Pair<TextView, Key>>()
    private var enterKeys = ArrayList<TextView>()
    private var enterLabel = "↵"
    private var symbolCategory: String? = null

    init {
        orientation = VERTICAL
        setBackgroundColor(palette.background)
        setPadding(dp(3f), 0, dp(3f), dp(4f))
        addView(strip, LayoutParams(LayoutParams.MATCH_PARENT, dp(44f)))
        addView(pages, LayoutParams(LayoutParams.MATCH_PARENT, keyHeight * 5))
        show(Page.LETTERS)
        drawStrip()
    }

    // MARK: Pages

    fun show(next: Page) {
        page = next
        pages.removeAllViews()
        letterKeys.clear()
        enterKeys.clear()
        val content = when (next) {
            Page.LETTERS -> rows(Layouts.letters)
            Page.NUMBERS -> rows(Layouts.numbers)
            Page.SYMBOLS -> symbols()
        }
        pages.addView(content)
        drawShift()
    }

    private fun rows(layout: List<List<Key>>): View = LinearLayout(context).apply {
        orientation = VERTICAL
        for (keys in layout) addView(row(keys), LayoutParams(LayoutParams.MATCH_PARENT, keyHeight))
    }

    private fun row(keys: List<Key>): View = LinearLayout(context).apply {
        orientation = HORIZONTAL
        for (key in keys) {
            val view = if (key.kind == KeyKind.SPACER) View(context) else keyView(key)
            addView(view, LayoutParams(0, LayoutParams.MATCH_PARENT, key.weight))
        }
    }

    // The engine's table, by category, with the category tabs above it.
    // Tapping types the symbol; holding says which command it is.
    private fun symbols(): View {
        val entries = Engine.symbolEntries
        val categories = entries.map(SymbolEntry::category).distinct()
        val current = symbolCategory?.takeIf { it in categories } ?: categories.first()

        val tabs = LinearLayout(context).apply { orientation = HORIZONTAL }
        for (category in categories) {
            tabs.addView(TextView(context).apply {
                text = category
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(dp(12f), 0, dp(12f), 0)
                setTextColor(if (category == current) palette.accent else palette.muted)
                if (category == current) typeface = Typeface.DEFAULT_BOLD
                setOnClickListener {
                    symbolCategory = category
                    show(Page.SYMBOLS)
                }
            }, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT))
        }

        val grid = LinearLayout(context).apply { orientation = VERTICAL }
        for (chunk in entries.filter { it.category == current }.chunked(COLUMNS)) {
            val keys = chunk.map { Key(it.glyph, output = it.glyph, description = it.unicodeName.lowercase()) }
            val padded = keys + List(COLUMNS - keys.size) { Key("", KeyKind.SPACER) }
            grid.addView(row(padded).also { line ->
                // Holding a symbol names its command, so the keyboard teaches
                // the LaTeX as it is used.
                chunk.forEachIndexed { i, entry ->
                    (line as LinearLayout).getChildAt(i).setOnLongClickListener {
                        note("\\${entry.command}  —  ${entry.unicodeName.lowercase()}")
                        true
                    }
                }
            }, LayoutParams(LayoutParams.MATCH_PARENT, keyHeight))
        }

        return LinearLayout(context).apply {
            orientation = VERTICAL
            addView(HorizontalScrollView(context).apply {
                isHorizontalScrollBarEnabled = false
                addView(tabs)
            }, LayoutParams(LayoutParams.MATCH_PARENT, dp(36f)))
            addView(ScrollView(context).apply { addView(grid) },
                LayoutParams(LayoutParams.MATCH_PARENT, keyHeight * 4 - dp(36f)))
            addView(row(Layouts.symbolsBottom), LayoutParams(LayoutParams.MATCH_PARENT, keyHeight))
        }
    }

    // MARK: Keys

    @SuppressLint("ClickableViewAccessibility")
    private fun keyView(key: Key): TextView = TextView(context).apply {
        text = key.label
        contentDescription = key.description
        gravity = Gravity.CENTER
        textSize = if (key.label.length > 2) 14f else 21f
        setTextColor(palette.text)
        background = keyBackground(key.isSpecial)
        isSoundEffectsEnabled = false
        val inset = dp(3f)
        // Margins would shrink the touch target; padding keeps it, and the
        // background is inset instead.
        setPadding(inset, inset, inset, inset)

        when (key.kind) {
            KeyKind.CHARACTER -> if (page == Page.LETTERS && key.label.length == 1 && key.label[0].isLetter()) {
                letterKeys.add(this to key)
            }
            KeyKind.ENTER -> { enterKeys.add(this); text = enterLabel }
            KeyKind.SPACE -> setTextColor(palette.muted)
            KeyKind.RENDER -> setTextColor(palette.accent)
            else -> Unit
        }

        if (key.kind == KeyKind.DELETE) {
            // Held, it repeats, as every keyboard's delete does.
            val repeat = object : Runnable {
                override fun run() {
                    service.onDelete()
                    handler.postDelayed(this, REPEAT_INTERVAL)
                }
            }
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        view.isPressed = true
                        tap(view)
                        service.onDelete()
                        handler.postDelayed(repeat, REPEAT_DELAY)
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        view.isPressed = false
                        handler.removeCallbacks(repeat)
                    }
                }
                true
            }
        } else {
            setOnClickListener { view ->
                tap(view)
                pressed(key)
            }
        }
        if (key.kind == KeyKind.SWITCH_KEYBOARD) {
            setOnLongClickListener { service.showKeyboardPicker(); true }
        }
    }

    private fun pressed(key: Key) {
        when (key.kind) {
            KeyKind.CHARACTER -> {
                // Shift is for letters: a symbol typed after it stays as it is.
                val output = if (shift != Shift.OFF && page == Page.LETTERS) key.output.uppercase() else key.output
                service.onText(output)
                if (shift == Shift.ONCE) {
                    shift = Shift.OFF
                    drawShift()
                }
            }
            KeyKind.SHIFT -> {
                val now = System.currentTimeMillis()
                shift = when {
                    shift == Shift.ONCE && now - lastShiftTap < DOUBLE_TAP -> Shift.LOCKED
                    shift == Shift.OFF -> Shift.ONCE
                    else -> Shift.OFF
                }
                lastShiftTap = now
                drawShift()
            }
            KeyKind.SPACE -> service.onSpace()
            KeyKind.ENTER -> service.onEnter()
            KeyKind.PAGE -> show(key.page ?: Page.LETTERS)
            KeyKind.SWITCH_KEYBOARD -> service.onSwitchKeyboard()
            KeyKind.RENDER -> service.onRender()
            KeyKind.DELETE, KeyKind.SPACER -> Unit
        }
    }

    private fun tap(view: View) {
        if (service.settings.vibrateOnKeys) view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    }

    private fun drawShift() {
        for ((view, key) in letterKeys) view.text = if (shift == Shift.OFF) key.label else key.label.uppercase()
    }

    fun setEnterLabel(label: String) {
        enterLabel = label
        for (view in enterKeys) view.text = label
    }

    /** A new text box: back to letters, shift off, nothing left in the strip. */
    fun reset() {
        shift = Shift.OFF
        noteShowing = false
        offerShowing = false
        handler.removeCallbacks(endNote)
        if (page != Page.LETTERS) show(Page.LETTERS) else drawShift()
        drawStrip()
    }

    // MARK: Strip

    /** What space would do now, tappable when it is a conversion. */
    fun showPreview(text: String?, apply: (() -> Unit)?) {
        preview = text?.let { it to apply }
        drawStrip()
    }

    /** Something the user should be told, such as why LaTeX was left alone. */
    fun note(text: String) {
        noteShowing = true
        offerShowing = false
        stripText.text = text
        stripText.setTextColor(palette.text)
        stripText.setOnClickListener(null)
        stripAction.visibility = GONE
        stripDismiss.visibility = GONE
        handler.removeCallbacks(endNote)
        handler.postDelayed(endNote, NOTE_DURATION)
    }

    /** A rendered image is waiting. Insert when the text box takes images, else say how to paste. */
    fun offerImage(canInsert: Boolean, insert: () -> Unit, dismiss: () -> Unit) {
        offerShowing = true
        noteShowing = false
        handler.removeCallbacks(endNote)
        stripText.setOnClickListener(null)
        stripText.setTextColor(palette.text)
        stripText.text = if (canInsert) "Your equation is ready." else "Copied. Hold the text box and tap Paste."
        stripAction.text = "Insert"
        stripAction.visibility = if (canInsert) VISIBLE else GONE
        stripAction.setOnClickListener { offerShowing = false; insert(); drawStrip() }
        stripDismiss.visibility = VISIBLE
        stripDismiss.setOnClickListener { offerShowing = false; dismiss(); drawStrip() }
    }

    private fun drawStrip() {
        if (noteShowing || offerShowing) return
        stripAction.visibility = GONE
        stripDismiss.visibility = GONE
        val current = preview
        if (current == null) {
            stripText.text = "Type LaTeX, then space"
            stripText.setTextColor(palette.muted)
            stripText.setOnClickListener(null)
        } else {
            stripText.text = current.first
            val apply = current.second
            stripText.setTextColor(if (apply != null) palette.text else palette.muted)
            stripText.setOnClickListener(apply?.let { action -> OnClickListener { action() } })
        }
    }

    // MARK: Drawing

    private fun keyBackground(special: Boolean): StateListDrawable {
        fun shape(colour: Int) = GradientDrawable().apply {
            cornerRadius = dp(6f).toFloat()
            setColor(colour)
        }
        val inset = dp(3f)
        fun inset(drawable: GradientDrawable) =
            android.graphics.drawable.InsetDrawable(drawable, inset, inset, inset, inset)
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_pressed), inset(shape(palette.pressed)))
            addState(intArrayOf(), inset(shape(if (special) palette.specialKey else palette.key)))
        }
    }

    /** Light and dark, following the system. */
    private class Palette(
        val background: Int, val key: Int, val specialKey: Int, val pressed: Int,
        val text: Int, val muted: Int, val accent: Int,
    ) {
        companion object {
            fun of(context: Context): Palette {
                val night = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                    Configuration.UI_MODE_NIGHT_YES
                return if (night) {
                    Palette(0xFF1C1B19.toInt(), 0xFF3A3835.toInt(), 0xFF2B2926.toInt(), 0xFF55524D.toInt(),
                        0xFFF2F0EB.toInt(), 0xFFA8A49C.toInt(), 0xFFF27A1A.toInt())
                } else {
                    Palette(0xFFE8E5DE.toInt(), 0xFFFFFFFF.toInt(), 0xFFD3CFC6.toInt(), 0xFFBDB8AE.toInt(),
                        0xFF1C1B19.toInt(), 0xFF6B675F.toInt(), 0xFFD9620F.toInt())
                }
            }
        }
    }

    private companion object {
        const val COLUMNS = 8
        const val REPEAT_DELAY = 400L
        const val REPEAT_INTERVAL = 60L
        const val DOUBLE_TAP = 350L
        const val NOTE_DURATION = 4000L
    }
}
