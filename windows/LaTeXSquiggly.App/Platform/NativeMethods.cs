using System.Runtime.InteropServices;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// Every Win32 call the app makes, in one place, so the rest of the code reads
/// like the Mac app's does. Nothing here has any logic in it.
/// </summary>
internal static class Native
{
    // Hooks
    internal const int WH_KEYBOARD_LL = 13;

    internal const int WM_KEYDOWN = 0x0100;
    internal const int WM_KEYUP = 0x0101;
    internal const int WM_SYSKEYDOWN = 0x0104;
    internal const int WM_SYSKEYUP = 0x0105;

    /// <summary>Set on a keystroke that SendInput produced rather than a key.</summary>
    internal const uint LLKHF_INJECTED = 0x10;

    // Virtual keys
    internal const int VK_LBUTTON = 0x01;
    internal const int VK_RBUTTON = 0x02;
    internal const int VK_MBUTTON = 0x04;
    internal const int VK_BACK = 0x08;
    internal const int VK_RETURN = 0x0D;
    internal const int VK_SHIFT = 0x10;
    internal const int VK_CONTROL = 0x11;
    internal const int VK_MENU = 0x12;
    internal const int VK_CAPITAL = 0x14;
    internal const int VK_ESCAPE = 0x1B;
    internal const int VK_PRIOR = 0x21;
    internal const int VK_NEXT = 0x22;
    internal const int VK_END = 0x23;
    internal const int VK_HOME = 0x24;
    internal const int VK_LEFT = 0x25;
    internal const int VK_UP = 0x26;
    internal const int VK_RIGHT = 0x27;
    internal const int VK_DOWN = 0x28;
    internal const int VK_DELETE = 0x2E;
    internal const int VK_LWIN = 0x5B;
    internal const int VK_RWIN = 0x5C;

    /// <summary>What a KEYEVENTF_UNICODE keystroke looks like to a hook.</summary>
    internal const int VK_PACKET = 0xE7;

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    internal delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    internal struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern IntPtr SetWindowsHookExW(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    internal static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern IntPtr GetModuleHandleW(string? lpModuleName);

    // The input thread's message loop. A bare Win32 pump, not WinForms: the
    // thread has no window, and posting to it is how everything else talks to it.
    internal const uint WM_QUIT = 0x0012;
    internal const uint WM_TIMER = 0x0113;
    internal const uint WM_APP_RESET = 0x8000 + 1;     // WM_APP + 1
    internal const uint WM_APP_REPLACE = 0x8000 + 2;   // WM_APP + 2
    internal const uint PM_NOREMOVE = 0x0000;

    [StructLayout(LayoutKind.Sequential)]
    internal struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int ptX;
        public int ptY;
    }

    [DllImport("user32.dll")]
    internal static extern int GetMessageW(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PeekMessageW(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax,
        uint wRemoveMsg);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    internal static extern IntPtr DispatchMessageW(ref MSG lpMsg);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PostThreadMessageW(uint idThread, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern UIntPtr SetTimer(IntPtr hWnd, UIntPtr nIDEvent, uint uElapse, IntPtr lpTimerFunc);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool KillTimer(IntPtr hWnd, UIntPtr uIDEvent);

    [DllImport("kernel32.dll")]
    internal static extern uint GetCurrentThreadId();

    // Being told when the foreground window changes, instead of polling for it
    internal const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    internal const uint WINEVENT_OUTOFCONTEXT = 0x0000;

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    internal delegate void WinEventProc(IntPtr hWinEventHook, uint eventType, IntPtr hwnd, int idObject,
        int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    internal static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmodWinEventProc,
        WinEventProc pfnWinEventProc, uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    // Typing. MOUSEINPUT and HARDWAREINPUT are never sent, but they are part of
    // INPUT's union, and without them the struct is the wrong size for SendInput.
    internal const uint INPUT_KEYBOARD = 1;
    internal const uint KEYEVENTF_KEYUP = 0x0002;
    internal const uint KEYEVENTF_UNICODE = 0x0004;

    [StructLayout(LayoutKind.Sequential)]
    internal struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct INPUTUNION
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct INPUT
    {
        public uint type;
        public INPUTUNION u;
    }

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    // Reading the keyboard layout
    internal const uint MAPVK_VK_TO_VSC = 0;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int ToUnicodeEx(uint wVirtKey, uint wScanCode, byte[] lpKeyState,
        [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 4)] char[] pwszBuff,
        int cchBuff, uint wFlags, IntPtr dwhkl);

    [DllImport("user32.dll")]
    internal static extern IntPtr GetKeyboardLayout(uint idThread);

    [DllImport("user32.dll")]
    internal static extern uint MapVirtualKeyExW(uint uCode, uint uMapType, IntPtr dwhkl);

    [DllImport("user32.dll")]
    internal static extern short GetKeyState(int nVirtKey);

    [DllImport("user32.dll")]
    internal static extern short GetAsyncKeyState(int nVirtKey);

    // Who is in front. The buffers are char arrays rather than StringBuilders so
    // a caller can keep one and reuse it instead of allocating on every check.
    [DllImport("user32.dll")]
    internal static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern int GetWindowTextW(IntPtr hWnd, [Out] char[] lpString, int nMaxCount);

    internal const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern IntPtr OpenProcess(uint dwDesiredAccess,
        [MarshalAs(UnmanagedType.Bool)] bool bInheritHandle, uint dwProcessId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool QueryFullProcessImageNameW(IntPtr hProcess, uint dwFlags,
        [Out] char[] lpExeName, ref uint lpdwSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool CloseHandle(IntPtr hObject);

    // Resource counts, for the diagnostics log: a handle leak shows up here
    // long before it shows up as a failure.
    internal const uint GR_GDIOBJECTS = 0;
    internal const uint GR_USEROBJECTS = 1;

    [DllImport("user32.dll")]
    internal static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);

    [DllImport("kernel32.dll")]
    internal static extern IntPtr GetCurrentProcess();
}
