import SwiftUI
import UIKit

enum Screen { case code, name, chat }

struct Entry: Identifiable {
    enum Kind {
        case text(String)
        case sticker(String)
        case image(UIImage)
    }
    let id = UUID()
    let time = Date()
    let user: String
    let color: Color
    let kind: Kind
}

final class ChatModel: ObservableObject {
    @Published var screen: Screen = .code
    @Published var code = ""
    @Published var name = ""
    @Published var slots: [Entry] = []      // immer nur die letzten 2
    @Published var status = ""
    @Published var log: [String] = []       // ganzer Verlauf (nur für Admin)
    @Published var showAdmin = false

    private(set) var room = ""
    private(set) var user = ""

    let myId: String = String((0..<10).map { _ in "0123456789abcdef".randomElement()! })

    private let mqtt = MqttClient()
    private var online: [String: (name: String, seen: Date)] = [:]
    private var netUp = false
    private var flashWork: DispatchWorkItem?
    private var heartbeat: Timer?

    static let maxImage = 200 * 1024
    static let topicPrefix = "retrochat-7k3q/v1/room/"

    init() {
        mqtt.onMessage = { [weak self] data in self?.onPacket(data) }
        mqtt.onStatus = { [weak self] up in
            guard let self = self else { return }
            self.netUp = up
            self.updateStatus()
            if up { self.sendPing() }
        }
    }

    var title: String { screen == .chat ? "CHAT - #\(room)" : "CHAT" }

    // MARK: - Bildschirme

    func codeChanged(_ value: String) {
        let digits = String(value.filter { $0 >= "0" && $0 <= "9" }.prefix(4))
        if digits != value { code = digits; return }
        if digits.count == 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if self.code.count == 4 && self.screen == .code {
                    self.room = self.code
                    self.screen = .name
                }
            }
        }
    }

    func join() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { Sound.shared.beep(); return }
        user = String(n.prefix(16))
        room = code
        slots = []
        log = []
        online = [myId: (user, Date())]
        screen = .chat
        addLog("\(user) ist dem Raum beigetreten (du)")
        connect()
        updateStatus()
    }

    func back() {
        switch screen {
        case .name:
            code = ""
            screen = .code
        case .chat:
            leave()
        case .code:
            break
        }
    }

    private func leave() {
        mqtt.stop(last: pkt("L"))
        heartbeat?.invalidate()
        heartbeat = nil
        slots = []
        online = [:]
        netUp = false
        status = ""
        code = ""
        screen = .code
    }

    private func connect() {
        mqtt.start(topic: ChatModel.topicPrefix + room, clientId: "rc" + myId, will: pkt("L"), hello: pkt("J"))
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// App geht in den Hintergrund / kommt zurück
    func scene(_ phase: ScenePhase) {
        guard screen == .chat else { return }
        if phase == .background {
            mqtt.stop(last: pkt("L"))
            heartbeat?.invalidate()
            heartbeat = nil
            netUp = false
            online = [myId: (user, Date())]
        } else if phase == .active && !mqtt.isRunning {
            connect()
            updateStatus()
        }
    }

    // MARK: - Senden

    func handleInput(_ text: String) {
        // Admin-Einstellungen (wird nicht gesendet)
        if text.lowercased() == "admin123" { showAdmin = true; return }

        // Lautstärke: /lautstärke50, /lautstärke 50, /lautstaerke(50), /volume 50
        if let g = match(#"^/(lautst(ä|ae|a)rke|volume|vol)\s*\(?\s*(\d{1,3})\s*%?\s*\)?$"#, text) {
            let v = Int(g[3]) ?? 0
            if (1...100).contains(v) {
                Sound.shared.volume = v
                flash("Lautstärke: \(v)%")
                Sound.shared.beep()
            } else {
                flash("Lautstärke geht von 1 bis 100")
            }
            return
        }

        // Geräusch auf allen anderen Geräten: /sound1 ... /sound5
        if let g = match(#"^/sound\s*\(?\s*(\d+)\s*\)?$"#, text) {
            guard let n = Int(g[1]), (1...5).contains(n) else { flash("Sounds gibt es von 1 bis 5"); return }
            if send("S", String(n)) {
                add(Entry(user: user, color: myColor, kind: .text("♪ Sound \(n)")), "[Sound \(n)]")
            }
            return
        }

        // Vorlesen auf allen anderen Geräten: /tts Hallo
        if let g = match(#"^/tts\s+([\s\S]+)$"#, text) {
            let t = String(g[1].trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            if send("T", t) {
                add(Entry(user: user, color: myColor, kind: .text("» " + t)), "[TTS] " + t)
            }
            return
        }

        let t = String(text.prefix(300))
        if send("M", t) {
            add(Entry(user: user, color: myColor, kind: .text(t)), t)
        }
    }

    func sendSticker(_ name: String) {
        if send("K", name) {
            add(Entry(user: user, color: myColor, kind: .sticker(name)), "[Sticker: \(name)]")
        }
    }

    func sendImageData(_ raw: Data) {
        var bytes = raw
        let isGif = raw.starts(with: [UInt8]("GIF8".utf8))
        if !(isGif && raw.count <= ChatModel.maxImage) {
            guard let img = UIImage(data: raw), let small = ChatModel.shrink(img) else {
                flash("Bild konnte nicht gelesen werden")
                return
            }
            bytes = small
            if isGif { flash("GIF war zu groß (max 200 KB) - als Standbild gesendet") }
        }
        guard let shown = Gif.image(from: bytes) else { flash("Bild konnte nicht gelesen werden"); return }
        if send("I", bytes.base64EncodedString()) {
            add(Entry(user: user, color: myColor, kind: .image(shown)), "[GIF/Bild]")
        }
    }

    private static func shrink(_ img: UIImage) -> Data? {
        let w = img.size.width * img.scale
        let h = img.size.height * img.scale
        guard w >= 1, h >= 1 else { return nil }
        let sc = min(1.0, 360.0 / w, 360.0 / h)
        let size = CGSize(width: max(1, (w * sc).rounded(.down)), height: max(1, (h * sc).rounded(.down)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let out = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        if let png = out.pngData(), png.count <= maxImage { return png }
        return out.jpegData(compressionQuality: 0.75)
    }

    @discardableResult
    private func send(_ type: String, _ data: String) -> Bool {
        let ok = mqtt.publish(pkt(type, data))
        if !ok { flash("Nicht verbunden - Nachricht nicht gesendet") }
        return ok
    }

    private func sendPing() {
        if screen == .chat && mqtt.connected { mqtt.publish(pkt("P")) }
    }

    private func pkt(_ type: String, _ data: String = "") -> Data {
        Packet(type: type, id: myId, user: user, data: data).encode()
    }

    // MARK: - Empfangen

    private func onPacket(_ raw: Data) {
        guard screen == .chat, let p = Packet.decode(raw), p.id != myId else { return }
        let color = ChatModel.colorFor(p.id)
        let wasOnline = online[p.id] != nil
        if p.type != "L" { online[p.id] = (p.user, Date()) }

        switch p.type {
        case "M":
            let t = String(p.data.prefix(300))
            add(Entry(user: p.user, color: color, kind: .text(t)), t)
            Sound.shared.beep()
            buzz()
        case "T":
            let t = String(p.data.prefix(200))
            add(Entry(user: p.user, color: color, kind: .text("» " + t)), "[TTS] " + t)
            Sound.shared.speak(t)
            buzz()
        case "S":
            if let n = Int(p.data), (1...5).contains(n) {
                add(Entry(user: p.user, color: color, kind: .text("♪ Sound \(n)")), "[Sound \(n)]")
                Sound.shared.effect(n)
            }
        case "K":
            if Stickers.exists(p.data) {
                add(Entry(user: p.user, color: color, kind: .sticker(p.data)), "[Sticker: \(p.data)]")
                Sound.shared.beep()
                buzz()
            }
        case "I":
            if p.data.utf8.count <= ChatModel.maxImage * 2,
               let d = Data(base64Encoded: p.data),
               let img = Gif.image(from: d) {
                add(Entry(user: p.user, color: color, kind: .image(img)), "[GIF/Bild]")
                Sound.shared.beep()
                buzz()
            }
        case "J":
            addLog("\(p.user) ist beigetreten")
            flash("\(p.user) ist beigetreten")
            Sound.shared.joinTone()
            sendPing()   // damit der Neue weiß, wer schon da ist
        case "L":
            if online.removeValue(forKey: p.id) != nil {
                addLog("\(p.user) hat den Raum verlassen")
                flash("\(p.user) ist weg")
            }
        default:
            break
        }
        if !wasOnline || p.type == "L" { updateStatus() }
    }

    private func add(_ e: Entry, _ logText: String) {
        slots.append(e)
        while slots.count > 2 { slots.removeFirst() }
        addLog("\(e.user): \(logText)", e.time)
    }

    private func buzz() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Status

    func flash(_ msg: String) {
        status = msg
        flashWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            self?.flashWork = nil
            self?.updateStatus()
        }
        flashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: w)
    }

    private func tick() {
        sendPing()
        let cutoff = Date().addingTimeInterval(-50)
        for (k, v) in online where k != myId && v.seen < cutoff {
            addLog("\(v.name) hat den Raum verlassen")
            online[k] = nil
        }
        updateStatus()
    }

    private func updateStatus() {
        guard screen == .chat, flashWork == nil else { return }
        status = "#\(room)   " + (netUp ? "\(online.count) online" : "verbinde...")
    }

    // MARK: - Verlauf / Admin

    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return f
    }()

    private func addLog(_ line: String, _ when: Date = Date()) {
        log.append("[\(ChatModel.stampFormat.string(from: when))] \(line)")
    }

    func exportFile() -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("chat_\(room)_\(f.string(from: Date())).txt")
        var text = "\u{FEFF}CHAT - Raum #\(room)\r\n"
        text += "Exportiert am \(ChatModel.stampFormat.string(from: Date()))\r\n"
        text += String(repeating: "-", count: 50) + "\r\n"
        text += log.joined(separator: "\r\n") + "\r\n"
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Hilfen

    private var myColor: Color { ChatModel.colorFor(myId) }

    private static let colors: [Color] = [
        rgb(0, 0, 128), rgb(128, 0, 0), rgb(0, 128, 0), rgb(128, 0, 128),
        rgb(0, 128, 128), rgb(160, 80, 0), rgb(0, 0, 255), rgb(200, 0, 100),
    ]

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    /// Gleiche Farbe pro Person wie in Chat.exe / chat.html
    static func colorFor(_ id: String) -> Color {
        var h: Int32 = 0
        for c in id.utf16 { h = h &* 31 &+ Int32(c) }
        return colors[Int(h & 0x7fffffff) % colors.count]
    }

    private func match(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}
