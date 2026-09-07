using LaTeXSquiggly.Core.Input;
using LaTeXSquiggly.Core.Suppression;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// Owns the low-level keyboard and mouse hooks and the rolling input buffer.
///
/// Threading: both hooks are installed from the UI thread and Windows calls them
/// back on that same thread, so the buffer is only ever touched there. The
/// replacement is sent synchronously from inside the callback, for the same
/// reason the Mac app posts synchronously: deferring it leaves a window in which
/// the next keystroke arrives before the backspaces do, and the delete count
/// then eats a character the user meant to keep.
/// </summary>
internal sealed class KeyboardHook : IDisposable
{
    private readonly InputBuffer _buffer = new();
    private IntPtr _keyboard = IntPtr.Zero;
    private IntPtr _mouse = IntPtr.Zero;

    // Windows only holds a weak reference to a hook procedure, so these fields
    // are what stop the delegates from being collected out from under it.
    private Native.HookProc? _keyboardProc;
    private Native.HookProc? _mouseProc;

    /// <summary>Set while we are typing, so our own events cannot re-enter.</summary>
    private bool _replacing;

    /// <summary>
    /// The key whose release must be swallowed because we swallowed its press.
    /// Leaving a stray key-up behind confuses anything that tracks key state.
    /// </summary>
    private int _suppressedKeyUp = -1;

    /// <summary>Called with an explanation the user needs to see.</summary>
    public Action<string>? OnNotice { get; set; }

    /// <summary>
    /// Captured when the hook is built, on the UI thread, rather than read
    /// inside the callback. Windows calls the hook during message dispatch, and
    /// relying on the ambient context being set at that moment is the kind of
    /// assumption that fails silently: notices would simply stop appearing.
    /// </summary>
    private readonly System.Threading.SynchronizationContext? _ui =
        System.Threading.SynchronizationContext.Current;

    /// <summary>Decides whether conversion is allowed wherever the user is typing.</summary>
    public Func<SuppressionDecision>? Suppression { get; set; }

    public bool IsRunning => _keyboard != IntPtr.Zero;

    public bool Start()
    {
        if (IsRunning) return true;

        _keyboardProc = KeyboardCallback;
        _mouseProc = MouseCallback;
        var module = Native.GetModuleHandleW(null);

        _keyboard = Native.SetWindowsHookExW(Native.WH_KEYBOARD_LL, _keyboardProc, module, 0);
        if (_keyboard == IntPtr.Zero)
        {
            _keyboardProc = null;
            _mouseProc = null;
            return false;
        }
        // Watched purely to forget: a click puts the caret somewhere the buffer
        // knows nothing about. Failing to install this is not fatal, it only
        // costs the click reset, so it is not checked.
        _mouse = Native.SetWindowsHookExW(Native.WH_MOUSE_LL, _mouseProc, module, 0);

        _buffer.Reset();
        return true;
    }

    public void Stop()
    {
        if (_keyboard != IntPtr.Zero) Native.UnhookWindowsHookEx(_keyboard);
        if (_mouse != IntPtr.Zero) Native.UnhookWindowsHookEx(_mouse);
        _keyboard = IntPtr.Zero;
        _mouse = IntPtr.Zero;
        _keyboardProc = null;
        _mouseProc = null;
        _buffer.Reset();
    }

    /// <summary>
    /// Switching apps moves the caret somewhere we know nothing about, so the
    /// buffer stops describing the text in front of it.
    /// </summary>
    public void ResetBuffer() => _buffer.Reset();

    public void Dispose() => Stop();

    // MARK: The callbacks

    private IntPtr MouseCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var message = (int)wParam;
            if (message is Native.WM_LBUTTONDOWN or Native.WM_RBUTTONDOWN or Native.WM_MBUTTONDOWN)
            {
                _buffer.Reset();
            }
        }
        return Native.CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private IntPtr KeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0) return Native.CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);

        try
        {
            var handled = Handle((int)wParam, lParam);
            if (handled) return new IntPtr(1);
        }
        catch (Exception)
        {
            // A hook that throws is a hook Windows removes, which would leave
            // the user with a keyboard that has quietly stopped converting and
            // no way to tell. Swallowing is the lesser evil; the keystroke is
            // passed through untouched.
            _buffer.Reset();
        }
        return Native.CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    /// <returns>True to swallow the keystroke.</returns>
    private bool Handle(int message, IntPtr lParam)
    {
        var data = System.Runtime.InteropServices.Marshal
            .PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);

        // Our own synthetic keystrokes come back around; ignore them or the
        // replacement feeds itself.
        if (data.dwExtraInfo == TextReplacer.SyntheticMarker || _replacing) return false;

        var isKeyUp = message is Native.WM_KEYUP or Native.WM_SYSKEYUP;
        if (isKeyUp)
        {
            // Swallow the release of a press we swallowed, and nothing else.
            if (_suppressedKeyUp >= 0 && data.vkCode == (uint)_suppressedKeyUp)
            {
                _suppressedKeyUp = -1;
                return true;
            }
            return false;
        }
        if (message is not (Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN)) return false;

        var key = (int)data.vkCode;

        // Modifiers produce a key-down of their own on Windows, unlike the Mac
        // where they are a separate kind of event entirely. Forgetting the
        // buffer on one would break every capital letter: \Delta needs a Shift.
        if (IsModifier(key)) return false;

        // Per-app suppression, checked before anything is remembered: in an
        // excluded app no buffer accumulates, so a replacement there is not
        // declined late, it is structurally impossible.
        var decision = Suppression?.Invoke();
        if (decision is not null && decision.IsSuppressed)
        {
            if (!_buffer.IsEmpty) _buffer.Reset();
            return false;
        }

        var control = Down(Native.VK_CONTROL);
        var alt = Down(Native.VK_MENU);
        var windows = Down(Native.VK_LWIN) || Down(Native.VK_RWIN);

        // Control chords and Windows chords are shortcuts, not text. Control
        // *with* Alt is left alone: that is AltGr, which types real characters
        // on a great many layouts, and treating it as a shortcut would make the
        // app useless outside the English-speaking world.
        if (windows || (control && !alt) || (alt && !control))
        {
            _buffer.Reset();
            return false;
        }

        // Tab is deliberately absent: it produces U+0009 and is handled below as
        // a terminator, not as navigation.
        switch (key)
        {
            case Native.VK_BACK:
                _buffer.DeleteBackward();
                return false;
            case Native.VK_DELETE:
                // Deletes ahead of the caret, which the buffer does not model.
                _buffer.Reset();
                return false;
            case Native.VK_RETURN or Native.VK_ESCAPE
                or Native.VK_LEFT or Native.VK_RIGHT or Native.VK_UP or Native.VK_DOWN
                or Native.VK_HOME or Native.VK_END or Native.VK_PRIOR or Native.VK_NEXT:
                _buffer.Reset();
                return false;
        }

        var typed = TypedString(data);
        if (typed is null || typed.Length == 0)
        {
            // Dead keys, function keys and anything else we cannot model.
            // Forgetting is the safe response.
            _buffer.Reset();
            return false;
        }

        if (typed.Length == 1 && TriggerDetector.Terminators.Contains(typed[0]))
        {
            return HandleTerminator(typed[0], key);
        }

        _buffer.Insert(typed);
        return false;
    }

    private bool HandleTerminator(char character, int key)
    {
        var outcome = TriggerDetector.Outcome(_buffer.Text, character);

        switch (outcome.Kind)
        {
            case TriggerKind.None:
                _buffer.Insert(character.ToString());
                return false;

            case TriggerKind.Replace:
                _buffer.Reset();

                // A browser tab can change without the foreground window
                // changing, so this asks again at the last instant at which the
                // answer is still free of consequences.
                var decision = Suppression?.Invoke();
                if (decision is not null && decision.Reason is not null)
                {
                    Notify($"Left as you typed it, {decision.Reason.Explanation}.");
                    return false;
                }

                _replacing = true;
                try { TextReplacer.Perform(outcome.Replacement!); }
                finally { _replacing = false; }

                if (outcome.Replacement!.Notice is not null) Notify(outcome.Replacement.Notice);

                // Suppress the terminator: the replacement types it back, so
                // letting the original through would double it.
                _suppressedKeyUp = key;
                return true;

            default:
                _buffer.Reset();
                Notify(outcome.Reason!);
                // The user's text is left exactly as they typed it.
                return false;
        }
    }

    /// <summary>
    /// UI work must never run inside a hook callback: Windows removes a hook
    /// that takes too long, and it does so silently.
    /// </summary>
    private void Notify(string message)
    {
        var notice = OnNotice;
        if (notice is null) return;
        if (_ui is not null) _ui.Post(_ => notice(message), null);
        else notice(message);
    }

    private static bool IsModifier(int key) => key is
        Native.VK_SHIFT or Native.VK_CONTROL or Native.VK_MENU or Native.VK_CAPITAL
        or Native.VK_LWIN or Native.VK_RWIN
        or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5   // left/right shift, control, alt
        or 0x90 or 0x91;                                   // num lock, scroll lock

    private static bool Down(int key) => (Native.GetAsyncKeyState(key) & 0x8000) != 0;

    /// <summary>
    /// The text this keystroke produces under the layout of whichever app is in
    /// front, which is not necessarily ours.
    /// </summary>
    private static string? TypedString(Native.KBDLLHOOKSTRUCT data)
    {
        var state = new byte[256];
        if (Down(Native.VK_SHIFT)) state[Native.VK_SHIFT] = 0x80;
        if (Down(Native.VK_CONTROL)) state[Native.VK_CONTROL] = 0x80;
        if (Down(Native.VK_MENU)) state[Native.VK_MENU] = 0x80;
        if ((Native.GetKeyState(Native.VK_CAPITAL) & 1) != 0) state[Native.VK_CAPITAL] = 0x01;

        var window = Native.GetForegroundWindow();
        var thread = window == IntPtr.Zero ? 0 : Native.GetWindowThreadProcessId(window, out _);
        var layout = Native.GetKeyboardLayout(thread);

        var buffer = new char[8];
        // Bit 2 tells Windows not to disturb the kernel's keyboard state, which
        // is what keeps dead keys working for the user while we look at them.
        var written = Native.ToUnicodeEx(data.vkCode, data.scanCode, state, buffer, buffer.Length, 4, layout);
        if (written <= 0) return null;
        return new string(buffer, 0, Math.Min(written, buffer.Length));
    }
}
