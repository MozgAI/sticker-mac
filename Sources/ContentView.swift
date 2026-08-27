import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Фирменный розовый — тот же, что на значке приложения.
extension Color {
    static let sticker = Color(red: 0.925, green: 0.118, blue: 0.471)
}

struct ContentView: View {
    @StateObject private var printer = Printer()
    @ObservedObject private var loc = L10n.shared
    @ObservedObject private var inbox = Inbox.shared
    @State private var layout = Layout()
    @State private var source: CGImage?
    @State private var fileName = ""
    @State private var showAsPrinted = true
    @State private var dragStart: CGSize?
    @State private var flipPreview = false
    @State private var error: String?

    private var composed: CGImage? { Renderer.compose(image: source, layout: layout) }

    private var preview: NSImage? {
        guard let img = Renderer.colorPreview(image: source, layout: layout,
                                              printed: showAsPrinted) else { return nil }
        return NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
    }

    var body: some View {
        HStack(spacing: 0) {
            canvas
            Divider()
            controls.frame(width: 310)
        }
        .frame(minWidth: 940, minHeight: 640)
        .onReceive(inbox.$url.compactMap { $0 }) { set($0) }
        .alert(loc("errorTitle"), isPresented: .constant(error != nil)) {
            Button(loc("errorOK")) { error = nil }
        } message: { Text(error ?? "") }
    }

    // MARK: - холст

    private var canvas: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle(isOn: $flipPreview) {
                    Label(loc("flipPreview"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .toggleStyle(.button)
                .controlSize(.large)
                .help(loc("flipHelp"))
                if flipPreview {
                    Text(loc("flipOn")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                if let p = preview {
                    Image(nsImage: p)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(flipPreview ? 180 : 0))
                        .padding(18)
                }
                if source == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 42))
                        Text(loc("dropHere")).font(.title3)
                        Text(loc("dropHint")).font(.caption).foregroundStyle(.secondary)
                    }.foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .gesture(
                DragGesture()
                    .onChanged { g in
                        if dragStart == nil { dragStart = CGSize(width: layout.panX, height: layout.panY) }
                        let s = dragStart!
                        let k: CGFloat = flipPreview ? -1 : 1
                        layout.panX = s.width + g.translation.width / 400 * k
                        layout.panY = s.height + g.translation.height / 400 * k
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                load(from: providers); return true
            }

            Text(source == nil ? loc("noFile")
                 : "\(fileName)  ·  \(loc("dragToMove"))  ·  \(Int(layout.zoom * 100))%")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - панель

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                group(loc("sectionPrint")) {
                    HStack(spacing: 10) {
                        Button { printNow() } label: {
                            Label(printer.busy ? loc("printing") : loc("print"),
                                  systemImage: "printer.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.sticker)
                        .controlSize(.large)
                        .disabled(!printer.connected || printer.busy || source == nil)

                        Stepper(value: $layout.copies, in: 1...200) {
                            Text("\(layout.copies)").monospacedDigit().frame(width: 28)
                        }
                    }
                    if printer.busy { ProgressView(value: printer.progress) }
                    HStack(spacing: 6) {
                        Circle().fill(printer.connected ? .green : .orange).frame(width: 8, height: 8)
                        Text(printer.connected ? "\(printer.connectedName) · \(loc("ready"))"
                                               : printer.status)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack {
                        Button(loc("testShape")) { printNow(testOnly: true) }
                            .disabled(!printer.connected || printer.busy)
                            .help(loc("testHelp"))
                        Button(loc("savePNG")) { savePNG() }.disabled(composed == nil)
                    }
                }
                Divider()

                group(loc("sectionImage")) {
                    HStack {
                        Button(loc("open")) { openFile() }
                        Button(loc("center")) { layout.panX = 0; layout.panY = 0; layout.zoom = 1 }
                            .disabled(source == nil)
                    }
                    labeled(loc("scale"), String(format: "%.0f%%", layout.zoom * 100))
                    Slider(value: $layout.zoom, in: 0.4...4)
                }

                group(loc("sectionShape")) {
                    Picker("", selection: $layout.shape) {
                        Text(loc("circle")).tag(Shape.circle)
                        Text(loc("rect")).tag(Shape.rect)
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    if layout.shape == .circle {
                        labeled(loc("diameter"), mm(layout.printMM))
                        Slider(value: $layout.printMM, in: 10...48, step: 1)
                    } else {
                        labeled(loc("artWidth"), mm(layout.printWMM))
                        Slider(value: $layout.printWMM, in: 10...48, step: 1)
                        labeled(loc("artHeight"), mm(layout.printHMM))
                        Slider(value: $layout.printHMM, in: 8...80, step: 1)
                        labeled(loc("corner"), mm(layout.cornerMM))
                        Slider(value: $layout.cornerMM, in: 0...10, step: 0.5)
                    }
                    hint(loc("shapeHint"))
                }

                group(loc("sectionLabel")) {
                    labeled(loc("feed"), mm(layout.labelMM))
                    Slider(value: $layout.labelMM, in: 10...80, step: 1)
                    if layout.shape == .rect {
                        labeled(loc("labelWidth"), mm(layout.labelWMM))
                        Slider(value: $layout.labelWMM, in: 10...48, step: 1)
                    }
                    hint(loc("feedHint"))
                }

                group(loc("sectionAlign")) {
                    nudgePad
                    hint(flipPreview ? loc("alignFlipped") : loc("alignHint"))
                }

                group(loc("sectionOrient")) {
                    Picker("", selection: Binding(
                        get: { layout.mirror ? (layout.flip180 ? 3 : 1) : (layout.flip180 ? 2 : 0) },
                        set: { v in layout.mirror = (v == 1 || v == 3)
                                   layout.flip180 = (v == 2 || v == 3) })) {
                        Text(loc("asIs")).tag(0)
                        Text(loc("mirror")).tag(1)
                        Text("180°").tag(2)
                        Text(loc("both")).tag(3)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    hint(loc("orientHint"))

                    labeled(loc("quality"), layout.speed <= 2 ? loc("qMax")
                            : (layout.speed >= 5 ? loc("qFast") : loc("qMid")))
                    Picker("", selection: $layout.speed) {
                        Text(loc("qMax")).tag(1)
                        Text(loc("qMid")).tag(3)
                        Text(loc("qFast")).tag(5)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }

                group(loc("sectionHow")) {
                    Picker("", selection: $layout.dither) {
                        Text(loc("artwork")).tag(false)
                        Text(loc("photo")).tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    hint(layout.dither ? loc("photoHint") : loc("artworkHint"))

                    if !layout.dither {
                        labeled(loc("threshold"), "\(layout.threshold)")
                        Slider(value: Binding(get: { Double(layout.threshold) },
                                              set: { layout.threshold = Int($0) }),
                               in: 60...240, step: 5)
                        hint(loc("thresholdHint"))
                    }

                    labeled(loc("cleanBG"), String(format: "%.0f%%", layout.cleanBG * 100))
                    Slider(value: $layout.cleanBG, in: 0...0.4)
                    hint(loc("cleanHint"))

                    Toggle(loc("negative"), isOn: $layout.invert)
                    Toggle(loc("showPrinted"), isOn: $showAsPrinted)
                    labeled(loc("brightness"), String(format: "%+.2f", layout.brightness))
                    Slider(value: $layout.brightness, in: -0.5...0.5)
                    labeled(loc("contrast"), String(format: "%.2f", layout.contrast))
                    Slider(value: $layout.contrast, in: 0.5...2.5)
                    labeled(loc("density"), "\(layout.density)")
                    Slider(value: Binding(get: { Double(layout.density) },
                                          set: { layout.density = Int($0) }), in: 1...15, step: 1)
                }

                Divider()
                group(loc("sectionPrinter")) {
                    HStack {
                        TextField(loc("namePlaceholder"), text: Binding(
                            get: { printer.nameFilter },
                            set: { printer.setFilter($0) }))
                            .textFieldStyle(.roundedBorder)
                        Button(loc("scan")) { printer.startScan() }
                    }
                    hint(loc("filterHint"))

                    if printer.connected {
                        HStack {
                            if printer.pinnedID == nil {
                                Button(loc("pin")) { printer.pinCurrent() }
                            } else {
                                Label(loc("pinned"), systemImage: "pin.fill").font(.caption)
                                Spacer()
                                Button(loc("forget")) { printer.unpin() }.font(.caption)
                            }
                        }
                        HStack {
                            Text(printer.connectedName).font(.caption).bold()
                            Spacer()
                            Button(loc("disconnect")) { printer.disconnect() }.font(.caption)
                        }
                    } else {
                        if !printer.devices.isEmpty {
                            hint(loc("devicesHint"))
                            ForEach(printer.devices.prefix(8)) { d in
                                Button { printer.connect(to: d) } label: {
                                    HStack {
                                        Image(systemName: d.likely ? "printer" : "dot.radiowaves.left.and.right")
                                        Text(d.name).lineLimit(1)
                                        Spacer()
                                        Text("\(d.rssi)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }

                Divider()
                languagePicker
            }
            .padding(18)
        }
    }

    /// Флаги внизу: нажал — язык сменился сразу, без перезапуска.
    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("language").uppercased())
                .font(.caption).bold().foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach([Lang.en, .uk, .ru]) { l in
                    Button { loc.lang = l } label: {
                        Text(l.flag)
                            .font(.system(size: l == .ru ? 22 : 26))
                            .frame(width: 56, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(loc.lang == l ? Color.sticker.opacity(0.18) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(loc.lang == l ? Color.sticker : Color.secondary.opacity(0.3),
                                            lineWidth: loc.lang == l ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    // MARK: - мелочи интерфейса

    private func mm(_ v: CGFloat) -> String { String(format: "%.0f mm", v) }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption).bold().foregroundStyle(.secondary)
            c()
        }
    }

    private func labeled(_ a: String, _ b: String) -> some View {
        HStack { Text(a).font(.callout); Spacer(); Text(b).font(.callout).monospacedDigit() }
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.caption2).foregroundStyle(.secondary)
    }

    /// Джойстик: стрелки понятно куда жать, в центре — крупные значения обеих осей.
    private var nudgePad: some View {
        VStack(spacing: 6) {
            arrow("chevron.up") { move(dy: -0.5) }
            HStack(spacing: 6) {
                arrow("chevron.left") { move(dx: -0.5) }
                Button {
                    layout.shiftXMM = 0; layout.shiftYMM = 0
                } label: {
                    VStack(spacing: 1) {
                        Text(String(format: "%+.1f", layout.shiftXMM))
                            .foregroundStyle(layout.shiftXMM == 0 ? Color.secondary : Color.sticker)
                        Text(String(format: "%+.1f", layout.shiftYMM))
                            .foregroundStyle(layout.shiftYMM == 0 ? Color.secondary : Color.sticker)
                    }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 74, height: 50)
                }
                .buttonStyle(.bordered)
                .help(loc("resetHelp"))
                arrow("chevron.right") { move(dx: 0.5) }
            }
            arrow("chevron.down") { move(dy: 0.5) }
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold))
                .frame(width: 74, height: 34)
        }
        .buttonStyle(.bordered)
    }

    private func move(dx: CGFloat = 0, dy: CGFloat = 0) {
        let k: CGFloat = flipPreview ? -1 : 1
        layout.shiftXMM += dx * k
        layout.shiftYMM += dy * k
    }

    // MARK: - действия

    private func openFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .bmp, .webP]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let url = p.url { set(url) }
    }

    private func load(from providers: [NSItemProvider]) {
        guard let pr = providers.first else { return }
        if pr.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            pr.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                var url: URL?
                if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                if let url { DispatchQueue.main.async { set(url) } }
            }
            return
        }
        pr.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dropped.png")
            try? data.write(to: tmp)
            DispatchQueue.main.async { set(tmp) }
        }
    }

    private func set(_ url: URL) {
        guard let img = Renderer.load(url: url) else {
            error = "\(loc("cantRead")): \(url.lastPathComponent)"; return
        }
        source = img
        fileName = url.lastPathComponent
        layout.zoom = 1; layout.panX = 0; layout.panY = 0
    }

    private func printNow(testOnly: Bool = false) {
        var L = layout
        if testOnly { L.copies = 1 }
        guard let img = Renderer.compose(image: testOnly ? nil : source, layout: L) else { return }
        let r = Renderer.raster(img, layout: L)
        Task {
            do { try await printer.print(raster: r.data, lines: r.lines, layout: L) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func savePNG() {
        guard let c = composed,
              let img = showAsPrinted ? Renderer.preview1bit(c, layout: layout) : c else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [.png]
        p.nameFieldStringValue = "sticker.png"
        guard p.runModal() == .OK, let url = p.url else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        rep.size = NSSize(width: img.width, height: img.height)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
