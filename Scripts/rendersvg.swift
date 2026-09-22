// Renders an SVG to an exact-size PNG through WKWebView. qlmanage adds a document
// shadow and margin, and ImageMagick has no rsvg delegate here, so neither can do it.
import Cocoa
import WebKit

let args = CommandLine.arguments
guard args.count >= 4, let side = Int(args[3]) else {
    FileHandle.standardError.write("usage: rendersvg <in.svg> <out.png> <size>\n".data(using: .utf8)!)
    exit(2)
}
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let svg = try! String(contentsOf: inURL, encoding: .utf8)

let html = """
<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;background:transparent;}
svg{display:block;width:\(side)px;height:\(side)px;}</style></head>
<body>\(svg)</body></html>
"""

final class Snapper: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let out: URL
    let side: Int
    init(out: URL, side: Int) {
        self.out = out
        self.side = side
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: side, height: side), configuration: cfg)
        web.setValue(false, forKey: "drawsBackground")
        super.init()
        web.navigationDelegate = self
    }
    func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
        // One runloop turn so the SVG paints before the snapshot is taken.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = NSRect(x: 0, y: 0, width: self.side, height: self.side)
            w.takeSnapshot(with: cfg) { image, err in
                guard let image, err == nil else {
                    FileHandle.standardError.write("snapshot failed: \(String(describing: err))\n".data(using: .utf8)!)
                    exit(1)
                }
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: self.side, pixelsHigh: self.side,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                image.draw(in: NSRect(x: 0, y: 0, width: self.side, height: self.side))
                NSGraphicsContext.restoreGraphicsState()
                try! rep.representation(using: .png, properties: [:])!.write(to: self.out)
                exit(0)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let snapper = Snapper(out: outURL, side: side)
snapper.web.loadHTMLString(html, baseURL: nil)
app.run()
