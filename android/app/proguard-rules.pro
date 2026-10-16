# The renderer page calls these by name through addJavascriptInterface.
-keepclassmembers class io.github.superwalrus01.squiggly.render.RendererBridge {
    @android.webkit.JavascriptInterface <methods>;
}
