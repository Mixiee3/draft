import SwiftUI
import DraftCore

/// Crop and reposition a cover. The original image is untouched; only the crop rectangle and
/// ratio are stored, so the same cover can render differently later (cards, export).
struct CoverCropSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.tokens) var t
    let docId: String
    let cover: Cover
    let image: NSImage
    @State private var crop = CropRect(x: 0, y: 0, w: 1, h: 1)
    @State private var ratio = "3:1"
    @State private var dragStart: CropRect?
    @FocusState private var focused: Bool

    var aspect: Double { Double(image.size.width / max(1, image.size.height)) }
    var ratioValue: Double? { CoverCrop.value(of: ratio) }

    var body: some View {
        let box = CGSize(width: 620, height: 360)
        let scale = min(box.width / image.size.width, box.height / image.size.height)
        let disp = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { model.coverEditorDoc = nil }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Crop Cover").font(.system(size: DS.headline, weight: .semibold))
                    Spacer()
                    IconButton(symbol: "xmark", label: "Cancel", size: 26) { model.coverEditorDoc = nil }
                }
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image).resizable().frame(width: disp.width, height: disp.height)
                    let r = CGRect(x: crop.x * disp.width, y: crop.y * disp.height, width: crop.w * disp.width, height: crop.h * disp.height)
                    Path { p in p.addRect(CGRect(origin: .zero, size: disp)); p.addRect(r) }
                        .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                    Rectangle().strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onChanged { g in
                            let s = dragStart ?? crop; dragStart = s
                            crop = CoverCrop.clamped(CropRect(x: s.x + g.translation.width / disp.width, y: s.y + g.translation.height / disp.height, w: s.w, h: s.h))
                        }.onEnded { _ in dragStart = nil })
                        .accessibilityLabel("Crop area. Drag or use the arrow keys to move it.")
                    Circle().fill(Color.white).frame(width: 16, height: 16).shadow(radius: 2)
                        .offset(x: r.maxX - 8, y: r.maxY - 8)
                        .gesture(DragGesture().onChanged { g in
                            let s = dragStart ?? crop; dragStart = s
                            let w = s.w + g.translation.width / disp.width
                            let h = ratioValue.map { w * aspect / $0 } ?? (s.h + g.translation.height / disp.height)
                            crop = CoverCrop.clamped(CropRect(x: s.x, y: s.y, w: w, h: h))
                        }.onEnded { _ in dragStart = nil })
                        .accessibilityLabel("Resize handle")
                }
                .frame(width: disp.width, height: disp.height)
                .clipped()
                .frame(maxWidth: .infinity)
                .focusable()
                .focused($focused)
                .onKeyPress(.leftArrow) { nudge(-0.01, 0) }
                .onKeyPress(.rightArrow) { nudge(0.01, 0) }
                .onKeyPress(.upArrow) { nudge(0, -0.01) }
                .onKeyPress(.downArrow) { nudge(0, 0.01) }
                DraftSegmented("Ratio", selection: $ratio, options: CoverCrop.ratios.map { ($0.id, $0.label) })
                .onChange(of: ratio) { _, r in
                    if r != "free" { crop = CoverCrop.fitted(ratio: CoverCrop.value(of: r), imageAspect: aspect, cx: crop.x + crop.w / 2, cy: crop.y + crop.h / 2) }
                }
                Text("Drag the frame to reposition, the corner to resize. Arrow keys move it in small steps.")
                    .font(.system(size: DS.footnote)).foregroundStyle(t.secondary)
                HStack {
                    Button("Reset") { ratio = "3:1"; crop = CoverCrop.fitted(ratio: 3, imageAspect: aspect, cy: cover.focalY) }
                    Spacer()
                    Button("Cancel") { model.coverEditorDoc = nil }.keyboardShortcut(.cancelAction)
                    Button("Apply") {
                        let c = crop, r = ratio
                        model.updateAppearance(docId) { $0.cover?.crop = c; $0.cover?.ratio = r; $0.cover?.focalY = c.y + c.h / 2 }
                        model.coverEditorDoc = nil
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 680)
            .background(PanelBackground())
        }
        .onAppear {
            ratio = cover.ratio ?? "3:1"
            crop = CoverCrop.effective(cover, imageAspect: aspect)
            focused = true
        }
        .accessibilityAddTraits(.isModal)
    }

    func nudge(_ dx: Double, _ dy: Double) -> KeyPress.Result {
        crop = CoverCrop.clamped(CropRect(x: crop.x + dx, y: crop.y + dy, w: crop.w, h: crop.h))
        return .handled
    }
}
