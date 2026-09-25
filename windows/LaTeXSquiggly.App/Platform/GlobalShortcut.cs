using System.Windows.Forms;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// Win+Alt+L from any app: opens the renderer window.
///
/// RegisterHotKey rather than the keyboard hook, so it works while conversion
/// is off and costs the input thread nothing. Windows delivers only this one
/// combination to the app, as a message to a window on the UI thread.
///
/// Why these keys. Ctrl+Alt is AltGr on most European layouts, and Ctrl+Alt+L
/// types ł in Polish, so any Ctrl+Alt combination takes a character from
/// someone. The Windows key is reserved for shortcuts, and Win+Alt+L is one
/// Windows itself does not use. If another program has it, registering fails
/// and the tray menu is the way in; the renderer says no shortcut.
/// </summary>
internal sealed class GlobalShortcut : NativeWindow, IDisposable
{
    public const string Keys = "Win+Alt+L";

    private const int WM_HOTKEY = 0x0312;
    private const uint MOD_ALT = 0x0001;
    private const uint MOD_WIN = 0x0008;
    private const uint MOD_NOREPEAT = 0x4000;
    private const uint VK_L = 0x4C;
    private const int Id = 1;

    private readonly Action _action;

    public bool IsRegistered { get; private set; }

    public GlobalShortcut(Action action)
    {
        _action = action;
        // A message-only window: never shown, never in Alt+Tab, there only to be told.
        CreateHandle(new CreateParams { Parent = new IntPtr(-3) });
    }

    /// <returns>False when another program already holds the combination.</returns>
    public bool Register()
    {
        if (IsRegistered) return true;
        IsRegistered = Native.RegisterHotKey(Handle, Id, MOD_WIN | MOD_ALT | MOD_NOREPEAT, VK_L);
        if (!IsRegistered)
        {
            Diagnostics.Log($"could not register {Keys}, error "
                + System.Runtime.InteropServices.Marshal.GetLastWin32Error());
        }
        return IsRegistered;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_HOTKEY && m.WParam == (IntPtr)Id)
        {
            try
            {
                _action();
            }
            catch (Exception error)
            {
                Diagnostics.Log("the renderer shortcut failed: " + error);
            }
            return;
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        if (IsRegistered) Native.UnregisterHotKey(Handle, Id);
        IsRegistered = false;
        DestroyHandle();
    }
}
