package net.scbb.modefinder;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.webkit.ValueCallback;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * The whole app: one local HTML file, full screen.
 *
 * mobile.html is carried in assets/ byte for byte as the browser prototype was
 * measured, so this wrapper adds nothing to the layout but a dark window. There
 * are no permissions and network loads are blocked: the page never fetches
 * anything.
 */
public class MainActivity extends Activity {

    /** --bg from the page's palette, so there is no flash of white at launch. */
    private static final int APP_BG = 0xFF0F1113;

    private WebView web;

    @SuppressLint({"SetJavaScriptEnabled", "ClickableViewAccessibility"})
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        Window w = getWindow();
        w.setStatusBarColor(APP_BG);
        w.setNavigationBarColor(APP_BG);

        web = new WebView(this);
        web.setLayoutParams(new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        web.setBackgroundColor(APP_BG);
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);   // no glow dragging the neck

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        // The layout is tuned to the pixel, so the OS must not rescale type:
        // textZoom follows the system font-size setting, and a minimum font
        // size can inflate the small labels. Both are pinned.
        s.setTextZoom(100);
        s.setMinimumFontSize(1);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        // Honour the page's own viewport meta so CSS pixels are device pixels
        // (this defaults to false, which would lay the page out on a 980px
        // desktop viewport -- every measurement here assumes 1:1).
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(false);
        s.setBlockNetworkLoads(true);                    // everything is local
        // It is already dark -- stop the WebView repainting it.
        if (Build.VERSION.SDK_INT >= 33) s.setAlgorithmicDarkeningAllowed(false);
        else if (Build.VERSION.SDK_INT >= 29) s.setForceDark(WebSettings.FORCE_DARK_OFF);

        web.setWebViewClient(new WebViewClient());       // keep navigation inside
        setContentView(web);
        web.loadUrl("file:///android_asset/mobile.html");
    }

    /**
     * Back closes an open menu first and only then leaves. The page already
     * closes its own menus when a click lands outside them (its document-level
     * click handler), so dispatching a click on the body lets the page keep its
     * internal state consistent -- the wrapper never edits the page's DOM.
     */
    @Override
    public void onBackPressed() {
        web.evaluateJavascript(
                "(function(){"
              + "  var m=document.getElementById('menu'), v=document.getElementById('vmenu');"
              + "  if((m&&!m.hidden)||(v&&!v.hidden)){"
              + "    document.body.click();"
              + "    return '1';"
              + "  }"
              + "  return '0';"
              + "})()",
                new ValueCallback<String>() {
                    @Override public void onReceiveValue(String value) {
                        if (value == null || !value.contains("1")) finish();
                    }
                });
    }
}
