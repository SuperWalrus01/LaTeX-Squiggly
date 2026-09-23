namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// What every key types under one keyboard layout, worked out in advance.
///
/// Turning a keystroke into text is ToUnicodeEx, and calling it inside the
/// keyboard hook is what hung this app: while a low-level hook is pending, the
/// call can wait on the very input queue the hook is holding up. So it is never
/// called with a keystroke in flight. Instead, when the foreground layout
/// changes, the input thread builds this table between keystrokes, asking
/// ToUnicodeEx once for every key in every combination of Shift, AltGr and Caps
/// Lock, and the hook only ever reads from the table.
///
/// Dead keys and anything the table has no answer for come back null, and the
/// caller forgets its buffer, which is the safe response to a keystroke it
/// cannot model.
/// </summary>
internal sealed class KeyboardLayoutTable
{
    /// <summary>Shift, AltGr and Caps Lock, on or off: eight combinations per key.</summary>
    private const int States = 8;

    private const int Keys = 256;

    /// <summary>Indexed by key * States + state.</summary>
    private readonly string?[] _characters;

    /// <summary>A table with no answers, used until the first real one is built.</summary>
    public static readonly KeyboardLayoutTable Empty = new(new string?[Keys * States]);

    /// <summary>The layout this table describes.</summary>
    public IntPtr Layout { get; private init; } = IntPtr.Zero;

    /// <summary>How many key and state pairs type something, for the diagnostics log.</summary>
    public int Mapped { get; private init; }

    public static KeyboardLayoutTable Build(IntPtr layout)
    {
        var characters = new string?[Keys * States];
        var mapped = Fill(characters, layout);
        return new KeyboardLayoutTable(characters) { Layout = layout, Mapped = mapped };
    }

    private KeyboardLayoutTable(string?[] characters) => _characters = characters;

    private static int Fill(string?[] characters, IntPtr layout)
    {
        var state = new byte[256];
        var buffer = new char[8];
        var mapped = 0;

        for (var key = 0; key < Keys; key++)
        {
            // The mouse buttons and the like below 8, and VK_PACKET, which is
            // how synthetic Unicode input arrives and has no layout meaning.
            if (key <= 0x07 || key == Native.VK_PACKET) continue;

            var scanCode = Native.MapVirtualKeyExW((uint)key, Native.MAPVK_VK_TO_VSC, layout);
            for (var combination = 0; combination < States; combination++)
            {
                Array.Clear(state);
                if ((combination & 1) != 0) state[Native.VK_SHIFT] = 0x80;
                if ((combination & 2) != 0)
                {
                    // AltGr is Control and Alt together, as far as Windows is concerned.
                    state[Native.VK_CONTROL] = 0x80;
                    state[Native.VK_MENU] = 0x80;
                }
                if ((combination & 4) != 0) state[Native.VK_CAPITAL] = 0x01;

                // Bit 2 tells Windows not to disturb the kernel's keyboard state,
                // which is what keeps dead keys working for the user.
                var written = Native.ToUnicodeEx((uint)key, scanCode, state, buffer, buffer.Length, 4, layout);
                if (written > 0)
                {
                    characters[key * States + combination] = new string(buffer, 0, Math.Min(written, buffer.Length));
                    mapped++;
                }
            }
        }
        return mapped;
    }

    /// <summary>The text a key types in the given state, or null if it types nothing we can model.</summary>
    public string? Lookup(int key, bool shift, bool altGr, bool caps)
    {
        if ((uint)key >= Keys) return null;
        var combination = (shift ? 1 : 0) | (altGr ? 2 : 0) | (caps ? 4 : 0);
        return _characters[key * States + combination];
    }
}
