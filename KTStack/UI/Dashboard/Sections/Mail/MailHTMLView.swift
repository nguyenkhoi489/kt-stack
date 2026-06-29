import SwiftUI
import WebKit

struct MailHTMLView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(to: webView, html: html)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.attach(to: webView, html: html)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private static var ruleList: WKContentRuleList?
        private var loadedHTML: String?

        func attach(to webView: WKWebView, html: String) {
            guard html != loadedHTML else { return }
            loadedHTML = html
            if let list = Self.ruleList {
                load(webView, html: html, rules: list)
            } else {
                let json = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "ktstack-mail-block-all", encodedContentRuleList: json
                ) { [weak webView] list, _ in
                    Self.ruleList = list
                    guard let webView else { return }
                    self.load(webView, html: html, rules: list)
                }
            }
        }

        private func load(_ webView: WKWebView, html: String, rules: WKContentRuleList?) {
            webView.configuration.userContentController.removeAllContentRuleLists()
            guard let rules else {
                webView.loadHTMLString(
                    "<body style='font:13px -apple-system;color:#888;padding:16px'>Could not render this message safely.</body>",
                    baseURL: nil
                )
                return
            }
            webView.configuration.userContentController.add(rules)
            webView.loadHTMLString(html, baseURL: nil)
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            if scheme == nil || scheme == "about" || scheme == "data" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
