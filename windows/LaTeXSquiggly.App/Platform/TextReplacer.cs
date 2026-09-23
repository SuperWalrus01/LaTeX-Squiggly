using LaTeXSquiggly.Core.Input;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// Turns a Replacement into synthetic keystrokes.
///
/// Insertion goes through SendInput with KEYEVENTF_UNICODE, never the
/// clipboard: clipboard swapping destroys whatever the user had copied and
/// races against anything else reading it.
///
/// Unlike the Mac, the whole replacement is one SendInput call. Windows queues
/// the array atomically and in order, so there is no need for the pauses the
/// Mac version has to insert between events, and no window in which the user's
/// next keystroke can arrive in the middle of a replacement.
/// </summary>
internal static class TextReplacer
{
    /// <summary>
    /// Stamped on every event we post so the hook can recognise its own output
    /// and not feed on it. The Mac calls this the same thing and uses the same
    /// four letters.
    /// </summary>
    internal static readonly IntPtr SyntheticMarker = new(0x4C545855);   // "LTXU"

    /// <summary>
    /// False when Windows accepted fewer events than it was given, which it
    /// does when another program's input is being blocked or a secure desktop
    /// is in front. The caller logs it: a replacement that half happened is the
    /// one outcome worth knowing about afterwards.
    /// </summary>
    public static bool Perform(Replacement replacement)
    {
        // An array sized exactly, rather than a list grown and copied: this
        // runs on the input thread, where allocation is kept to the minimum.
        var count = replacement.DeleteCount * 2 + replacement.Insert.Length * 2;
        if (count == 0) return true;
        var events = new Native.INPUT[count];
        var next = 0;

        for (var i = 0; i < replacement.DeleteCount; i++)
        {
            events[next++] = Key(Native.VK_BACK, up: false);
            events[next++] = Key(Native.VK_BACK, up: true);
        }

        // One UTF-16 unit per event. A surrogate pair arrives as two events and
        // Windows reassembles it, which is how the double-struck letters survive.
        foreach (var unit in replacement.Insert)
        {
            events[next++] = Unicode(unit, up: false);
            events[next++] = Unicode(unit, up: true);
        }

        var sent = Native.SendInput((uint)events.Length, events,
            System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>());
        return sent == (uint)events.Length;
    }

    private static Native.INPUT Key(int virtualKey, bool up) => new()
    {
        type = Native.INPUT_KEYBOARD,
        u = new Native.INPUTUNION
        {
            ki = new Native.KEYBDINPUT
            {
                wVk = (ushort)virtualKey,
                wScan = 0,
                dwFlags = up ? Native.KEYEVENTF_KEYUP : 0,
                time = 0,
                dwExtraInfo = SyntheticMarker,
            },
        },
    };

    private static Native.INPUT Unicode(char unit, bool up) => new()
    {
        type = Native.INPUT_KEYBOARD,
        u = new Native.INPUTUNION
        {
            ki = new Native.KEYBDINPUT
            {
                wVk = 0,
                wScan = unit,
                dwFlags = Native.KEYEVENTF_UNICODE | (up ? Native.KEYEVENTF_KEYUP : 0),
                time = 0,
                dwExtraInfo = SyntheticMarker,
            },
        },
    };
}
