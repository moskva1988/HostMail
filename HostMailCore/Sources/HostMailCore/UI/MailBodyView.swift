import SwiftUI
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - HTMLBodyView (WKWebView)

public struct HTMLBodyView: View {
    let html: String

    public init(html: String) { self.html = html }

    public var body: some View {
        #if canImport(WebKit)
        WebViewRepresentable(html: html)
        #else
        ScrollView { Text(html).padding(20) }
        #endif
    }
}

// MARK: - PlainBodyView (Text + URL auto-detection)

public struct PlainBodyView: View {
    let plain: String

    public init(plain: String) { self.plain = plain }

    public var body: some View {
        ScrollView {
            Text(linkify(plain))
                .font(.body)
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func linkify(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsRange = NSRange(text.startIndex..., in: text)
        detector?.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match = match,
                  let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attr),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attr) else { return }
            attr[lower..<upper].link = url
            attr[lower..<upper].foregroundColor = HostTheme.accent
            attr[lower..<upper].underlineStyle = .single
        }
        return attr
    }
}

// MARK: - WKWebView wrapper

#if canImport(WebKit)

#if canImport(UIKit)
struct WebViewRepresentable: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: makeConfig())
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML(html), baseURL: nil)
    }

    func makeCoordinator() -> WebCoordinator { WebCoordinator() }
}
#elseif canImport(AppKit)
struct WebViewRepresentable: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: makeConfig())
        web.navigationDelegate = context.coordinator
        // Transparent background so dark mode of host UI shows through.
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(wrappedHTML(html), baseURL: nil)
    }

    func makeCoordinator() -> WebCoordinator { WebCoordinator() }
}
#endif

private func makeConfig() -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    let prefs = WKWebpagePreferences()
    prefs.allowsContentJavaScript = false
    config.defaultWebpagePreferences = prefs
    return config
}

// CSP blocks remote scripts AND remote images (no tracking pixels).
// Allows inline styles (common in email) and base64 data: images.
private let cspPolicy = "default-src 'none'; img-src data:; style-src 'unsafe-inline'"

private func wrappedHTML(_ html: String) -> String {
    """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="Content-Security-Policy" content="\(cspPolicy)">
    <style>
    :root { color-scheme: light dark; }
    body {
      font: -apple-system-body, system-ui, -apple-system;
      margin: 0;
      padding: 16px;
      max-width: 720px;
      word-wrap: break-word;
      line-height: 1.45;
    }
    a { color: #0D9488; }
    img { max-width: 100%; height: auto; }
    table { max-width: 100%; border-collapse: collapse; }
    blockquote {
      border-left: 3px solid #0D9488;
      margin: 0;
      padding-left: 12px;
      opacity: 0.8;
    }
    pre, code { font-family: ui-monospace, monospace; font-size: 0.9em; }
    @media (prefers-color-scheme: dark) {
      html, body {
        background-color: #1a1a1c !important;
        background: #1a1a1c !important;
        color: #e8e8ea !important;
      }
      /* Override common email patterns that hard-code white on inner blocks */
      table, tr, td, th, div[bgcolor], td[bgcolor], tr[bgcolor],
      [style*="background-color:#fff"], [style*="background-color: #fff"],
      [style*="background-color:#FFF"], [style*="background-color: #FFF"],
      [style*="background-color:white"], [style*="background-color: white"],
      [style*="background:#fff"], [style*="background: #fff"],
      [style*="background:white"], [style*="background: white"] {
        background-color: #1a1a1c !important;
        background: #1a1a1c !important;
      }
      table, td, th { border-color: #3a3a3c !important; }
      /* Most email text colors target white BG (dark text). Lighten unless
         author explicitly used light-on-dark already. */
      body, body p, body span, body td, body div, body li {
        color: #e8e8ea !important;
      }
    }
    </style>
    </head>
    <body>
    \(html)
    </body>
    </html>
    """
}

final class WebCoordinator: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Initial loadHTMLString is `.other` — allow it through.
        if navigationAction.navigationType == .other {
            decisionHandler(.allow)
            return
        }
        // User-tapped links open in the system browser, never inside the
        // mail body view (we treat the body as untrusted content).
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
        decisionHandler(.cancel)
    }
}

#endif
