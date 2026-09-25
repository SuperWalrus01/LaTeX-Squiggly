using System.Drawing;
using System.Drawing.Imaging;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace LaTeXSquiggly.App.Platform;

/// <summary>
/// The renderer: LaTeX in, an image out, to paste where LaTeX is not
/// understood. The same page as the Chrome extension's renderer and the Mac
/// app's window, in a WebView2, with the app doing what a page cannot: the
/// clipboard, the save dialog, and keeping its settings.
///
/// The page is used exactly as the Mac app has it, unchanged. It talks to its
/// host through window.webkit.messageHandlers.squiggly, whose postMessage
/// returns the app's answer (see chrome/renderer/host.js). WebView2 has no
/// such thing, so Bridge, run before the page's own scripts, provides it: each
/// call becomes a chrome.webview message carrying an id, and the answer comes
/// back as a message with the same id. The window is kept once made, so
/// MathJax loads once per launch and the shortcut brings it back at once.
///
/// The page's files are embedded in the exe and served from memory at
/// https://app.squiggly/, never written to disk: a web view will not load ES
/// modules from file://, and the renderer is made of them.
/// </summary>
internal sealed class RendererWindow : Form
{
    private const string Origin = "https://app.squiggly/";

    /// <summary>
    /// The Mac app's message handler, as the page expects to find it, carried
    /// over WebView2's messages. A promise per call, settled by the reply with
    /// its id; Reply is the app's half.
    /// </summary>
    private const string Bridge = """
        (() => {
          const webview = window.chrome?.webview;
          if (!webview) return;
          const pending = new Map();
          let nextId = 0;
          webview.addEventListener("message", (event) => {
            const { id, result, error } = event.data ?? {};
            const waiting = pending.get(id);
            if (!waiting) return;
            pending.delete(id);
            if (error) waiting.reject(new Error(error));
            else waiting.resolve(result ?? null);
          });
          const squiggly = {
            postMessage: (message) => new Promise((resolve, reject) => {
              const id = ++nextId;
              pending.set(id, { resolve, reject });
              webview.postMessage({ ...message, id });
            }),
          };
          window.webkit = { messageHandlers: { squiggly } };
        })();
        """;

    private static readonly Dictionary<string, string> Types = new(StringComparer.OrdinalIgnoreCase)
    {
        [".html"] = "text/html; charset=utf-8",
        [".js"] = "text/javascript; charset=utf-8",
        [".css"] = "text/css; charset=utf-8",
        [".json"] = "application/json",
        [".svg"] = "image/svg+xml",
        [".png"] = "image/png",
    };

    /// <summary>Served path to embedded resource name, built once.</summary>
    private static readonly Lazy<Dictionary<string, string>> Files = new(IndexFiles);

    private readonly WebView2 _web = new() { Dock = DockStyle.Fill };
    private readonly RendererStorage _storage = new();
    private readonly Func<string?> _shortcut;
    private Task? _starting;

    /// <summary>
    /// Whatever was in front when the renderer opened, which gets the focus
    /// back when it closes, so Ctrl+Enter then Ctrl+V pastes where you were.
    /// </summary>
    private IntPtr _previous;

    /// <summary>Set once the app is quitting, so closing really closes.</summary>
    public bool Quitting { get; set; }

    /// <param name="shortcut">The global shortcut's keys, or null if it could not be registered.</param>
    public RendererWindow(Func<string?> shortcut)
    {
        _shortcut = shortcut;
        Text = "Render LaTeX";
        Icon = AppIcon.Window;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(540, 720);
        MinimumSize = new Size(440, 460);
        Controls.Add(_web);
    }

    public void ShowRenderer()
    {
        var front = Native.GetForegroundWindow();
        if (front != IntPtr.Zero && !IsOwnWindow(front)) _previous = front;

        _starting ??= Start();
        Show();
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        Activate();
        _web.Focus();
        // Selects the input, ready to be typed over. Before the page has
        // loaded there is nothing to call, and the page selects it itself.
        if (_web.CoreWebView2 is not null)
        {
            _ = _web.ExecuteScriptAsync("globalThis.squigglyShown?.()");
        }
    }

    private void HideRenderer()
    {
        Hide();
        var previous = _previous;
        _previous = IntPtr.Zero;
        if (previous != IntPtr.Zero) Native.SetForegroundWindow(previous);
    }

    // Closing only hides it, so the next show is instant.
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!Quitting && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            HideRenderer();
            return;
        }
        base.OnFormClosing(e);
    }

    private static bool IsOwnWindow(IntPtr window)
    {
        Native.GetWindowThreadProcessId(window, out var pid);
        return pid == (uint)Environment.ProcessId;
    }

    // MARK: Starting the web view

    private async Task Start()
    {
        try
        {
            // Not the default, which is a folder next to the exe: that is
            // wherever the user put it, often Downloads, and may not be writable.
            var data = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "LaTeXSquiggly", "WebView2");
            var environment = await CoreWebView2Environment.CreateAsync(null, data);
            await _web.EnsureCoreWebView2Async(environment);
        }
        catch (WebView2RuntimeNotFoundException)
        {
            Diagnostics.Log("renderer: the WebView2 runtime is not installed");
            Hide();
            MessageBox.Show(
                "The renderer needs the Microsoft Edge WebView2 Runtime, which is part of "
                + "Windows 11 and of most Windows 10 installs, but is missing here.\n\n"
                + "Get it from https://go.microsoft.com/fwlink/p/?LinkId=2124703 and try again.",
                "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            _starting = null;
            return;
        }
        catch (Exception error)
        {
            Diagnostics.Log("renderer: the web view would not start: " + error);
            Hide();
            MessageBox.Show("The renderer could not start.\n\n" + error.Message,
                "LaTeX Squiggly", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            _starting = null;
            return;
        }

        var core = _web.CoreWebView2;
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultContextMenusEnabled = true;
        core.Settings.IsStatusBarEnabled = false;
        core.Settings.IsZoomControlEnabled = false;
        // Ctrl+P, F5, Ctrl+F and the like belong to a browser, not to this window.
        core.Settings.AreBrowserAcceleratorKeysEnabled = false;

        core.AddWebResourceRequestedFilter(Origin + "*", CoreWebView2WebResourceContext.All);
        core.WebResourceRequested += (_, e) => e.Response = Serve(core.Environment, e.Request.Uri);
        core.WebMessageReceived += (_, e) => Received(e.WebMessageAsJson);

        // The page never leaves its own files. A link out opens in the browser.
        core.NavigationStarting += (_, e) =>
        {
            if (e.Uri.StartsWith(Origin, StringComparison.OrdinalIgnoreCase)) return;
            e.Cancel = true;
            OpenOutside(e.Uri);
        };
        core.NewWindowRequested += (_, e) =>
        {
            e.Handled = true;
            OpenOutside(e.Uri);
        };
        await core.AddScriptToExecuteOnDocumentCreatedAsync(Bridge);
        core.NavigationCompleted += (_, e) =>
            Diagnostics.Log(e.IsSuccess ? "renderer: page loaded" : "renderer: page failed, " + e.WebErrorStatus);

        core.Navigate(Origin + "index.html");
    }

    private static void OpenOutside(string uri)
    {
        if (!uri.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) return;
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uri) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // No browser to hand it to.
        }
    }

    // MARK: Serving the page

    private static Dictionary<string, string> IndexFiles()
    {
        // Resource names are "web/" plus the served path; MSBuild may write
        // the folder separators either way.
        var files = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var name in Assembly.GetExecutingAssembly().GetManifestResourceNames())
        {
            var path = name.Replace('\\', '/');
            if (path.StartsWith("web/", StringComparison.Ordinal)) files[path["web/".Length..]] = name;
        }
        return files;
    }

    private static CoreWebView2WebResourceResponse Serve(CoreWebView2Environment environment, string uri)
    {
        var path = Uri.TryCreate(uri, UriKind.Absolute, out var parsed)
            ? Uri.UnescapeDataString(parsed.AbsolutePath.TrimStart('/'))
            : "";
        if (path.Length == 0) path = "index.html";

        // Only the files that were embedded: nothing above them, whatever the path.
        if (!path.Split('/').Contains("..") && Files.Value.TryGetValue(path, out var name))
        {
            var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
            if (stream is not null)
            {
                var type = Types.GetValueOrDefault(Path.GetExtension(path), "application/octet-stream");
                return environment.CreateWebResourceResponse(stream, 200, "OK", "Content-Type: " + type);
            }
        }
        Diagnostics.Log("renderer: no file for " + path);
        return environment.CreateWebResourceResponse(null, 404, "Not Found", "");
    }

    // MARK: Messages from the page

    private void Received(string json)
    {
        JsonNode? id = null;
        try
        {
            var message = JsonNode.Parse(json) as JsonObject ?? throw new InvalidDataException("not an object");
            id = message["id"]?.DeepClone();
            var op = (string?)message["op"];
            switch (op)
            {
                case "get":
                    Reply(id, _storage.Get(Area(message), Strings(message["keys"])));
                    break;
                case "set":
                    _storage.Set(Area(message), message["items"] as JsonObject ?? new JsonObject());
                    Reply(id, null);
                    break;
                case "shortcut":
                    Reply(id, (string?)message["name"] == "open-renderer" ? _shortcut() : null);
                    break;
                case "close":
                    Reply(id, null);
                    BeginInvoke(HideRenderer);
                    break;
                case "copyImage":
                    Reply(id, null, CopyImage(
                        (string?)message["png"],
                        (double?)message["width"] ?? 0,
                        (double?)message["height"] ?? 0));
                    break;
                case "copyText":
                    Reply(id, null, CopyText((string?)message["text"] ?? ""));
                    break;
                case "save":
                    // After this handler returns: a modal dialog inside a web
                    // view's event handler is a nested message loop it may not survive.
                    var saveId = id;
                    var fileName = (string?)message["name"] ?? "equation";
                    var content = (string?)message["data"];
                    BeginInvoke(() => Save(saveId, fileName, content));
                    break;
                default:
                    Reply(id, null, $"Unknown op {op}.");
                    break;
            }
        }
        catch (Exception error)
        {
            Diagnostics.Log("renderer: a message failed: " + error.Message);
            Reply(id, null, error.Message);
        }
    }

    private void Reply(JsonNode? id, JsonNode? result, string? error = null)
    {
        if (id is null || _web.CoreWebView2 is null) return;
        var answer = new JsonObject { ["id"] = id.DeepClone(), ["result"] = result };
        if (error is not null) answer["error"] = error;
        _web.CoreWebView2.PostWebMessageAsJson(answer.ToJsonString());
    }

    private static string Area(JsonObject message) => (string?)message["area"] == "sync" ? "sync" : "local";

    private static List<string> Strings(JsonNode? node) =>
        node is JsonArray array
            ? array.Select(item => item?.GetValueKind() == JsonValueKind.String ? (string?)item : null)
                .OfType<string>().ToList()
            : new List<string>();

    /// <summary>
    /// The PNG, with its resolution set so that it pastes at the size it was
    /// previewed: a 3x image says it is 288 dpi, and Word, PowerPoint and
    /// OneNote then place it at a third of its pixel size, and sharp. A bitmap
    /// goes with it, flattened onto white, for the apps that take only that:
    /// a bitmap on the clipboard has no transparency, and a transparent PNG
    /// pasted as one comes out on black.
    /// </summary>
    private static string? CopyImage(string? base64, double width, double height)
    {
        if (string.IsNullOrEmpty(base64)) return "No image to copy.";
        using var source = new Bitmap(new MemoryStream(Convert.FromBase64String(base64)));
        using var image = new Bitmap(source);
        if (width > 0 && height > 0)
        {
            var dpi = (float)(96 * image.Width / width);
            image.SetResolution(dpi, dpi);
        }

        using var png = new MemoryStream();
        image.Save(png, ImageFormat.Png);

        using var flat = new Bitmap(image.Width, image.Height, PixelFormat.Format24bppRgb);
        flat.SetResolution(image.HorizontalResolution, image.VerticalResolution);
        using (var graphics = Graphics.FromImage(flat))
        {
            graphics.Clear(Color.White);
            graphics.DrawImage(image, 0, 0, image.Width, image.Height);
        }

        var data = new DataObject();
        data.SetData("PNG", false, png);
        data.SetData(DataFormats.Bitmap, true, flat);
        return SetClipboard(data);
    }

    private static string? CopyText(string text)
    {
        var data = new DataObject();
        data.SetText(text.Length == 0 ? " " : text, TextDataFormat.UnicodeText);
        return SetClipboard(data);
    }

    /// <summary>Another program can be holding the clipboard, so it is tried a few times.</summary>
    private static string? SetClipboard(DataObject data)
    {
        try
        {
            Clipboard.SetDataObject(data, copy: true, retryTimes: 10, retryDelay: 50);
            return null;
        }
        catch (Exception error)
        {
            Diagnostics.Log("renderer: the clipboard refused: " + error.Message);
            return "Another program is holding the clipboard. Try again.";
        }
    }

    private void Save(JsonNode? id, string name, string? base64)
    {
        if (string.IsNullOrEmpty(base64))
        {
            Reply(id, false, "Nothing to save.");
            return;
        }
        var svg = name.EndsWith(".svg", StringComparison.OrdinalIgnoreCase);
        using var dialog = new SaveFileDialog
        {
            FileName = name,
            Filter = svg ? "SVG image (*.svg)|*.svg" : "PNG image (*.png)|*.png",
            DefaultExt = svg ? "svg" : "png",
            AddExtension = true,
            OverwritePrompt = true,
        };
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            Reply(id, false);
            return;
        }
        try
        {
            File.WriteAllBytes(dialog.FileName, Convert.FromBase64String(base64));
            Reply(id, true);
        }
        catch (Exception error)
        {
            Reply(id, false, error.Message);
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _web.Dispose();
        base.Dispose(disposing);
    }
}

/// <summary>
/// The page's two storage areas, as the extension has them: sync for the
/// settings and local for the last input and the history. One JSON file each,
/// next to settings.json. Nothing in them is ever sent anywhere.
/// </summary>
internal sealed class RendererStorage
{
    private static string PathOf(string area) =>
        Path.Combine(Settings.Directory, area == "sync" ? "renderer-settings.json" : "renderer-local.json");

    private static JsonObject Load(string area)
    {
        try
        {
            var path = PathOf(area);
            if (File.Exists(path) && JsonNode.Parse(File.ReadAllText(path)) is JsonObject stored) return stored;
        }
        catch (Exception)
        {
            // A damaged file is the same as none: the page has its own defaults.
        }
        return new JsonObject();
    }

    public JsonObject Get(string area, List<string> keys)
    {
        var stored = Load(area);
        var result = new JsonObject();
        foreach (var key in keys)
        {
            if (stored.TryGetPropertyValue(key, out var value)) result[key] = value?.DeepClone();
        }
        return result;
    }

    public void Set(string area, JsonObject items)
    {
        var stored = Load(area);
        foreach (var (key, value) in items) stored[key] = value?.DeepClone();
        try
        {
            Directory.CreateDirectory(Settings.Directory);
            File.WriteAllText(PathOf(area), stored.ToJsonString());
        }
        catch (Exception error)
        {
            Diagnostics.Log("renderer: could not save " + area + ": " + error.Message);
        }
    }
}
