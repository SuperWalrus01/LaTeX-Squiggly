package io.github.superwalrus01.squiggly

import android.content.Context
import android.content.SharedPreferences

/** Every switch's key and default, in one place. Read fresh each time. */
class Settings(context: Context) {

    private val preferences: SharedPreferences =
        context.applicationContext.getSharedPreferences("settings", Context.MODE_PRIVATE)

    /** Space after LaTeX converts it, as on the other platforms. */
    var convertOnSpace: Boolean
        get() = preferences.getBoolean(CONVERT_ON_SPACE, true)
        set(value) = preferences.edit().putBoolean(CONVERT_ON_SPACE, value).apply()

    /** Say so when a conversion is approximate or refused. */
    var showNotes: Boolean
        get() = preferences.getBoolean(SHOW_NOTES, true)
        set(value) = preferences.edit().putBoolean(SHOW_NOTES, value).apply()

    var vibrateOnKeys: Boolean
        get() = preferences.getBoolean(VIBRATE_ON_KEYS, true)
        set(value) = preferences.edit().putBoolean(VIBRATE_ON_KEYS, value).apply()

    private companion object {
        const val CONVERT_ON_SPACE = "convertOnSpace"
        const val SHOW_NOTES = "showNotes"
        const val VIBRATE_ON_KEYS = "vibrateOnKeys"
    }
}
