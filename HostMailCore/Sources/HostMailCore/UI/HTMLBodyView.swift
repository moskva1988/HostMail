import SwiftUI
import WebKit

#if os(iOS)
public struct HTMLBodyView: UIViewRepresentable {
    let html: String

    public init(html: String) { self.html = html }

    public func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: Self.makeConfig())
        view.scrollView.bounces = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        return view
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.wrap(html), baseURL: nil)
    }

    private static func makeConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs
        return config
    }

    private static func wrap(_ rawHtml: String) -> String { Self.htmlEnvelope(rawHtml) }
    fileprivate static func htmlEnvelope(_ raw: String) -> String { wrapHTMLForRender(raw) }
}
#elseif os(macOS)
public struct HTMLBodyView: NSViewRepresentable {
    let html: String

    public init(html: String) { self.html = html }

    public func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: Self.makeConfig())
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrapHTMLForRender(html), baseURL: nil)
    }

    private static func makeConfig() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs
        return config
    }
}
#endif

// Wraps email HTML in a minimal scaffold:
// - viewport for proper width on iOS
// - prefers-color-scheme so default text color follows system theme (most
//   email HTML defines its own colors and overrides this; it's a fallback)
// - max-width on body so wide HTML fits on phone screens
fileprivate func wrapHTMLForRender(_ raw: String) -> String {
    """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <style>
      :root { color-scheme: light dark; }
      html, body {
        margin: 0;
        padding: 12px;
        font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
        font-size: 15px;
        line-height: 1.4;
        word-wrap: break-word;
        -webkit-text-size-adjust: 100%;
      }
      img, table { max-width: 100% !important; height: auto; }
      a { color: #6B6BE8; }
    </style>
    </head>
    <body>
    \(raw)
    </body>
    </html>
    """
}
