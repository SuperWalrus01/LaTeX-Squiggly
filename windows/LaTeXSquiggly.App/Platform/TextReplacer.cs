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

    public static void Perform(Replacement replacement)
    {
        var events = new List<Native.INPUT>(replacement.DeleteCount * 2 + replacement.Insert.Length * 2);

        for (var i = 0; i < replacement.DeleteCount; i++)
        {
            events.Add(Key(Native.VK_BACK, up: false));
            events.Add(Key(Native.VK_BACK, up: true));
        }

        // One UTF-16 unit per event. A surrogate pair arrives as two events and
        // Windows reassembles it, which is how the double-struck letters survive.
        foreach (var unit in replacement.Insert)
        {
            events.Add(Unicode(unit, up: false));
            events.Add(Unicode(unit, up: true));
        }

        if (events.Count == 0) return;
        var array = events.ToArray();
        Native.SendInput((uint)array.Length, array, System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>());
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
