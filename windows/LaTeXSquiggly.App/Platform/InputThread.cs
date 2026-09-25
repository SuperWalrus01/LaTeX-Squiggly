using System.Diagnostics;
using LaTeXSquiggly.Core.Input;
using LaTeXSquiggly.Core.Suppression;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// Owns the low-level keyboard hook, the thread it lives on, and the rolling
/// input buffer.
///
/// Windows delivers a low-level keyboard hook by posting to the message queue of
/// the thread that installed it and then waiting for that thread to answer.
/// Until it answers, the keystroke has not reached anybody. So whichever thread
/// installs the hook is, for as long as the app runs, part of the path every
/// keystroke on the machine takes, and Windows silently removes a hook whose
/// thread takes longer than LowLevelHooksTimeout (300 ms by default) to answer.
///
/// The first Windows build installed its hooks from the UI thread, which also
/// lays out the settings window, draws the tray menu and stops for garbage
/// collection, and every one of those put the whole machine's input on hold. So
/// the hook now lives on a thread of its own, running nothing else: no window, no
/// WinForms message loop, no synchronisation context. It runs a bare Win32 pump
/// and the callbacks, and talks to the UI by posting, never by waiting. Three
/// rules follow, and they are the reason for most of what looks fussy here:
///
/// - Nothing on the hot path allocates. The key event is read through its
///   pointer rather than marshalled, and the keyboard layout is looked up in a
///   table built in advance (see KeyboardLayoutTable).
/// - Nothing on the hot path locks. The exclusion rules arrive as an immutable
///   snapshot, replaced wholesale when the user changes them.
/// - The expensive question is asked rarely. Whether to stay quiet is cached for
///   200 ms, dropped the instant the foreground window changes, and always asked
///   again, uncached, in the moment before anything is typed.
///
/// There is no mouse hook. It fires on every movement of the pointer, and its
/// callbacks queue on the same thread as the keyboard's. A click is noticed
/// instead through GetAsyncKeyState, and only when the buffer could trigger;
/// the four second buffer lifetime covers any click that check misses.
/// </summary>
internal sealed class InputThread : IDisposable
{
    /// <summary>
    /// How long a suppression decision is reused. Shorter than any app switch a
    /// person can perform, and never used for the check just before typing.
    /// </summary>
    private const int DecisionLifetimeMs = 200;

    /// <summary>
    /// A half-typed command with no keystroke for this long is not a command any
    /// more. Longer than anyone takes to type \alpha, shorter than the pause
    /// involved in reaching for the trackpad.
    /// </summary>
    private const int BufferLifetimeMs = 4000;

    private const int TickIntervalMs = 1000;

    /// <summary>One summary line in the log a minute, so a hang has a timeline around it.</summary>
    private const int TicksPerHeartbeat = 60;

    /// <summary>
    /// A callback this slow is logged. Far under the 300 ms at which Windows
    /// removes the hook, so the log shows a problem long before it becomes one.
    /// </summary>
    private const long SlowCallbackMicroseconds = 10_000;

    private static readonly uint OwnProcessId = (uint)Environment.ProcessId;

    private readonly InputBuffer _buffer = new();
    private readonly ForegroundWatcher _watcher = new();

    private Thread? _thread;
    private uint _threadId;
    private readonly ManualResetEventSlim _ready = new(false);

    private IntPtr _keyboard = IntPtr.Zero;
    private IntPtr _foregroundEvent = IntPtr.Zero;

    // Windows only holds a weak reference to a hook procedure, so these fields
    // are what stop the delegates from being collected out from under it.
    private Native.HookProc? _keyboardProc;
    private Native.WinEventProc? _foregroundProc;

    private volatile bool _installed;

    /// <summary>Set while we are typing, so our own events cannot re-enter.</summary>
    private bool _replacing;

    /// <summary>
    /// The key whose release must be swallowed because we swallowed its press.
    /// Leaving a stray key-up behind confuses anything that tracks key state.
    /// </summary>
    private int _suppressedKeyUp = -1;

    // The cached suppression decision, and the window and time it was made for.
    private IntPtr _decisionWindow = IntPtr.Zero;
    private int _decisionAt;
    private SuppressionDecision _decision = SuppressionDecision.Convert;

    /// <summary>Built on the UI thread when the layout changes, read here.</summary>
    private volatile KeyboardLayoutTable _layout = KeyboardLayoutTable.Empty;

    private int _lastKeystroke;
    private int _lastSlowReport;

    /// <summary>The replacement waiting to be typed once the hook has returned.</summary>
    private Replacement? _pending;

    // For the log's heartbeat line.
    private int _ticks;
    private long _events;
    private long _conversions;
    private long _slowestMicroseconds;

    /// <summary>
    /// Called on this thread with an explanation the user needs to see. The
    /// receiver must post it to the UI thread and return at once.
    /// </summary>
    public Action<string>? OnNotice { get; set; }

    /// <summary>Called on this thread when another window comes to the front.</summary>
    public Action? OnForegroundChanged { get; set; }

    /// <summary>The current exclusion rules: a snapshot nobody edits.</summary>
    public Func<ExclusionList>? Rules { get; set; }

    public bool IsRunning => _installed;

    /// <summary>The layout the current table was built for.</summary>
    public IntPtr LayoutHandle => _layout.Layout;

    /// <summary>Replaces the layout table. A single reference swap, safe from any thread.</summary>
    public void UseLayout(KeyboardLayoutTable table) => _layout = table;

    /// <summary>
    /// Starts the thread and waits, briefly, for it to report whether the hook
    /// went in. False if it did not.
    /// </summary>
    public bool Start()
    {
        if (_thread is not null) return _installed;

        _ready.Reset();
        _thread = new Thread(Run)
        {
            Name = "LaTeX Squiggly input",
            IsBackground = true,
            // Above the UI, so a busy settings window cannot delay a keystroke.
            Priority = ThreadPriority.AboveNormal,
        };
        _thread.Start();
        _ready.Wait(2000);
        if (!_installed) Stop();
        return _installed;
    }

    public void Stop()
    {
        var thread = _thread;
        if (thread is null) return;

        _thread = null;
        if (_threadId != 0) Native.PostThreadMessageW(_threadId, Native.WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        thread.Join(2000);
        _installed = false;
        _threadId = 0;
    }

    /// <summary>
    /// Forgets the buffer. Posted rather than done directly, because the buffer
    /// belongs to the input thread and is never touched from anywhere else.
    /// </summary>
    public void ResetBuffer()
    {
        var threadId = _threadId;
        if (threadId != 0) Native.PostThreadMessageW(threadId, Native.WM_APP_RESET, IntPtr.Zero, IntPtr.Zero);
    }

    public void Dispose() => Stop();

    // MARK: The thread

    private void Run()
    {
        try
        {
            Pump();
        }
        catch (Exception error)
        {
            // Take the hook out before anything else, so no keystroke waits on a
            // thread that is no longer pumping, then say so: an app that has
            // quietly stopped converting looks exactly like one that has died.
            try { Uninstall(); } catch (Exception) { _installed = false; }
            Diagnostics.Log("the input thread died: " + error);
            try
            {
                OnNotice?.Invoke("LaTeX Squiggly stopped converting because of an internal error. "
                    + "Switch it off and on again from the tray menu. The details are in the log.");
            }
            catch (Exception)
            {
                // Nothing useful left to do.
            }
        }
        finally
        {
            // Whatever happened, Start must not wait out its whole timeout.
            _ready.Set();
        }
    }

    private void Pump()
    {
        _threadId = Native.GetCurrentThreadId();

        // A thread has no message queue until it asks for one, and a message
        // posted to it before then is lost. Peeking creates the queue, so Stop
        // and ResetBuffer can post from the moment _threadId is set.
        Native.PeekMessageW(out _, IntPtr.Zero, Native.WM_QUIT, Native.WM_QUIT, Native.PM_NOREMOVE);

        Install();
        _ready.Set();
        if (!_installed) return;

        var timer = Native.SetTimer(IntPtr.Zero, UIntPtr.Zero, TickIntervalMs, IntPtr.Zero);
        if (timer == UIntPtr.Zero) Report("SetTimer failed; there will be no timeline");

        int result;
        while ((result = Native.GetMessageW(out var message, IntPtr.Zero, 0, 0)) > 0)
        {
            switch (message.message)
            {
                case Native.WM_TIMER:
                    Guarded(Tick, "tick");
                    break;
                case Native.WM_APP_RESET:
                    Guarded(Forget, "reset");
                    break;
                case Native.WM_APP_REPLACE:
                    Guarded(PerformPending, "replace");
                    break;
                default:
                    // Hook callbacks arrive through dispatch.
                    Native.TranslateMessage(ref message);
                    Native.DispatchMessageW(ref message);
                    break;
            }
        }

        // The hook comes out before the file is written, so no keystroke waits on the disk.
        var summary = Summary();
        if (timer != UIntPtr.Zero) Native.KillTimer(IntPtr.Zero, timer);
        Uninstall();
        Diagnostics.Log($"the input pump ended (GetMessage returned {result}); " + summary);
    }

    /// <summary>An exception in housekeeping is logged, never allowed to end the pump.</summary>
    private static void Guarded(Action work, string what)
    {
        try
        {
            work();
        }
        catch (Exception error)
        {
            Report($"!!! {what} threw: {error}");
        }
    }

    private void Install()
    {
        var module = Native.GetModuleHandleW(null);
        _keyboardProc = KeyboardCallback;
        _foregroundProc = ForegroundCallback;

        _keyboard = Native.SetWindowsHookExW(Native.WH_KEYBOARD_LL, _keyboardProc, module, 0);
        if (_keyboard == IntPtr.Zero)
        {
            var error = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            Diagnostics.Log($"SetWindowsHookEx(WH_KEYBOARD_LL) failed, error {error}");
            _keyboardProc = null;
            _foregroundProc = null;
            return;
        }

        // Told when the foreground window changes, instead of polling for it.
        // Not fatal if it fails: the decision cache still expires on its own.
        _foregroundEvent = Native.SetWinEventHook(
            Native.EVENT_SYSTEM_FOREGROUND, Native.EVENT_SYSTEM_FOREGROUND, IntPtr.Zero,
            _foregroundProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT);
        if (_foregroundEvent == IntPtr.Zero) Report("SetWinEventHook failed");

        _watcher.ReadsPages = true;
        Forget();
        _lastKeystroke = Environment.TickCount;
        _installed = true;
        Report("keyboard hook installed");
    }

    private void Uninstall()
    {
        if (_keyboard != IntPtr.Zero) Native.UnhookWindowsHookEx(_keyboard);
        if (_foregroundEvent != IntPtr.Zero) Native.UnhookWinEvent(_foregroundEvent);
        _keyboard = IntPtr.Zero;
        _foregroundEvent = IntPtr.Zero;
        _keyboardProc = null;
        _foregroundProc = null;
        _installed = false;
        _buffer.Reset();
    }

    /// <summary>
    /// The caret may be somewhere the buffer knows nothing about, so forget
    /// what was typed, and the decision made for the window it was typed in.
    /// </summary>
    private void Forget()
    {
        _buffer.Reset();
        _suppressedKeyUp = -1;
        InvalidateDecision();
    }

    private void Tick()
    {
        _ticks++;
        if (!_buffer.IsEmpty && Environment.TickCount - _lastKeystroke > BufferLifetimeMs) Forget();
        if (_ticks % TicksPerHeartbeat == 0) Report(Summary());
    }

    private static string Handles()
    {
        var process = Native.GetCurrentProcess();
        return $"gdi {Native.GetGuiResources(process, Native.GR_GDIOBJECTS)}, "
            + $"user {Native.GetGuiResources(process, Native.GR_USEROBJECTS)}";
    }

    /// <summary>One line for the log: whether the hook is in, and how it has been doing.</summary>
    public string Summary()
    {
        var slowest = _slowestMicroseconds;
        var slowestText = slowest < 1000 ? slowest + " us" : slowest / 1000 + " ms";
        return $"hook {(_installed ? "installed" : "NOT INSTALLED")}, {_events} key events, "
            + $"{_conversions} conversions, slowest callback {slowestText}, " + Handles();
    }

    /// <summary>
    /// Writes to the log off this thread. Once the hook is in, every write from
    /// here goes through this: a file write on this thread holds up every
    /// keystroke on the machine, and one slow enough gets the hook removed.
    /// </summary>
    private static void Report(string message) => Diagnostics.LogLater(message);

    // MARK: The callbacks

    private void ForegroundCallback(IntPtr hook, uint eventType, IntPtr window, int idObject, int idChild,
        uint thread, uint time)
    {
        try
        {
            // An app switch moves the caret somewhere we know nothing about. The
            // first build did not reset here, so a command half typed in one
            // window could finish itself in the next.
            Forget();
            OnForegroundChanged?.Invoke();
        }
        catch (Exception)
        {
            // Never let an exception out of a Windows callback.
        }
    }

    private IntPtr KeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0) return Native.CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);

        var handled = false;
        try
        {
            _events++;
            var started = Stopwatch.GetTimestamp();
            handled = Handle((int)wParam, lParam);
            TimeIt(started);
        }
        catch (Exception error)
        {
            // A hook that throws is a hook Windows removes, which would leave
            // the user with a keyboard that has quietly stopped converting and
            // no way to tell. Swallowing is the lesser evil; the keystroke is
            // passed through untouched.
            try
            {
                _buffer.Reset();
                Report("!!! a keystroke threw: " + error);
            }
            catch (Exception)
            {
                // Nothing useful left to do.
            }
        }
        return handled ? new IntPtr(1) : Native.CallNextHookEx(IntPtr.Zero, nCode, wParam, lParam);
    }

    private void TimeIt(long started)
    {
        var elapsed = (Stopwatch.GetTimestamp() - started) * 1_000_000 / Stopwatch.Frequency;
        if (elapsed > _slowestMicroseconds) _slowestMicroseconds = elapsed;
        if (elapsed < SlowCallbackMicroseconds) return;

        // At most one report every ten seconds, so a slow spell cannot flood the log.
        var now = Environment.TickCount;
        if (now - _lastSlowReport < 10_000) return;
        _lastSlowReport = now;
        Report($"a keyboard callback took {elapsed / 1000} ms ({elapsed} us); "
            + "Windows removes a hook that takes 300 ms");
    }

    /// <returns>True to swallow the keystroke.</returns>
    private unsafe bool Handle(int message, IntPtr lParam)
    {
        // Read through the pointer: marshalling a copy allocates.
        var data = *(Native.KBDLLHOOKSTRUCT*)lParam;

        // Our own synthetic keystrokes come back around; ignore them or the
        // replacement feeds itself. So does anyone else's injected input, and
        // VK_PACKET, which is how Unicode text typed by another program arrives.
        if (data.dwExtraInfo == TextReplacer.SyntheticMarker
            || (data.flags & Native.LLKHF_INJECTED) != 0
            || data.vkCode == Native.VK_PACKET
            || _replacing)
        {
            return false;
        }

        if (message is Native.WM_KEYUP or Native.WM_SYSKEYUP)
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

        // A stale buffer, from a long pause or a click, is forgotten before this
        // keystroke is added to it.
        var now = Environment.TickCount;
        if (!_buffer.IsEmpty && (now - _lastKeystroke > BufferLifetimeMs || ClickHappened())) _buffer.Reset();
        _lastKeystroke = now;

        // Per-app suppression, checked before anything is remembered: in an
        // excluded app no buffer accumulates, so a replacement there is not
        // declined late, it is structurally impossible.
        var window = Native.GetForegroundWindow();

        // Never inside our own windows. The renderer's input is LaTeX, and
        // turning \alpha into a Greek letter there would break the equation.
        Native.GetWindowThreadProcessId(window, out var owner);
        if (owner == OwnProcessId)
        {
            if (!_buffer.IsEmpty) _buffer.Reset();
            return false;
        }

        if (Decision(window, fresh: false).IsSuppressed)
        {
            if (!_buffer.IsEmpty) _buffer.Reset();
            return false;
        }

        var shift = Down(Native.VK_SHIFT);
        var control = Down(Native.VK_CONTROL);
        var alt = Down(Native.VK_MENU);

        // Control chords and Windows chords are shortcuts, not text. Control
        // with Alt is left alone: that is AltGr, which types real characters
        // on a great many layouts, and treating it as a shortcut would make the
        // app useless outside the English-speaking world.
        if ((control && !alt) || (alt && !control) || Down(Native.VK_LWIN) || Down(Native.VK_RWIN))
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

        var caps = (Native.GetKeyState(Native.VK_CAPITAL) & 1) != 0;
        var typed = _layout.Lookup(key, shift, altGr: control && alt, caps);
        if (typed is null || typed.Length == 0)
        {
            // Dead keys, function keys and anything else we cannot model.
            // Forgetting is the safe response.
            _buffer.Reset();
            return false;
        }

        if (typed.Length == 1 && TriggerDetector.Terminators.Contains(typed[0]))
        {
            return HandleTerminator(typed[0], key, window);
        }

        _buffer.Insert(typed);
        return false;
    }

    /// <summary>
    /// Whether a mouse button went down since we last asked. Only asked when the
    /// buffer could trigger, which is the only time a stale buffer does harm.
    ///
    /// The "pressed since you last asked" bit is shared across processes, so
    /// another program polling the same button can clear it first. This can miss
    /// a click; it cannot invent one. The buffer lifetime covers the ones it misses.
    /// </summary>
    private bool ClickHappened()
    {
        if (!_buffer.CanTrigger) return false;
        return Pressed(Native.VK_LBUTTON) || Pressed(Native.VK_RBUTTON) || Pressed(Native.VK_MBUTTON);
    }

    private static bool Pressed(int key) => (Native.GetAsyncKeyState(key) & 1) != 0;

    private bool HandleTerminator(char character, int key, IntPtr window)
    {
        var outcome = TriggerDetector.Outcome(_buffer.Text, character);

        switch (outcome.Kind)
        {
            case TriggerKind.None:
                _buffer.Insert(character.ToString());
                return false;

            case TriggerKind.Replace:
            {
                _buffer.Reset();

                // A browser tab can change without the foreground window
                // changing, so this asks again, uncached, at the last instant at
                // which the answer is still free of consequences.
                var decision = Decision(window, fresh: true);
                if (decision.Reason is not null)
                {
                    Notify($"Left as you typed it, {decision.Reason.Explanation}.");
                    return false;
                }

                // Typed after this callback returns, not inside it: the rule for
                // a low-level hook is to do as little as possible and answer, and
                // typing is the most expensive thing this app does. The pump
                // picks the message up as soon as the callback returns. A
                // keystroke's callback can overtake a posted message, so one
                // arriving in that instant would be seen first, but the instant
                // is far shorter than the gap between two keystrokes.
                _pending = outcome.Replacement;
                if (!Native.PostThreadMessageW(_threadId, Native.WM_APP_REPLACE, IntPtr.Zero, IntPtr.Zero))
                {
                    _pending = null;
                    Report("PostThreadMessage failed; the replacement was dropped");
                    return false;
                }

                // Suppress the terminator: the replacement types it back, so
                // letting the original through would double it.
                _suppressedKeyUp = key;
                return true;
            }

            default:
                _buffer.Reset();
                Notify(outcome.Reason!);
                // The user's text is left exactly as they typed it.
                return false;
        }
    }

    private void PerformPending()
    {
        var pending = _pending;
        _pending = null;
        if (pending is null) return;

        // Counts only. What was typed is never written anywhere.
        Report($"typing: {pending.DeleteCount} deletes, {pending.Insert.Length} chars");
        _replacing = true;
        bool typed;
        try { typed = TextReplacer.Perform(pending); }
        finally { _replacing = false; }
        Report(typed ? "typed" : "SendInput refused");

        if (!typed)
        {
            Notify("Windows would not let LaTeX Squiggly type into this window. It is usually running as administrator.");
            return;
        }
        _conversions++;
        if (pending.Notice is not null) Notify(pending.Notice);
    }

    /// <summary>
    /// Whether to convert in the given window. Reused for DecisionLifetimeMs
    /// unless fresh is asked for, which it always is before typing.
    /// </summary>
    private SuppressionDecision Decision(IntPtr window, bool fresh)
    {
        if (!fresh && window == _decisionWindow && Environment.TickCount - _decisionAt < DecisionLifetimeMs)
        {
            return _decision;
        }
        var rules = Rules?.Invoke();
        _decision = rules is null ? SuppressionDecision.Convert : rules.Decision(_watcher.Current(window));
        _decisionWindow = window;
        _decisionAt = Environment.TickCount;
        return _decision;
    }

    private void InvalidateDecision()
    {
        _decisionWindow = IntPtr.Zero;
        _decision = SuppressionDecision.Convert;
        _decisionAt = 0;
    }

    private void Notify(string message) => OnNotice?.Invoke(message);

    private static bool IsModifier(int key) => key is
        Native.VK_SHIFT or Native.VK_CONTROL or Native.VK_MENU or Native.VK_CAPITAL
        or Native.VK_LWIN or Native.VK_RWIN
        or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5   // left/right shift, control, alt
        or 0x90 or 0x91;                                   // num lock, scroll lock

    private static bool Down(int key) => (Native.GetAsyncKeyState(key) & 0x8000) != 0;
}
