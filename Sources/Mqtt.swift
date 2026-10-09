import Foundation

/// Minimaler MQTT-3.1.1-Client über WebSocket (QoS 0).
/// Gleicher Server und gleiches Thema wie Chat.exe und chat.html, damit alle im selben Raum landen.
final class MqttClient: NSObject, URLSessionWebSocketDelegate {
    static let url = URL(string: "wss://broker.emqx.io:8084/mqtt")!

    var onMessage: ((Data) -> Void)?
    var onStatus: ((Bool) -> Void)?

    private(set) var connected = false
    var isRunning: Bool { running }

    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var buf: [UInt8] = []
    private var running = false
    private var topic = ""
    private var clientId = ""
    private var will = Data()
    private var hello: Data?
    private var pingTimer: Timer?
    private var retryWork: DispatchWorkItem?

    override init() {
        super.init()
        // Alle Rückmeldungen kommen auf dem Haupt-Thread an.
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    func start(topic: String, clientId: String, will: Data, hello: Data?) {
        self.topic = topic
        self.clientId = clientId
        self.will = will
        self.hello = hello
        running = true
        open()
    }

    func stop(last: Data?) {
        if let last = last { publish(last) }
        send(0xE0, [])
        running = false
        retryWork?.cancel()
        pingTimer?.invalidate()
        pingTimer = nil
        connected = false
        let old = task
        task = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            old?.cancel(with: .normalClosure, reason: nil)
        }
    }

    // MARK: - Verbindung

    private func open() {
        guard running else { return }
        buf.removeAll()
        let t = session.webSocketTask(with: MqttClient.url, protocols: ["mqtt"])
        t.maximumMessageSize = 4 * 1024 * 1024
        task = t
        t.resume()
        receive(t)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) {
        guard webSocketTask === task else { return }
        var b: [UInt8] = []
        MqttClient.str(&b, "MQTT")
        b.append(contentsOf: [4, 0x02 | 0x04, 0, 30])   // Version 3.1.1, Clean Session + Will, Keep-Alive 30 s
        MqttClient.str(&b, clientId)
        MqttClient.str(&b, topic)
        b.append(UInt8((will.count >> 8) & 0xFF))
        b.append(UInt8(will.count & 0xFF))
        b.append(contentsOf: [UInt8](will))
        send(0x10, b)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        closed(webSocketTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let ws = task as? URLSessionWebSocketTask { closed(ws) }
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.task === t else { return }
                switch result {
                case .success(let msg):
                    switch msg {
                    case .data(let d): self.feed([UInt8](d))
                    case .string(let s): self.feed([UInt8](s.utf8))
                    @unknown default: break
                    }
                    self.receive(t)
                case .failure:
                    self.closed(t)
                }
            }
        }
    }

    private func closed(_ t: URLSessionWebSocketTask) {
        guard t === task else { return }
        task = nil
        t.cancel()
        pingTimer?.invalidate()
        pingTimer = nil
        let was = connected
        connected = false
        if was { onStatus?(false) }
        guard running else { return }
        let w = DispatchWorkItem { [weak self] in self?.open() }
        retryWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }

    // MARK: - Pakete

    private func feed(_ chunk: [UInt8]) {
        buf.append(contentsOf: chunk)
        while buf.count >= 2 {
            var len = 0
            var mult = 1
            var i = 1
            var complete = false
            while i < buf.count && i <= 4 {
                let d = Int(buf[i])
                i += 1
                len += (d & 127) * mult
                mult *= 128
                if d & 128 == 0 { complete = true; break }
            }
            if !complete {
                if i > 4 { buf.removeAll() }   // kaputtes Paket
                return
            }
            guard buf.count >= i + len else { return }
            let header = buf[0]
            let body = Array(buf[i ..< i + len])
            buf.removeFirst(i + len)
            packet(header, body)
        }
    }

    private func packet(_ h: UInt8, _ body: [UInt8]) {
        let type = h >> 4
        if type == 2 {                                    // CONNACK
            guard body.count >= 2, body[1] == 0 else { task?.cancel(); return }
            var b: [UInt8] = [0, 1]
            MqttClient.str(&b, topic)
            b.append(0)
            send(0x82, b)                                 // SUBSCRIBE
            connected = true
            pingTimer?.invalidate()
            pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                _ = self?.send(0xC0, [])
            }
            onStatus?(true)
            if let h = hello {
                publish(h)
                hello = nil                               // "beigetreten" nur beim ersten Verbinden
            }
        } else if type == 3 {                             // PUBLISH
            guard body.count >= 2 else { return }
            let qos = (h >> 1) & 3
            let tl = (Int(body[0]) << 8) | Int(body[1])
            let start = 2 + tl + (qos > 0 ? 2 : 0)
            guard start <= body.count else { return }
            onMessage?(Data(body[start...]))
        }
    }

    @discardableResult
    func publish(_ payload: Data) -> Bool {
        guard connected else { return false }
        var b: [UInt8] = []
        MqttClient.str(&b, topic)
        b.append(contentsOf: [UInt8](payload))
        return send(0x30, b)
    }

    @discardableResult
    private func send(_ h: UInt8, _ body: [UInt8]) -> Bool {
        guard let t = task else { return false }
        var out: [UInt8] = [h]
        var len = body.count
        repeat {
            var d = UInt8(len % 128)
            len /= 128
            if len > 0 { d |= 128 }
            out.append(d)
        } while len > 0
        out.append(contentsOf: body)
        t.send(.data(Data(out))) { _ in }
        return true
    }

    private static func str(_ b: inout [UInt8], _ s: String) {
        let e = [UInt8](s.utf8)
        b.append(UInt8((e.count >> 8) & 0xFF))
        b.append(UInt8(e.count & 0xFF))
        b.append(contentsOf: e)
    }
}

/// Nachrichtenformat im Chatraum (identisch zu Chat.exe / chat.html)
/// Typ: M=Text, T=TTS, S=Sound, K=Sticker, I=Bild/GIF, J=Join, P=Ping, L=Leave
struct Packet {
    var type: String
    var id: String
    var user: String
    var data: String

    func encode() -> Data {
        let u = user.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return Data("RC1\n\(type)\n\(id)\n\(u)\n\(data)".utf8)
    }

    static func decode(_ raw: Data) -> Packet? {
        guard let s = String(data: raw, encoding: .utf8) else { return nil }
        let parts = s.split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: false).map { String($0) }
        guard parts.count >= 4, parts[0] == "RC1", parts[1].count == 1,
              !parts[2].isEmpty, parts[2].count <= 32 else { return nil }
        var user = String(parts[3].prefix(24))
        if user.trimmingCharacters(in: .whitespaces).isEmpty { user = "???" }
        return Packet(type: parts[1], id: parts[2], user: user, data: parts.count > 4 ? parts[4] : "")
    }
}
