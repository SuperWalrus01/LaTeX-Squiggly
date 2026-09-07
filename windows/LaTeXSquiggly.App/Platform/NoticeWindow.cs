using System.Drawing;
using System.Windows.Forms;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// A transient, non-interactive panel for telling the user that a fallback
/// happened or that something was refused.
///
/// Deliberately not a toast notification: those need registration, persist in
/// the Action Center, and are the wrong weight for something that happens
/// mid-sentence. This appears above the tray and fades out.
///
/// Not stealing focus matters more than it looks. Taking the caret away from
/// the app the user is typing into would break the very thing we just replaced.
/// </summary>
internal sealed class NoticeWindow : Form
{
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_TOPMOST = 0x00000008;

    private readonly Label _label;
    private readonly System.Windows.Forms.Timer _dismiss;

    public NoticeWindow()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        BackColor = Color.FromArgb(32, 32, 32);
        ForeColor = Color.White;
        Padding = new Padding(14, 12, 14, 12);
        MaximumSize = new Size(420, 400);

        _label = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(392, 0),
            Font = new Font(SystemFonts.MessageBoxFont!.FontFamily, 9f),
            ForeColor = Color.White,
        };
        Controls.Add(_label);

        _dismiss = new System.Windows.Forms.Timer { Interval = 4000 };
        _dismiss.Tick += (_, _) => { _dismiss.Stop(); Hide(); };
    }

    /// <summary>Stops the panel from taking the caret when it appears.</summary>
    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST;
            return parameters;
        }
    }

    public void ShowNotice(string message)
    {
        _dismiss.Stop();
        _label.Text = message;

        // Sized to the text, then placed above the tray, which is where a
        // Windows user already looks for a transient message.
        var size = new Size(_label.PreferredWidth + Padding.Horizontal,
                            _label.PreferredHeight + Padding.Vertical);
        Size = size;

        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(area.Right - size.Width - 16, area.Bottom - size.Height - 16);

        Show();
        _dismiss.Start();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // The tray owns this window's lifetime; a close is a hide.
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnFormClosing(e);
    }
}
