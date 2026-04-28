import SwiftUI
import WebKit

/// SwiftUI wrapper around a WKWebView showing a YouTube embed. Used
/// for fighter community video posts (e.g. Takeru's training reel).
/// Accepts a watch URL or short URL; extracts the video id and loads
/// the embed iframe.
struct YouTubeEmbed: UIViewRepresentable {
    let watchURL: String

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: cfg)
        view.scrollView.isScrollEnabled = false
        view.backgroundColor = .black
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard let videoId = Self.extractVideoId(from: watchURL) else {
            uiView.loadHTMLString(Self.errorHTML, baseURL: nil)
            return
        }
        // playsinline=1 keeps playback inside the card on iPhone;
        // modestbranding=1 removes the YouTube logo overlay.
        let html = """
        <!DOCTYPE html>
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no" />
        <style>
          html, body { margin:0; padding:0; background:#000; height:100%; overflow:hidden; }
          .wrap { position:relative; width:100%; height:100%; }
          iframe { position:absolute; top:0; left:0; width:100%; height:100%; border:0; }
        </style></head>
        <body><div class="wrap">
          <iframe
            src="https://www.youtube.com/embed/\(videoId)?playsinline=1&modestbranding=1&rel=0"
            allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen></iframe>
        </div></body></html>
        """
        uiView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    /// Pulls the video id out of any common YouTube URL form:
    ///   https://www.youtube.com/watch?v=<id>
    ///   https://youtu.be/<id>
    ///   https://www.youtube.com/embed/<id>
    static func extractVideoId(from url: String) -> String? {
        guard let comps = URLComponents(string: url) else { return nil }
        if let host = comps.host {
            if host.contains("youtu.be") {
                let path = comps.path.trimmingCharacters(in: .init(charactersIn: "/"))
                return path.isEmpty ? nil : String(path.split(separator: "/").first ?? "")
            }
            if host.contains("youtube.com") {
                if comps.path.hasPrefix("/embed/") {
                    return String(comps.path.dropFirst("/embed/".count))
                }
                return comps.queryItems?.first(where: { $0.name == "v" })?.value
            }
        }
        return nil
    }

    private static let errorHTML = """
    <html><body style="background:#000;color:#888;font:14px -apple-system;display:flex;align-items:center;justify-content:center;height:100vh;">
    Couldn't load video.
    </body></html>
    """
}
