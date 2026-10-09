import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Windows-95-Farben und Rahmen

enum Win {
    static let face = Color(red: 192 / 255, green: 192 / 255, blue: 192 / 255)
    static let light = Color(red: 223 / 255, green: 223 / 255, blue: 223 / 255)
    static let shadow = Color(red: 128 / 255, green: 128 / 255, blue: 128 / 255)
    static let navy = Color(red: 0, green: 0, blue: 128 / 255)
    static let titleEnd = Color(red: 16 / 255, green: 132 / 255, blue: 208 / 255)
    static let desk = Color(red: 0, green: 128 / 255, blue: 128 / 255)

    static func ui(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Verdana-Bold" : "Verdana", size: size)
    }

    static func mono(_ size: CGFloat) -> Font {
        .custom("Courier New", size: size)
    }
}

/// Klassischer 3D-Rahmen: erhaben (Fenster, Knöpfe) oder eingedrückt (Felder)
struct Bevel: View {
    var sunken = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            func edge(_ inset: CGFloat, _ topLeft: Color, _ bottomRight: Color) {
                var a = Path()
                a.move(to: CGPoint(x: inset, y: h - inset))
                a.addLine(to: CGPoint(x: inset, y: inset))
                a.addLine(to: CGPoint(x: w - inset, y: inset))
                ctx.stroke(a, with: .color(topLeft), lineWidth: 1)
                var b = Path()
                b.move(to: CGPoint(x: w - inset, y: inset))
                b.addLine(to: CGPoint(x: w - inset, y: h - inset))
                b.addLine(to: CGPoint(x: inset, y: h - inset))
                ctx.stroke(b, with: .color(bottomRight), lineWidth: 1)
            }
            if sunken {
                edge(0.5, Win.shadow, .white)
                edge(1.5, .black, Win.light)
            } else {
                edge(0.5, Win.light, .black)
                edge(1.5, .white, Win.shadow)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func bevel(sunken: Bool = false) -> some View {
        overlay(Bevel(sunken: sunken))
    }

    func retroField() -> some View {
        textFieldStyle(.plain)
            .foregroundColor(.black)
            .tint(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(Color.white)
            .bevel(sunken: true)
    }
}

struct RetroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.black)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
            .background(Win.face)
            .bevel(sunken: configuration.isPressed)
    }
}

/// Fenster mit blauer Titelleiste
struct RetroWindow<Content: View>: View {
    let title: String
    let onClose: (() -> Void)?
    let content: Content

    init(title: String, onClose: (() -> Void)?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Win.ui(14, bold: true))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let close = onClose {
                    Button(action: close) {
                        Text("×")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 26, height: 22)
                    }
                    .buttonStyle(RetroButtonStyle())
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(LinearGradient(colors: [Win.navy, Win.titleEnd], startPoint: .leading, endPoint: .trailing))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 6)
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
        }
        .padding(4)
        .background(Win.face)
        .bevel()
    }
}

// MARK: - Hauptansicht

struct RootView: View {
    @StateObject private var m = ChatModel()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ZStack {
            Win.desk.ignoresSafeArea()
            RetroWindow(title: m.title, onClose: m.screen == .code ? nil : { m.back() }) {
                switch m.screen {
                case .code: CodeScreen(m: m)
                case .name: NameScreen(m: m)
                case .chat: ChatScreen(m: m)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .preferredColorScheme(.light)
        .onChange(of: phase) { newPhase in m.scene(newPhase) }
        .sheet(isPresented: $m.showAdmin) { AdminView(m: m) }
    }
}

// MARK: - 1. Nummer

struct PixelLogo: View {
    private static let glyphs: [Character: [String]] = [
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    ]

    var body: some View {
        Canvas { ctx, size in
            let letters = Array("CHAT")
            let px = max(2, floor(min(size.width / 27, size.height / 7.5)))
            let ox = floor((size.width - 26 * px) / 2)
            let oy = floor((size.height - 7 * px) / 2)

            func each(_ draw: (CGRect) -> Void) {
                for (li, letter) in letters.enumerated() {
                    guard let rows = PixelLogo.glyphs[letter] else { continue }
                    for (y, row) in rows.enumerated() {
                        for (x, ch) in row.enumerated() where ch == "#" {
                            let cx = ox + CGFloat(li * 7 + x) * px
                            let cy = oy + CGFloat(y) * px
                            draw(CGRect(x: cx, y: cy, width: px, height: px))
                        }
                    }
                }
            }

            let sh = floor(px / 3) + 1
            each { r in ctx.fill(Path(r.offsetBy(dx: sh, dy: sh)), with: .color(Win.shadow)) }
            each { r in ctx.fill(Path(r), with: .color(Win.navy)) }
            each { r in
                ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: max(1, floor(px / 4)))),
                         with: .color(Win.titleEnd))
            }
        }
    }
}

struct CodeScreen: View {
    @ObservedObject var m: ChatModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            PixelLogo()
                .frame(height: 96)
                .padding(.horizontal, 16)
            TextField("", text: $m.code)
                .keyboardType(.numberPad)
                .font(Win.mono(32).bold())
                .multilineTextAlignment(.center)
                .focused($focused)
                .retroField()
                .frame(width: 170)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
        .onChange(of: m.code) { value in m.codeChanged(value) }
    }
}

// MARK: - 2. Username

struct NameScreen: View {
    @ObservedObject var m: ChatModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("username:")
                    .font(Win.ui(15))
                    .foregroundColor(.black)
                TextField("", text: $m.name)
                    .font(Win.ui(18))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { m.join() }
                    .retroField()
            }
            .frame(width: 260)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
        .onChange(of: m.name) { value in
            if value.count > 16 { m.name = String(value.prefix(16)) }
        }
    }
}

// MARK: - 3. Chat

struct ChatScreen: View {
    @ObservedObject var m: ChatModel
    @State private var text = ""
    @State private var showStickers = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                SlotView(entry: m.slots.count == 2 ? m.slots[0] : nil)
                Rectangle()
                    .fill(Color(white: 0.82))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                SlotView(entry: m.slots.last)
            }
            .padding(3)
            .background(Color.white)
            .bevel(sunken: true)

            HStack(spacing: 4) {
                TextField("", text: $text)
                    .font(Win.ui(16))
                    .submitLabel(.send)
                    .focused($focused)
                    .onSubmit(send)
                    .retroField()
                Button {
                    showStickers = true
                } label: {
                    Text("☺\u{FE0E}")
                        .font(.system(size: 24))
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(RetroButtonStyle())
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(m.status)
                    .font(Win.ui(12))
                    .foregroundColor(.black)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 22)
            .bevel(sunken: true)
        }
        .sheet(isPresented: $showStickers) {
            StickerSheet(m: m)
                .presentationDetents([.height(340)])
        }
        .onAppear { focused = true }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        if !t.isEmpty { m.handleInput(t) }
        DispatchQueue.main.async { focused = true }
    }
}

struct SlotView: View {
    let entry: Entry?

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let e = entry {
                HStack {
                    Text("<\(e.user)>")
                        .font(Win.ui(13, bold: true))
                        .foregroundColor(e.color)
                        .lineLimit(1)
                    Spacer()
                    Text(SlotView.timeFormat.string(from: e.time))
                        .font(Win.ui(12))
                        .foregroundColor(Win.shadow)
                }
                switch e.kind {
                case .text(let t):
                    Text(t)
                        .font(Win.ui(17))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .sticker(let name):
                    Image(uiImage: Stickers.image(name))
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 84, height: 84)
                case .image(let img):
                    GifView(image: img)
                        .aspectRatio(img.size.width / max(1, img.size.height), contentMode: .fit)
                        .frame(maxWidth: max(40, img.size.width * 2), alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

/// Zeigt Bilder an – animierte GIFs laufen
struct GifView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        if v.image !== image {
            v.image = image
            v.startAnimating()
        }
    }
}

// MARK: - Sticker / GIF auswählen

struct StickerSheet: View {
    @ObservedObject var m: ChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?
    @State private var importing = false

    private let columns = Array(repeating: GridItem(.fixed(70), spacing: 6), count: 3)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Stickers.names, id: \.self) { name in
                    Button {
                        m.sendSticker(name)
                        dismiss()
                    } label: {
                        Image(uiImage: Stickers.image(name))
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 42, height: 42)
                            .frame(width: 70, height: 58)
                    }
                    .buttonStyle(RetroButtonStyle())
                }
            }
            HStack(spacing: 6) {
                PhotosPicker(selection: $pick, matching: .images) {
                    Text("Fotos...")
                        .font(Win.ui(13))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(RetroButtonStyle())
                Button {
                    importing = true
                } label: {
                    Text("Dateien...")
                        .font(Win.ui(13))
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(RetroButtonStyle())
            }
            .frame(width: 70 * 3 + 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Win.face.ignoresSafeArea())
        .onChange(of: pick) { item in
            guard let item = item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data = data {
                        m.sendImageData(data)
                    } else {
                        m.flash("Bild konnte nicht geladen werden")
                    }
                    dismiss()
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.gif, .image]) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    m.sendImageData(data)
                }
            }
            dismiss()
        }
    }
}

// MARK: - Admin

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct AdminView: View {
    @ObservedObject var m: ChatModel
    @Environment(\.dismiss) private var dismiss
    @State private var share: ShareItem?

    var body: some View {
        ZStack {
            Win.desk.ignoresSafeArea()
            RetroWindow(title: "Admin - Raum #\(m.room)", onClose: { dismiss() }) {
                VStack(spacing: 6) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                Text(m.log.joined(separator: "\n"))
                                    .font(Win.mono(13))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(8)
                                Color.clear.frame(height: 1).id("end")
                            }
                        }
                        .onAppear { proxy.scrollTo("end") }
                        .onChange(of: m.log.count) { _ in proxy.scrollTo("end") }
                    }
                    .background(Color.white)
                    .bevel(sunken: true)

                    HStack(spacing: 8) {
                        Spacer()
                        Button {
                            if let url = m.exportFile() { share = ShareItem(url: url) }
                        } label: {
                            Text("Als .txt exportieren")
                                .font(Win.ui(13))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                        }
                        .buttonStyle(RetroButtonStyle())
                        Button {
                            dismiss()
                        } label: {
                            Text("Schließen")
                                .font(Win.ui(13))
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                        }
                        .buttonStyle(RetroButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .preferredColorScheme(.light)
        .sheet(item: $share) { item in
            ActivityView(items: [item.url])
        }
    }
}
