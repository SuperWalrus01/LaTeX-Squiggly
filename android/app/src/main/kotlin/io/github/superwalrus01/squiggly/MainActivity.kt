package io.github.superwalrus01.squiggly

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.provider.Settings as SystemSettings
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import io.github.superwalrus01.squiggly.render.RendererActivity

/**
 * The app's one screen: setting up the keyboard, a box to try it in, the
 * renderer, and the few switches there are. Also the keyboard's settings
 * page, which the system links to from its keyboard list.
 */
class MainActivity : Activity() {

    private lateinit var settings: Settings
    private lateinit var enableStep: TextView
    private lateinit var enableButton: Button
    private lateinit var switchStep: TextView

    private val density by lazy { resources.displayMetrics.density }
    private fun dp(value: Float) = (value * density + 0.5f).toInt()

    private val night by lazy {
        (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }
    private val accent by lazy { if (night) 0xFFF27A1A.toInt() else 0xFFD9620F.toInt() }
    private val ink by lazy { if (night) 0xFFF2F0EB.toInt() else 0xFF1C1B19.toInt() }
    private val muted by lazy { if (night) 0xFFA8A49C.toInt() else 0xFF6B675F.toInt() }
    private val surface by lazy { if (night) 0xFF2B2926.toInt() else 0xFFFFFFFF.toInt() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        settings = Settings(this)

        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20f), dp(24f), dp(20f), dp(32f))
        }

        column.addView(label("LaTeX Squiggly", 28f, accent, bold = true))
        column.addView(label("Type LaTeX, get real characters. \\alpha becomes α.", 16f, muted).spaced(4f, 20f))

        // 1. Turn it on.
        enableStep = label("", 15f, ink)
        enableButton = button("Open keyboard settings") {
            startActivity(Intent(SystemSettings.ACTION_INPUT_METHOD_SETTINGS))
        }
        column.addView(card("1. Turn on the maths keyboard", enableStep, enableButton))

        // 2. Switch to it.
        switchStep = label("", 15f, ink)
        column.addView(card(
            "2. Switch to it for maths",
            switchStep,
            label("Keep your usual keyboard for everything else. On the maths keyboard, " +
                "🌐 takes you straight back to it; hold 🌐 to choose another.", 14f, muted),
            button("Choose keyboard") { getSystemService(InputMethodManager::class.java)?.showInputMethodPicker() },
        ))

        // Try it.
        val tryBox = EditText(this).apply {
            hint = "Type \\alpha, then space"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 2
            setTextColor(ink)
            setHintTextColor(muted)
        }
        column.addView(card(
            "Try it",
            tryBox,
            label("\\int_0^1, \\frac{1}{2}, \$x^2\$ and \\mathbb{R} all work. When something has no exact " +
                "character, the strip above the keys says so instead of guessing.", 14f, muted),
        ))

        // The renderer.
        column.addView(card(
            "Turn LaTeX into an image",
            label("For maths plain text can't hold, like a stacked fraction or a matrix. Copy it as a " +
                "picture, or tap Render on the keyboard and insert it where you were typing.", 14f, muted),
            button("Open the renderer") { RendererActivity.open(this, null) },
        ))

        // Selection menu.
        column.addView(card(
            "In any app",
            label("Select LaTeX anywhere, then choose Convert LaTeX or Render LaTeX from the menu " +
                "that appears (it may be under ⋮). Works with whichever keyboard you use.", 14f, muted),
        ))

        // Settings.
        column.addView(card(
            "Settings",
            toggle("Convert LaTeX when I press space", settings.convertOnSpace) { settings.convertOnSpace = it },
            toggle("Tell me when a conversion is approximate", settings.showNotes) { settings.showNotes = it },
            toggle("Vibrate on key press", settings.vibrateOnKeys) { settings.vibrateOnKeys = it },
        ))

        column.addView(label(
            "This app has no internet access, and Android enforces that: it never asked for the " +
                "permission. Nothing you type leaves your phone.",
            13f, muted,
        ).spaced(20f, 4f))
        column.addView(label("Version ${packageManager.getPackageInfo(packageName, 0).versionName}", 13f, muted))

        val scroll = ScrollView(this).apply { addView(column) }
        padForSystemBars(scroll)
        setContentView(scroll)
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    // The keyboard picker is a dialog over this screen; choosing in it only
    // gives the focus back.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) refresh()
    }

    private fun refresh() {
        val manager = getSystemService(InputMethodManager::class.java)
        val enabled = manager?.enabledInputMethodList.orEmpty().any { it.packageName == packageName }
        val current = SystemSettings.Secure.getString(contentResolver, SystemSettings.Secure.DEFAULT_INPUT_METHOD)
            ?.startsWith("$packageName/") == true

        enableStep.text = if (enabled) "✓ Turned on." else
            "Turn on “LaTeX Squiggly maths keyboard”. Android warns that a keyboard can " +
            "collect what you type; this one has no way to send it anywhere."
        enableButton.visibility = if (enabled) View.GONE else View.VISIBLE
        switchStep.text = when {
            current -> "✓ It's your keyboard right now."
            enabled -> "Tap the keyboard button at the bottom of the screen, or below."
            else -> "Once it's on, switch to it whenever you need maths."
        }
    }

    // MARK: Building the screen

    private fun label(value: String, size: Float, colour: Int, bold: Boolean = false) = TextView(this).apply {
        text = value
        textSize = size
        setTextColor(colour)
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun button(title: String, action: () -> Unit) = Button(this).apply {
        text = title
        isAllCaps = false
        setOnClickListener { action() }
    }

    private fun toggle(title: String, on: Boolean, changed: (Boolean) -> Unit) = Switch(this).apply {
        text = title
        textSize = 15f
        setTextColor(ink)
        isChecked = on
        setPadding(0, dp(8f), 0, dp(8f))
        setOnCheckedChangeListener { _, checked -> changed(checked) }
    }

    private fun card(title: String, vararg content: View) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16f), dp(14f), dp(16f), dp(14f))
        background = GradientDrawable().apply {
            cornerRadius = dp(14f).toFloat()
            setColor(surface)
        }
        addView(label(title, 17f, ink, bold = true).spaced(0f, 6f))
        for (view in content) addView(view.spaced(4f, 4f))
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(12f) }
        gravity = Gravity.START
    }

    private fun <T : View> T.spaced(top: Float, bottom: Float): T = apply {
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply {
            topMargin = dp(top)
            bottomMargin = dp(bottom)
        }
    }

    // Targeting Android 15 draws the window under the system bars.
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
}
