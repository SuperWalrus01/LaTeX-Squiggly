package io.github.superwalrus01.squiggly.keyboard

/** The keyboard's pages. Symbols is a grid of the engine's own table. */
enum class Page { LETTERS, NUMBERS, SYMBOLS }

enum class KeyKind { CHARACTER, SHIFT, DELETE, SPACE, ENTER, PAGE, SWITCH_KEYBOARD, RENDER, SPACER }

class Key(
    val label: String,
    val kind: KeyKind = KeyKind.CHARACTER,
    val weight: Float = 1f,
    /** What a character key types, when it is not its label. */
    val output: String = label,
    val page: Page? = null,
    val description: String = label,
) {
    val isSpecial: Boolean get() = kind != KeyKind.CHARACTER && kind != KeyKind.SPACE && kind != KeyKind.SPACER
}

/**
 * The layouts. A maths keyboard, not a replacement for the user's own: QWERTY
 * for command names, and a top row of the characters LaTeX is made of, which
 * an ordinary phone keyboard hides two pages deep.
 */
object Layouts {

    private fun row(characters: String) = characters.map { Key(it.toString()) }

    private val latexRow = row("\\{}^_\$[]").map {
        if (it.label == "\\") Key("\\", description = "Backslash") else it
    }

    private val shift = Key("\u21e7", KeyKind.SHIFT, 1.5f, description = "Shift")
    private val delete = Key("\u232b", KeyKind.DELETE, 1.5f, description = "Delete")
    private val switchKeyboard = Key("\ud83c\udf10", KeyKind.SWITCH_KEYBOARD, description = "Back to your keyboard")
    private val render = Key("Render", KeyKind.RENDER, 1.5f, description = "Render the LaTeX as an image")
    private val space = Key("space", KeyKind.SPACE, 4f, output = " ", description = "Space")
    private val enter = Key("\u21b5", KeyKind.ENTER, 1.5f, description = "Enter")

    val letters: List<List<Key>> = listOf(
        latexRow,
        row("qwertyuiop"),
        listOf(Key("", KeyKind.SPACER, 0.5f)) + row("asdfghjkl") + Key("", KeyKind.SPACER, 0.5f),
        listOf(shift) + row("zxcvbnm") + delete,
        listOf(Key("?123", KeyKind.PAGE, 1.5f, page = Page.NUMBERS, description = "Numbers"),
            switchKeyboard, render, space, Key("."), enter),
    )

    val numbers: List<List<Key>> = listOf(
        latexRow,
        row("1234567890"),
        row("+-=*/<>|'\""),
        listOf(Key("\u03b1\u2211", KeyKind.PAGE, 1.5f, page = Page.SYMBOLS, description = "Symbols")) +
            row(",:;!?%&") + delete,
        listOf(Key("ABC", KeyKind.PAGE, 1.5f, page = Page.LETTERS, description = "Letters"),
            switchKeyboard, render, space, Key(","), enter),
    )

    /** Below the symbol grid, which fills the rows above. */
    val symbolsBottom: List<Key> = listOf(
        Key("ABC", KeyKind.PAGE, 1.5f, page = Page.LETTERS, description = "Letters"),
        switchKeyboard, render, space, delete, enter,
    )
}
