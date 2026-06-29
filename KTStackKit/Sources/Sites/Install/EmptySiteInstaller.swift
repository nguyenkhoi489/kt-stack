import Foundation

public struct EmptySiteInstaller: SiteInstaller {
    public init() {}

    public func scaffold(
        into folder: URL,
        request: NewSiteRequest,
        emit: @Sendable (String) -> Void
    ) async throws {
        emit("Creating empty site…")
        let index = folder.appendingPathComponent("index.php")
        try Self.welcomePage(domain: request.domain)
            .data(using: .utf8)!
            .write(to: index, options: .atomic)
        emit("Created index.php")
    }

    static func welcomePage(domain: String) -> String {
        """
        <?php $php = phpversion(); ?>
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(domain)</title>
        <style>
        :root { color-scheme: light dark; }
        body { margin: 0; min-height: 100vh; display: grid; place-items: center;
               font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
               background: #0f1117; color: #e6e8ee; }
        main { max-width: 34rem; padding: 2.5rem; text-align: center; }
        h1 { font-size: 1.6rem; margin: 0 0 .75rem; }
        p { margin: .4rem 0; color: #9aa2b1; line-height: 1.5; }
        strong { color: #e6e8ee; }
        code { background: #1b1e27; padding: .15rem .4rem; border-radius: .35rem; color: #e6e8ee; }
        </style>
        </head>
        <body>
        <main>
        <h1>It works 🎉</h1>
        <p>Your empty site <strong>\(domain)</strong> is ready.</p>
        <p>Running on PHP <?= htmlspecialchars($php) ?> · served by KTStack</p>
        <p>Replace <code>index.php</code> in this folder to start building.</p>
        </main>
        </body>
        </html>
        """
    }
}
