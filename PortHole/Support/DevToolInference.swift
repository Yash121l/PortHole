import Foundation

/// A label inferred from what a process is *actually running*, rather than
/// from its port number.
struct InferredTool: Equatable, Hashable, Sendable {
    let label: String
    let colorName: String
}

/// Infers the development tool behind a listening process from its process
/// name and real command line (argv). This is what labels a bare `node`
/// process as "Vite" even on a non-standard port: interpreters all look the
/// same by name, but argv says `…/node_modules/.bin/vite dev`.
///
/// Pure and data-driven so it is trivially unit-testable and extendable.
/// Explicit user rules with a process hint still outrank this (see
/// `PortRowView.chip`), and port-only rules act as the fallback.
enum DevToolInference {
    static func infer(processName: String, arguments: [String]?) -> InferredTool? {
        let lowerName = processName.lowercased()
        for entry in processNameMatches where lowerName.contains(entry.fragment) {
            return entry.tool
        }

        guard let arguments, !arguments.isEmpty else { return nil }
        let tokens = arguments.map(normalize)

        for signature in signatures {
            guard let index = tokens.firstIndex(of: signature.binary) else { continue }
            if let subcommand = signature.subcommand {
                guard tokens.dropFirst(index + 1).contains(subcommand) else { continue }
            }
            return signature.tool
        }
        return nil
    }

    /// Basename of an argv token, lowercased, with JS wrapper extensions
    /// stripped so `…/vite/bin/vite.js` matches the `vite` signature.
    /// (Python/Ruby extensions are kept — `manage.py` is meaningful as-is.)
    private static func normalize(_ token: String) -> String {
        var name = token.split(separator: "/").last.map(String.init) ?? token
        name = name.lowercased()
        for ext in [".js", ".mjs", ".cjs", ".ts"] where name.hasSuffix(ext) {
            name = String(name.dropLast(ext.count))
            break
        }
        return name
    }

    // MARK: Signature tables

    /// Matched against the process name alone — covers tools that retitle
    /// their process (Next.js dev retitles to "next-server (v…)") and native
    /// binaries whose name is already the answer.
    private static let processNameMatches: [(fragment: String, tool: InferredTool)] = [
        ("next-server", InferredTool(label: "Next.js dev", colorName: "gray")),
        ("workerd", InferredTool(label: "Cloudflare workerd", colorName: "orange")),
        ("com.docker", InferredTool(label: "Docker", colorName: "blue")),
        ("hugo", InferredTool(label: "Hugo", colorName: "pink")),
        ("caddy", InferredTool(label: "Caddy", colorName: "teal")),
        ("ngrok", InferredTool(label: "ngrok", colorName: "cyan")),
        ("puma", InferredTool(label: "Puma", colorName: "red")),
        ("jekyll", InferredTool(label: "Jekyll", colorName: "brown")),
    ]

    private struct Signature {
        let binary: String
        let subcommand: String?
        let tool: InferredTool

        init(_ binary: String, _ subcommand: String? = nil, _ label: String, _ colorName: String) {
            self.binary = binary
            self.subcommand = subcommand
            self.tool = InferredTool(label: label, colorName: colorName)
        }
    }

    /// Matched against argv basenames, in order — put "tool + subcommand"
    /// before the bare tool so `next dev` beats `next`.
    private static let signatures: [Signature] = [
        // JavaScript ecosystem
        Signature("next", "dev", "Next.js dev", "gray"),
        Signature("next", nil, "Next.js", "gray"),
        Signature("vite", nil, "Vite", "purple"),
        Signature("astro", nil, "Astro", "orange"),
        Signature("nuxt", nil, "Nuxt", "green"),
        Signature("remix", nil, "Remix", "indigo"),
        Signature("react-scripts", nil, "CRA dev", "cyan"),
        Signature("webpack-dev-server", nil, "webpack dev", "blue"),
        Signature("webpack", "serve", "webpack dev", "blue"),
        Signature("storybook", nil, "Storybook", "pink"),
        Signature("wrangler", "dev", "Wrangler dev", "orange"),
        Signature("wrangler", nil, "Wrangler", "orange"),
        Signature("ng", "serve", "Angular dev", "red"),
        Signature("expo", nil, "Expo dev", "indigo"),
        Signature("firebase", "emulators:start", "Firebase emulator", "yellow"),
        Signature("nodemon", nil, "nodemon", "green"),
        Signature("ts-node", nil, "ts-node", "blue"),
        Signature("tsx", nil, "tsx", "blue"),
        Signature("http-server", nil, "http-server", "yellow"),
        Signature("json-server", nil, "json-server", "yellow"),
        Signature("bun", "dev", "Bun dev", "pink"),
        // Python
        Signature("manage.py", "runserver", "Django dev", "green"),
        Signature("uvicorn", nil, "Uvicorn", "teal"),
        Signature("gunicorn", nil, "Gunicorn", "green"),
        Signature("flask", nil, "Flask", "teal"),
        Signature("streamlit", nil, "Streamlit", "red"),
        Signature("jupyter", nil, "Jupyter", "orange"),
        Signature("jupyter-lab", nil, "Jupyter", "orange"),
        Signature("jupyter-notebook", nil, "Jupyter", "orange"),
        Signature("http.server", nil, "http.server", "yellow"),
        Signature("mkdocs", nil, "MkDocs", "teal"),
        // Ruby / PHP
        Signature("rails", "server", "Rails dev", "red"),
        Signature("rails", "s", "Rails dev", "red"),
        Signature("artisan", "serve", "Laravel dev", "red"),
    ]
}
