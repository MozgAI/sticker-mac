import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Фирменный розовый — тот же, что на значке приложения.
extension Color {
    static let sticker = Color(red: 0.925, green: 0.118, blue: 0.471)
}

struct ContentView: View {
    @StateObject private var printer = Printer()
    @State private var layout = Layout()
    @State private var source: CGImage?
    @State private var fileName = ""
    @State private var showAsPrinted = true
    @State private var dragStart: CGSize?
    /// Показывать превью перевёрнутым — как наклейка выезжает из принтера.
    @State private var flipPreview = false
    @State private var error: String?
    @ObservedObject private var inbox = Inbox.shared

    /// Итоговая картинка: то, что уйдёт в принтер.
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
            controls.frame(width: 300)
        }
        .frame(minWidth: 900, minHeight: 620)
        .onReceive(inbox.$url.compactMap { $0 }) { set($0) }
        .alert("Не получилось", isPresented: .constant(error != nil)) {
            Button("Ясно") { error = nil }
        } message: { Text(error ?? "") }
    }

    // MARK: - холст

    private var canvas: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle(isOn: $flipPreview) {
                    Label("Перевернуть превью", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .toggleStyle(.button)
                .controlSize(.large)
                .help("Показать так, как наклейка выезжает из принтера")
                if flipPreview {
                    Text("вид как из принтера").font(.caption).foregroundStyle(.secondary)
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
                        Text("Перетащи сюда картинку").font(.title3)
                        Text("зелёное — обрежется, в круге — напечатается")
                            .font(.caption).foregroundStyle(.secondary)
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

            Text(source == nil ? "Файл не выбран"
                 : "\(fileName)  ·  тяни мышкой, чтобы двигать  ·  \(Int(layout.zoom * 100))%")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - панель

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                group("Печать") {
                    HStack(spacing: 10) {
                        Button {
                            printNow()
                        } label: {
                            Label(printer.busy ? "Печатаю…" : "ПЕЧАТЬ", systemImage: "printer.fill")
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
                        Text(printer.connected ? "\(printer.connectedName) · готов" : printer.status)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack {
                        Button("Пробный круг") { printNow(testOnly: true) }
                            .disabled(!printer.connected || printer.busy)
                        Button("Сохранить PNG") { savePNG() }.disabled(composed == nil)
                    }
                }
                Divider()


                group("Картинка") {
                    HStack {
                        Button("Открыть…") { openFile() }
                        Button("По центру") { layout.panX = 0; layout.panY = 0; layout.zoom = 1 }
                            .disabled(source == nil)
                    }
                    labeled("Масштаб", String(format: "%.0f%%", layout.zoom * 100))
                    Slider(value: $layout.zoom, in: 0.4...4)
                }

                group("Размеры") {
                    labeled("Диаметр рисунка", String(format: "%.0f мм", layout.printMM))
                    Slider(value: $layout.printMM, in: 10...48, step: 1)
                    Text("Насколько крупно печатать. Должен влезать в наклейку.")
                        .font(.caption2).foregroundStyle(.secondary)

                    labeled("Шаг наклейки", String(format: "%.0f мм", layout.labelMM))
                    Slider(value: $layout.labelMM, in: 15...80, step: 1)
                    Text("Сколько ленты протянуть — высота одной наклейки с зазором. Белый пунктир в превью.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                group("Выравнивание") {
                    nudgePad
                    Text(flipPreview
                         ? "Стрелки двигают так, как ты видишь на перевёрнутом превью."
                         : "Если печать съезжает с вырубленного круга — двигай стрелками. Сверху в центре — сдвиг вбок, снизу — по ленте.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                group("Ориентация на ленте") {
                    Picker("", selection: Binding(
                        get: { layout.mirror ? (layout.flip180 ? 3 : 1) : (layout.flip180 ? 2 : 0) },
                        set: { v in layout.mirror = (v == 1 || v == 3)
                                   layout.flip180 = (v == 2 || v == 3) })) {
                        Text("Как есть").tag(0)
                        Text("Зеркало").tag(1)
                        Text("180°").tag(2)
                        Text("Оба").tag(3)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text("Если вышло зеркально или вверх ногами — переключи здесь. Превью не меняется: там всегда как ляжет в руку.")
                        .font(.caption2).foregroundStyle(.secondary)

                    labeled("Качество", layout.speed <= 2 ? "максимум" : "быстро")
                    Picker("", selection: $layout.speed) {
                        Text("Максимум").tag(1)
                        Text("Средне").tag(3)
                        Text("Быстро").tag(5)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }

                group("Как печатать") {
                    Picker("", selection: $layout.dither) {
                        Text("Рисунок").tag(false)
                        Text("Фото").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(layout.dither
                         ? "Полутона точками — для фотографий и градиентов."
                         : "Чисто чёрное и белое — для вензелей, надписей и лого.")
                        .font(.caption2).foregroundStyle(.secondary)

                    if !layout.dither {
                        labeled("Порог чёрного", "\(layout.threshold)")
                        Slider(value: Binding(get: { Double(layout.threshold) },
                                              set: { layout.threshold = Int($0) }),
                               in: 60...240, step: 5)
                        Text("Ниже — только самое тёмное. Выше — тонкие линии не пропадут.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    labeled("Чистка фона", String(format: "%.0f%%", layout.cleanBG * 100))
                    Slider(value: $layout.cleanBG, in: 0...0.4)
                    Text("Убирает крапинки на белом от сжатия JPEG.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Toggle("Негатив", isOn: $layout.invert)
                    Toggle("Показывать как напечатается", isOn: $showAsPrinted)
                    labeled("Яркость", String(format: "%+.2f", layout.brightness))
                    Slider(value: $layout.brightness, in: -0.5...0.5)
                    labeled("Контраст", String(format: "%.2f", layout.contrast))
                    Slider(value: $layout.contrast, in: 0.5...2.5)
                    labeled("Нагрев", "\(layout.density)")
                    Slider(value: Binding(get: { Double(layout.density) },
                                          set: { layout.density = Int($0) }), in: 1...15, step: 1)
                }

                Divider()
                group("Принтер") {
                    HStack {
                        TextField("часть имени принтера", text: Binding(
                            get: { printer.nameFilter },
                            set: { printer.setFilter($0) }))
                            .textFieldStyle(.roundedBorder)
                        Button("Искать") { printer.startScan() }
                    }
                    Text("Пусто — ищу любой принтер этикеток. Впиши кусок имени своего, если рядом несколько.")
                        .font(.caption2).foregroundStyle(.secondary)

                    if printer.connected {
                        HStack {
                            if printer.pinnedID == nil {
                                Button("Запомнить этот принтер") { printer.pinCurrent() }
                            } else {
                                Label("Закреплён", systemImage: "pin.fill").font(.caption)
                                Spacer()
                                Button("Забыть") { printer.unpin() }.font(.caption)
                            }
                        }
                    }

                    if !printer.connected {
                        if !printer.devices.isEmpty {
                            Text("Что в эфире — нажми свой принтер:")
                                .font(.caption2).foregroundStyle(.secondary)
                            ForEach(printer.devices.prefix(8)) { d in
                                Button {
                                    printer.connect(to: d)
                                } label: {
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
                        Button("Искать заново") { printer.startScan() }.font(.caption)
                    } else {
                        HStack {
                            Text(printer.connectedName).font(.caption).bold()
                            Spacer()
                            Button("Отключить") { printer.disconnect() }.font(.caption)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption).bold().foregroundStyle(.secondary)
            c()
        }
    }

    private func labeled(_ a: String, _ b: String) -> some View {
        HStack { Text(a).font(.callout); Spacer(); Text(b).font(.callout).monospacedDigit() }
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
                .help("Верх — вбок, низ — по ленте. Нажми, чтобы обнулить")
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

    /// Сдвиг в миллиметрах. При перевёрнутом превью — в ту же сторону, куда смотрит глаз.
    private func move(dx: CGFloat = 0, dy: CGFloat = 0) {
        let k: CGFloat = flipPreview ? -1 : 1
        layout.shiftXMM += dx * k
        layout.shiftYMM += dy * k
    }

    private func stepperMM(_ title: String, _ v: Binding<CGFloat>) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(String(format: "%+.1f", v.wrappedValue)).monospacedDigit().frame(width: 44)
            Stepper("") { v.wrappedValue += 0.5 } onDecrement: { v.wrappedValue -= 0.5 }
                .labelsHidden()
        }
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
        // картинку могли бросить прямо из браузера — сохраняем во временный файл
        pr.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("dropped.png")
            try? data.write(to: tmp)
            DispatchQueue.main.async { set(tmp) }
        }
    }

    private func set(_ url: URL) {
        guard let img = Renderer.load(url: url) else { error = "Не читается: \(url.lastPathComponent)"; return }
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
        p.nameFieldStringValue = "наклейка.png"
        guard p.runModal() == .OK, let url = p.url else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        rep.size = NSSize(width: img.width, height: img.height)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
