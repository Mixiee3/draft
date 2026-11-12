import Foundation

/// Standalone HTML for one document, styled with its tokens (or plain). The same HTML is turned
/// into PDF and PNG by the app, so the three always agree. Nothing is loaded from the network.
public enum HTMLExport {
    public struct Options {
        public var useStyle: Bool
        /// Where an asset file is, relative to the HTML file.
        public var assetPath: (String) -> String
        /// Relative link to another exported document, or nil when it isn't exported.
        public var docPath: (String) -> String?
        /// Picture of a scenic backdrop (rendered by the app), relative to the HTML file.
        public var backdropImage: (Backdrop) -> String?
        public var tagColor: (String) -> String
        public var tagRules: TagRules
        public var today: String
        /// Live title of a linked document or block (falls back to the chip text).
        public var linkTitle: (String, String?) -> String?
        public init(useStyle: Bool = true, assetPath: @escaping (String) -> String = { "assets/" + $0 }, docPath: @escaping (String) -> String? = { _ in nil },
                    backdropImage: @escaping (Backdrop) -> String? = { _ in nil }, tagColor: @escaping (String) -> String = Tags.defaultColor,
                    tagRules: TagRules = TagRules(), today: String = Day.today(), linkTitle: @escaping (String, String?) -> String? = { _, _ in nil }) {
            self.useStyle = useStyle; self.assetPath = assetPath; self.docPath = docPath; self.backdropImage = backdropImage
            self.tagColor = tagColor; self.tagRules = tagRules; self.today = today; self.linkTitle = linkTitle
        }
    }

    public struct Result { public var html: String; public var assets: [String]; public var pages: [String] }

    static func esc(_ s: String) -> String {
        var o = ""
        for c in s {
            switch c { case "&": o += "&amp;"; case "<": o += "&lt;"; case ">": o += "&gt;"; case "\"": o += "&quot;"; default: o.append(c) }
        }
        return o
    }
    static func attr(_ s: String) -> String { esc(s).replacingOccurrences(of: "'", with: "&#39;") }
    static func url(_ s: String) -> String { attr(s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(.init(charactersIn: ":#?=&%"))) ?? s) }

    static func fontStack(_ f: String) -> String {
        switch f {
        case "serif": return "ui-serif, 'New York', Georgia, serif"
        case "mono": return "ui-monospace, 'SF Mono', Menlo, monospace"
        case "rounded": return "ui-rounded, 'SF Pro Rounded', system-ui, sans-serif"
        default: return "system-ui, -apple-system, 'Helvetica Neue', sans-serif"
        }
    }

    static func cssColor(_ hex: String, _ opacity: Double?) -> String {
        guard let o = opacity, o < 1, hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return hex }
        return "rgba(\(v >> 16 & 255),\(v >> 8 & 255),\(v & 255),\(String(format: "%.2f", o)))"
    }

    public static func css(_ t: StyleTokens, useStyle: Bool, backdropImage: String?) -> String {
        let page = useStyle ? t.pageColor : "#ffffff", text = useStyle ? t.textColor : "#1f1f1f", accent = useStyle ? t.accent : "#3a5bd9"
        var bg = "#ffffff"
        if useStyle {
            switch t.backdrop.kind {
            case "solid": bg = t.backdrop.color ?? "#e9e6df"
            case "gradient":
                let stops = t.backdrop.colorStops.map { "\(cssColor($0.color, $0.opacity)) \(Int($0.at * 100))%" }.joined(separator: ", ")
                bg = t.backdrop.radial == true
                    ? "radial-gradient(circle at \(Int((t.backdrop.focusX ?? 0.5) * 100))% \(Int((t.backdrop.focusY ?? 0.5) * 100))%, \(stops))"
                    : "linear-gradient(\(Int((t.backdrop.angle ?? 135) + 90))deg, \(stops))"
            case "field": bg = backdropImage.map { "\(t.backdrop.colorStops.first?.color ?? t.shellTint) url('\($0)') center / cover no-repeat fixed" } ?? (t.backdrop.colorStops.first?.color ?? t.shellTint)
            case "image": bg = backdropImage.map { "\(t.shellTint) url('\($0)') center / cover no-repeat fixed" } ?? t.shellTint
            default: bg = t.shellTint
            }
        }
        let line = "color-mix(in srgb, \(text) 14%, transparent)"
        let fx = TextEffects.colors(accent: accent, text: text, page: page)
        let dark = ColorMath.isDark(page)
        return """
        :root{--page:\(page);--text:\(text);--accent:\(accent);--soft:color-mix(in srgb, \(text) 58%, transparent);--line:\(line);--fx1:\(fx.start);--fx2:\(fx.end)}
        .fx-accent,.fx-glow,.fx-lift{color:var(--fx1)}.fx-glow{text-shadow:0 0 calc(2px + 5px * var(--fxi,.6)) color-mix(in srgb, var(--fxc,var(--accent)) \(dark ? 95 : 75)%, transparent)}
        .fx-shadow{text-shadow:0 calc(.8px + 1.2px * var(--fxi,.6)) calc(.5px + 1.2px * var(--fxi,.6)) color-mix(in srgb, var(--fxc,#000) \(dark ? 70 : 35)%, transparent)}.fx-lift{text-shadow:calc(.5px + .8px * var(--fxi,.6)) calc(.5px + .8px * var(--fxi,.6)) 0 color-mix(in srgb, var(--fxc,var(--fx2)) 30%, transparent)}
        .fx-emboss{text-shadow:0 \(dark ? "1px" : "-1px") 0 color-mix(in srgb, var(--fxc,\(dark ? "#fff" : "#000")) \(dark ? 30 : 40)%, transparent)}.fx-outline{-webkit-text-stroke:calc(.3px + .9px * var(--fxi,.6)) color-mix(in srgb, var(--fxc,var(--accent)) 85%, transparent);paint-order:stroke fill}
        .fx-gradient{background:linear-gradient(90deg,var(--fx1),var(--fx2));-webkit-background-clip:text;background-clip:text;color:transparent}
        .fx-spectrum{-webkit-background-clip:text;background-clip:text;color:transparent}@media (prefers-contrast: more){.fx-spectrum{background:none!important;color:var(--fx1)}}
        [data-deco]{--t:var(--tint,var(--accent));border-radius:10px;padding:6px 12px;margin:.5em 0}[data-deco=focus]{border-radius:0;padding:0 0 0 14px;border-left:3px solid var(--t)}
        [data-deco=block]{background:color-mix(in srgb, var(--tint,var(--text)) \(dark ? 28 : 12)%, transparent)}[data-deco=gradient]{background:linear-gradient(90deg,color-mix(in srgb, var(--t) \(dark ? 32 : 20)%, transparent),color-mix(in srgb, var(--t) \(dark ? 6 : 3)%, transparent))}
        [data-deco=glass]{background:rgba(255,255,255,\(dark ? ".07" : ".6"));border:.5px solid \(dark ? "rgba(255,255,255,.18)" : "color-mix(in srgb, var(--text) 10%, transparent)");backdrop-filter:blur(12px)}
        [data-deco=glow]{background:color-mix(in srgb, var(--t) \(dark ? 16 : 7)%, transparent);border:1px solid color-mix(in srgb, var(--t) 60%, transparent);box-shadow:0 0 10px color-mix(in srgb, var(--t) \(dark ? 70 : 45)%, transparent)}
        [data-deco=accent]{background:color-mix(in srgb, var(--t) \(dark ? 8 : 4)%, transparent);border:1.5px solid var(--t)}h1[data-deco=accent],h2[data-deco=accent],h3[data-deco=accent],h4[data-deco=accent]{background:none;border:0;border-radius:0;padding:0 0 6px;background:linear-gradient(var(--t),var(--t)) left bottom/64px 3px no-repeat}
        @media (prefers-contrast: more){[data-deco]{box-shadow:none!important;backdrop-filter:none!important}[data-deco=gradient]{background:color-mix(in srgb, var(--t) 12%, transparent)}}
        @media (prefers-contrast: more){.fx{text-shadow:none!important;-webkit-text-stroke:0!important}}
        *{box-sizing:border-box}html{background:\(bg)}body{margin:0;padding:48px 16px;font:17px/1.6 \(fontStack(useStyle ? t.font : "system"));color:var(--text);-webkit-print-color-adjust:exact;print-color-adjust:exact}
        main{max-width:760px;margin:0 auto;background:var(--page);border-radius:\(useStyle ? 22 : 0)px;padding:56px 64px;\(useStyle && t.backdrop.kind != "none" ? "box-shadow:0 8px 40px rgba(0,0,0,.12);" : "")}
        h1.doc-title{font-size:38px;line-height:1.15;margin:0 0 8px}hr.title{border:0;border-top:1px solid var(--line);margin:18px 0 26px}
        h1{font-size:30px}h2{font-size:23px}h3{font-size:19px}h4{font-size:17px}h1,h2,h3,h4{margin:1.2em 0 .4em;line-height:1.2}
        p{margin:.2em 0 .5em}small,.caption{font-size:13.5px;color:var(--soft)}a{color:var(--accent)}
        blockquote{margin:.6em 0;padding:.1em 0 .1em 18px;border-left:3px solid var(--accent)}
        .callout{display:flex;gap:12px;padding:12px 16px;border-radius:12px;background:color-mix(in srgb, var(--accent) 10%, transparent);margin:.6em 0}
        pre{font:14px/1.45 ui-monospace,Menlo,monospace;background:color-mix(in srgb, var(--text) 6%, transparent);padding:14px 16px;border-radius:10px;overflow:auto;white-space:pre-wrap}
        code{font:0.88em ui-monospace,Menlo,monospace;background:color-mix(in srgb, var(--text) 7%, transparent);padding:1px 4px;border-radius:4px}
        mark{border-radius:3px;padding:0 2px;color:#1d1d1b}ul,ol{padding-left:26px;margin:.2em 0 .6em}li{margin:.15em 0}
        ul.tasks{list-style:none;padding-left:4px}ul.tasks li{display:flex;gap:9px;align-items:baseline}ul.tasks li.done>span{text-decoration:line-through;color:var(--soft)}
        .box{display:inline-block;width:14px;height:14px;border:1.5px solid var(--soft);border-radius:4px;flex:none;position:relative;top:2px}li.done .box{background:var(--accent);border-color:var(--accent)}
        details{margin:.3em 0}summary{cursor:pointer}
        hr.sep{border:0;margin:22px 0;height:1px;background:var(--line)}hr.sep.strong{height:2.5px;background:color-mix(in srgb, var(--text) 55%, transparent)}
        hr.sep.dotted{background:none;border-top:3px dotted var(--line)}hr.sep.dots{background:none;height:auto;text-align:center}hr.sep.dots::after{content:'• • •';color:var(--soft)}
        hr.sep.wave{height:8px;background:none;border-bottom:2px wavy var(--accent);text-decoration:none}
        hr.sep.tape{height:18px;width:46%;margin:22px auto;background:color-mix(in srgb, var(--accent) 32%, transparent);transform:rotate(var(--r,-1.6deg))}
        .page-break{break-after:page;page-break-after:always;height:0}
        figure{margin:.8em 0}figure img{max-width:100%;border-radius:10px;display:block}figcaption{font-size:13px;color:var(--soft);margin-top:4px}
        a.card,a.bookmark,div.card{display:flex;gap:14px;align-items:center;text-decoration:none;color:inherit;border:1px solid var(--line);border-radius:14px;padding:14px;margin:.6em 0;background:color-mix(in srgb, var(--text) 3.5%, transparent)}
        .card .thumb{width:40px;height:56px;border-radius:8px;background:var(--tint,var(--accent));flex:none;display:flex;align-items:center;justify-content:center;color:var(--page);font-weight:700;background-size:cover;background-position:center}
        .card.compact .thumb{width:30px;height:34px}.card.feature{flex-direction:column;align-items:stretch}.card.feature .thumb{width:100%;height:160px}
        .card b,.bookmark b{display:block}.card span,.bookmark span{color:var(--soft);font-size:13px}
        .chip{color:var(--accent);background:color-mix(in srgb, var(--accent) 10%, transparent);border-radius:5px;padding:0 3px;text-decoration:none}
        .chip.missing{color:var(--soft);text-decoration:line-through}.date.plain{background:none;color:inherit;padding:0}
        .tag{border-radius:4px;padding:0 2px}
        table.grid{border-collapse:collapse;width:100%;margin:.6em 0;font-size:.92em}table.grid th,table.grid td{border:1px solid var(--line);padding:6px 10px;text-align:left;vertical-align:top}table.grid th{background:color-mix(in srgb, var(--text) 5%, transparent);font-weight:600}
        .file{display:inline-flex;gap:8px;border:1px solid var(--line);border-radius:10px;padding:8px 12px}
        @media (max-width:640px){body{padding:16px 0}main{padding:28px 20px;border-radius:0}}
        @media print{html{background:\(useStyle ? bg : "#fff")}body{padding:0}main{box-shadow:none;max-width:none;border-radius:0}}
        """
    }

    public static func render(_ doc: DocFile, tokens: StyleTokens, _ o: Options, dateChips: Bool = true) -> Result {
        var assets: [String] = []
        var pages: [String] = []
        var numbering = 0

        func inline(_ nodes: [Node]?) -> String {
            var out = ""
            for n in nodes ?? [] {
                if n.type == "hardBreak" { out += "<br>"; continue }
                guard n.type == "text", var t = n.text else { continue }
                let marks = n.marks ?? []
                if let dl = marks.first(where: { $0.type == "docLink" }), let d = dl.attrs?["docId"]?.string {
                    let b = dl.attrs?["blockId"]?.string
                    t = o.linkTitle(d, b) ?? t
                    if let p = o.docPath(d) { out += "<a class='chip' href='\(url(p + (b.map { "#" + $0 } ?? "")))'>\(esc(t))</a>" }
                    else { out += "<span class='chip'>\(esc(t))</span>" }
                    continue
                }
                if let dm = marks.first(where: { $0.type == "date" }), let d = dm.attrs?["date"]?.string {
                    out += "<time class='chip date\(dateChips ? "" : " plain")' datetime='\(attr(d))'>\(esc(Day.chipLabel(d, today: o.today)))</time>"
                    continue
                }
                var s = ""
                if marks.contains(where: { ["code", "link"].contains($0.type) }) { s = esc(t) } else {
                    var last = t.startIndex
                    for tag in Tags.find(in: t, rules: o.tagRules) {
                        guard let r = Range(tag.range, in: t) else { continue }
                        let c = o.tagColor(tag.name)
                        s += esc(String(t[last..<r.lowerBound])) + "<span class='tag' style='color:\(c);background:\(c)1f'>\(esc(String(t[r])))</span>"
                        last = r.upperBound
                    }
                    s += esc(String(t[last...]))
                }
                for m in marks {
                    switch m.type {
                    case "bold": s = "<strong>\(s)</strong>"
                    case "italic": s = "<em>\(s)</em>"
                    case "underline": s = "<u>\(s)</u>"
                    case "strike": s = "<s>\(s)</s>"
                    case "code": s = "<code>\(s)</code>"
                    case "highlight": s = "<mark style='background:\(attr(m.attrs?["color"]?.string ?? "#fff3a3"))'>\(s)</mark>"
                    case "textStyle": if let c = m.attrs?["color"]?.string { s = "<span style='color:\(attr(c))'>\(s)</span>" }
                    case "effect":
                        guard let e = EffectSpec(mark: m), !marks.contains(where: { $0.type == "highlight" }) else { break }
                        let page = o.useStyle ? tokens.pageColor : "#ffffff"
                        var css: [String] = []
                        if ["gradient", "spectrum"].contains(e.kind) {
                            // A still gradient: exports never animate.
                            let c = e.fillColors(accent: o.useStyle ? tokens.accent : "#3a5bd9", text: o.useStyle ? tokens.textColor : "#1f1f1f", page: page)
                            let stops = zip(c.indices, c).map { i, col in e.stopLocations.map { "\(col) \(Int($0[i] * 100))%" } ?? col }.joined(separator: ",")
                            css.append(e.isRadial ? "background-image:radial-gradient(circle at \(Int((e.focusX ?? 0.5) * 100))% \(Int((e.focusY ?? 0.5) * 100))%,\(stops))"
                                                  : "background-image:linear-gradient(\(Int((e.angle ?? 0) + 90))deg,\(stops))")
                        }
                        if e.kind == "accent" { css.append("color:\(e.fillColors(accent: o.useStyle ? tokens.accent : "#3a5bd9", text: "", page: page)[0])") }
                        if let c = e.color, e.kind != "accent" { css.append("--fxc:\(c)") }
                        if let i = e.intensity { css.append("--fxi:\(String(format: "%.2f", i))") }
                        s = "<span class='fx fx-\(e.kind)'\(css.isEmpty ? "" : " style='\(css.joined(separator: ";"))'")>\(s)</span>"
                    default: break
                    }
                }
                if let l = marks.first(where: { $0.type == "link" }), let h = l.attrs?["href"]?.string {
                    if let (d, b) = parseDraftURL(h), let p = o.docPath(d) { s = "<a href='\(url(p + (b.map { "#" + $0 } ?? "")))'>\(s)</a>" }
                    else if !h.hasPrefix("draft://") { s = "<a href='\(attr(h))'>\(s)</a>" }
                }
                out += s
            }
            return out
        }

        func styleAttr(_ n: Node) -> String {
            var css: [String] = []
            if let f = n.attrs?["font"]?.string { css.append("font-family:\(fontStack(f))") }
            if let a = n.attrs?["textAlign"]?.string, a != "left" { css.append("text-align:\(a)") }
            let deco = n.attrs?["decoration"]?.string.flatMap { BlockEffects.kinds.contains($0) ? $0 : nil }
            if let c = n.attrs?["blockColor"]?.string { css.append(deco.map { _ in "--tint:\(c)" } ?? "background:\(c)22;border-radius:8px;padding:4px 10px") }
            let id = n.id.map { " id='\(attr($0))'" } ?? ""
            return id + (deco.map { " data-deco='\($0)'" } ?? "") + (css.isEmpty ? "" : " style='\(css.joined(separator: ";"))'")
        }

        func items(_ list: Node) -> String {
            (list.content ?? []).map { item in
                let kids = item.content ?? []
                let first = kids.first.map { $0.type == "paragraph" ? inline($0.content) : "" } ?? ""
                let rest = kids.dropFirst(kids.first?.type == "paragraph" ? 1 : 0).map(block).joined()
                switch list.type {
                case "taskList":
                    let done = item.attrs?["checked"]?.bool ?? false
                    return "<li\(styleAttr(item))\(done ? " class='done'" : "")><i class='box' role='img' aria-label='\(done ? "done" : "not done")'></i><span>\(first)\(rest)</span></li>"
                case "toggleList":
                    return "<li\(styleAttr(item))><details\((item.attrs?["open"]?.bool ?? true) ? " open" : "")><summary>\(first)</summary>\(rest)</details></li>"
                default:
                    return "<li\(styleAttr(item))>\(first)\(rest)</li>"
                }
            }.joined()
        }

        func block(_ n: Node) -> String {
            switch n.type {
            case "paragraph":
                let c = inline(n.content)
                return n.attrs?["variant"]?.string == "caption" ? "<p class='caption'\(styleAttr(n))>\(c)</p>" : "<p\(styleAttr(n))>\(c.isEmpty ? "<br>" : c)</p>"
            case "heading":
                let l = max(1, min(4, n.attrs?["level"]?.int ?? 1))
                return "<h\(l)\(styleAttr(n))>\(inline(n.content))</h\(l)>"
            case "blockquote": return "<blockquote\(styleAttr(n))>\((n.content ?? []).map(block).joined())</blockquote>"
            case "callout": return "<div class='callout'\(styleAttr(n))><span aria-hidden='true'>\(esc(n.attrs?["icon"]?.string ?? "💡"))</span><div>\((n.content ?? []).map(block).joined())</div></div>"
            case "codeBlock": return "<pre\(styleAttr(n))><code>\(esc((n.content ?? []).map { $0.text ?? "" }.joined()))</code></pre>"
            case "horizontalRule":
                let v = n.attrs?["variant"]?.string ?? (o.useStyle ? tokens.separator : "line")
                let rot = v == "tape" ? " style='--r:\(String(format: "%.1f", -3 + 6 * Variation.unit(n.id ?? "", 2)))deg'" : ""
                return "<hr class='sep \(attr(v))'\(rot)>"
            case "pageBreak": return "<div class='page-break'></div>"
            case "bulletList": return "<ul\(styleAttr(n))>\(items(n))</ul>"
            case "orderedList":
                numbering += 1
                return "<ol start='\(n.attrs?["start"]?.int ?? 1)'\(styleAttr(n))>\(items(n))</ol>"
            case "taskList": return "<ul class='tasks'\(styleAttr(n))>\(items(n))</ul>"
            case "toggleList": return "<ul class='toggles'\(styleAttr(n))>\(items(n))</ul>"
            case "image":
                var src = n.attrs?["src"]?.string ?? ""
                if let a = n.attrs?["assetId"]?.string { assets.append(a); src = o.assetPath(a) }
                let w = n.attrs?["width"]?.double.map { " style='width:\(Int($0 * 100))%'" } ?? ""
                let cap = n.attrs?["caption"]?.string.flatMap { $0.isEmpty ? nil : "<figcaption>\(esc($0))</figcaption>" } ?? ""
                return "<figure\(n.id.map { " id='\(attr($0))'" } ?? "")><img src='\(url(src))' alt='\(attr(n.attrs?["alt"]?.string ?? ""))'\(w)>\(cap)</figure>"
            case "file":
                let name = n.attrs?["name"]?.string ?? "File"
                guard let a = n.attrs?["assetId"]?.string else { return "<p>\(esc(name))</p>" }
                assets.append(a)
                return "<p><a class='file' href='\(url(o.assetPath(a)))' download='\(attr(name))'>📎 \(esc(name))</a></p>"
            case "pageCard":
                let d = n.attrs?["docId"]?.string ?? ""
                let title = o.linkTitle(d, nil) ?? n.attrs?["title"]?.string ?? "Untitled page"
                if !d.isEmpty { pages.append(d) }
                let size = n.attrs?["size"]?.string ?? "medium", preview = n.attrs?["preview"]?.string ?? "standard"
                let letter = preview == "standard" ? "" : esc(String(title.prefix(1)).uppercased())
                let inner = "<i class='thumb'>\(letter)</i><div><b>\(esc(title.isEmpty ? "Untitled page" : title))</b></div>"
                if let p = o.docPath(d) { return "<a class='card \(attr(size))' href='\(url(p))'>\(inner)</a>" }
                return "<div class='card \(attr(size))'>\(inner)</div>"
            case "table":
                let rows = n.content ?? []
                let head = rows.first.map { "<thead><tr>" + ($0.content ?? []).map { "<th>\(inline($0.content))</th>" }.joined() + "</tr></thead>" } ?? ""
                let body = rows.dropFirst().map { "<tr>" + ($0.content ?? []).map { "<td>\(inline($0.content))</td>" }.joined() + "</tr>" }.joined()
                return "<table class='grid'\(styleAttr(n))>\(head)<tbody>\(body)</tbody></table>"
            case "collection":
                guard let c = CollectionData(node: n) else { return "" }
                let title: (String) -> String = { o.linkTitle($0, nil) ?? "Untitled" }
                let head = "<tr><th>Name</th>" + c.fields.map { "<th>\(esc($0.name))</th>" }.joined() + "</tr>"
                let body = c.items.map { it -> String in
                    pages.append(it.docId)
                    let name = esc(title(it.docId))
                    let cell = o.docPath(it.docId).map { "<a href='\(url($0))'>\(name)</a>" } ?? name
                    return "<tr><td>\(cell)</td>" + c.fields.map { "<td>\(esc(c.display(it, $0.id, title: title)))</td>" }.joined() + "</tr>"
                }.joined()
                return "<figure class='collection'><figcaption>\(esc(c.name))</figcaption><table class='grid'><thead>\(head)</thead><tbody>\(body)</tbody></table></figure>"
            case "linkPreview":
                let u = n.attrs?["url"]?.string ?? ""
                return "<a class='bookmark' href='\(attr(u))'><div><b>\(esc(n.attrs?["title"]?.string ?? u))</b>\(n.attrs?["summary"]?.string.map { "<span>\(esc($0))</span><br>" } ?? "")<span>\(esc(u))</span></div></a>"
            default:
                return n.content.map { $0.map(block).joined() } ?? ""
            }
        }

        let body = (doc.content.content ?? []).map(block).joined(separator: "\n")
        var cover = ""
        if o.useStyle, let c = doc.appearance.cover { assets.append(c.assetId); cover = "<img class='cover' src='\(url(o.assetPath(c.assetId)))' alt='' style='width:100%;border-radius:14px;margin-bottom:24px;max-height:260px;object-fit:cover'>" }
        let title = doc.title.isEmpty ? "Untitled" : doc.title
        let html = """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Draft"><title>\(esc(title))</title>
        <style>\(css(tokens, useStyle: o.useStyle, backdropImage: o.backdropImage(tokens.backdrop)))</style></head>
        <body><main>\(cover)<h1 class="doc-title">\(esc(title))</h1><hr class="title">
        \(body)
        </main></body></html>
        """
        return Result(html: html, assets: assets, pages: pages)
    }
}

/// An offline website: index.html plus one page per document, linked relatively.
public enum SiteExport {
    public struct Bundle { public var files: [(path: String, content: String)]; public var assets: [String]; public var docs: [String] }

    public static func build(rootIds: [String], metas: [String: DocMeta], folders: [Folder], load: (String) -> DocFile?,
                             options: (String) -> HTMLExport.Options, tokens: (DocFile) -> StyleTokens, dateChips: Bool = true, siteTitle: String) -> Bundle {
        var queue = rootIds, seen = Set<String>(), docs: [DocFile] = []
        while let id = queue.first {
            queue.removeFirst()
            guard !seen.contains(id), let d = load(id) else { continue }
            seen.insert(id); docs.append(d)
            walk(d.content) { n in
                if n.type == "pageCard", let c = n.attrs?["docId"]?.string { queue.append(c) }
                if let c = CollectionData(node: n) { queue += c.items.map(\.docId) }
            }
        }
        var names: [String: String] = [:], used = Set<String>(["index.html"])
        for d in docs {
            let base = Markdown.safeFileName(d.title.isEmpty ? "Untitled" : d.title)
            var p = base + ".html", i = 2
            while used.contains(p.lowercased()) { p = "\(base) \(i).html"; i += 1 }
            used.insert(p.lowercased()); names[d.id] = p
        }
        var files: [(String, String)] = [], assets: [String] = []
        for d in docs {
            var o = options(d.id)
            o.docPath = { names[$0] }
            let r = HTMLExport.render(d, tokens: tokens(d), o, dateChips: dateChips)
            let nav = "<nav style='max-width:760px;margin:0 auto 14px;font:14px system-ui'><a href='index.html'>← \(HTMLExport.esc(siteTitle))</a></nav>"
            files.append((names[d.id]!, r.html.replacingOccurrences(of: "<body><main>", with: "<body>\(nav)<main>")))
            assets += r.assets
        }
        let roots = rootIds.compactMap { id in docs.first { $0.id == id } }
        var groups: [(String, [DocFile])] = []
        for d in roots {
            let f = metas[d.id]?.folderId.flatMap { fid in folders.first { $0.id == fid }?.name } ?? "Unsorted"
            if let i = groups.firstIndex(where: { $0.0 == f }) { groups[i].1.append(d) } else { groups.append((f, [d])) }
        }
        let list = groups.map { name, ds in
            "<h2>\(HTMLExport.esc(name))</h2><ul>" + ds.map { "<li><a href='\(HTMLExport.url(names[$0.id]!))'>\(HTMLExport.esc($0.title.isEmpty ? "Untitled" : $0.title))</a></li>" }.joined() + "</ul>"
        }.joined()
        let index = """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="generator" content="Draft">
        <title>\(HTMLExport.esc(siteTitle))</title><style>\(HTMLExport.css(Styles.builtIn[0].tokens, useStyle: false, backdropImage: nil))</style></head>
        <body><main><h1 class="doc-title">\(HTMLExport.esc(siteTitle))</h1><hr class="title">\(list)</main></body></html>
        """
        files.insert(("index.html", index), at: 0)
        return Bundle(files: files, assets: Array(Set(assets)), docs: docs.map(\.id))
    }
}
