import AVFoundation

/// Alle Geräusche werden im Programm erzeugt – dieselben wie in Chat.exe und chat.html.
final class Sound {
    static let shared = Sound()

    var volume = 70   // 1...100

    private let rate = 22050.0
    private var players: [AVAudioPlayer] = []
    private let synth = AVSpeechSynthesizer()

    private init() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    // MARK: - Töne

    func beep() {
        let n = Int(rate * 0.09)
        var s = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let env = min(1.0, Double(i) / 60.0) * min(1.0, Double(n - i) / 300.0)
            s[i] = square(1320.0 * t) * 0.35 * env
        }
        play(s)
    }

    func joinTone() {
        let n = Int(rate * 0.18)
        var s = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            let f = t < 0.09 ? 660.0 : 990.0
            let env = min(1.0, Double(n - i) / 400.0)
            s[i] = square(f * t) * 0.2 * env
        }
        play(s)
    }

    func effect(_ n: Int) {
        switch n {
        case 1: play(siren())
        case 2: play(laser())
        case 3: play(fanfare())
        case 4: play(explosion())
        default: play(boing())
        }
    }

    // 1: Alarm-Sirene
    private func siren() -> [Double] {
        let n = Int(rate * 1.6)
        var s = [Double](repeating: 0, count: n)
        var ph = 0.0
        for i in 0..<n {
            let t = Double(i) / rate
            let f = 750.0 + 450.0 * sin(2.0 * Double.pi * 1.25 * t)
            ph += f / rate
            let env = min(1.0, Double(n - i) / 2000.0)
            s[i] = triangle(ph) * 0.55 * env
        }
        return s
    }

    // 2: Laser "piu piu piu"
    private func laser() -> [Double] {
        let one = Int(rate * 0.16)
        var s = [Double](repeating: 0, count: one * 3)
        for k in 0..<3 {
            var ph = 0.0
            for i in 0..<one {
                let x = Double(i) / Double(one)
                let f = 2200.0 * pow(0.08, x)
                ph += f / rate
                s[k * one + i] = square(ph) * 0.3 * (1.0 - x)
            }
        }
        return s
    }

    // 3: Retro-Fanfare
    private func fanfare() -> [Double] {
        let notes: [Double] = [523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5]
        let lens: [Double] = [0.11, 0.11, 0.11, 0.22, 0.11, 0.5]
        let total = lens.reduce(0, +)
        var s = [Double](repeating: 0, count: Int(rate * total))
        var pos = 0
        for k in 0..<notes.count {
            let len = Int(rate * lens[k])
            var i = 0
            while i < len && pos < s.count {
                let t = Double(i) / rate
                let a = min(1.0, Double(i) / 80.0)
                let b = min(1.0, Double(len - i) / 250.0)
                let v = square(notes[k] * t) * 0.22 + square(notes[k] * 2.003 * t) * 0.08
                s[pos] = v * a * b
                i += 1
                pos += 1
            }
        }
        return s
    }

    // 4: Explosion
    private func explosion() -> [Double] {
        let n = Int(rate * 1.3)
        var s = [Double](repeating: 0, count: n)
        var lp = 0.0
        var hold = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(n)
            if i % 3 == 0 { hold = Double.random(in: -1...1) }
            let a = 0.02 + 0.25 * (1.0 - x)
            lp += (hold - lp) * a
            let env = pow(1.0 - x, 2.2) * min(1.0, Double(i) / 40.0)
            s[i] = lp * 1.6 * env
        }
        return s
    }

    // 5: Boing
    private func boing() -> [Double] {
        let n = Int(rate * 0.8)
        var s = [Double](repeating: 0, count: n)
        var ph = 0.0
        for i in 0..<n {
            let x = Double(i) / Double(n)
            let t = Double(i) / rate
            let wobble = 60.0 * sin(2.0 * Double.pi * 18.0 * t) * (1.0 - x)
            let f = 140.0 + 260.0 * exp(-x * 4.0) + wobble
            ph += f / rate
            let env = (1.0 - x) * min(1.0, Double(i) / 50.0)
            s[i] = sin(2.0 * Double.pi * ph) * 0.7 * env
        }
        return s
    }

    private func square(_ c: Double) -> Double {
        return (c - c.rounded(.down)) < 0.5 ? 1.0 : -1.0
    }

    private func triangle(_ c: Double) -> Double {
        let f = c - c.rounded(.down)
        return 4.0 * abs(f - 0.5) - 1.0
    }

    // MARK: - Abspielen (als WAV im Speicher)

    private func play(_ samples: [Double]) {
        let v = pow(Double(max(0, min(100, volume))) / 100.0, 2.0)
        var d = Data()
        func u32(_ x: UInt32) { var le = x.littleEndian; d.append(Data(bytes: &le, count: 4)) }
        func u16(_ x: UInt16) { var le = x.littleEndian; d.append(Data(bytes: &le, count: 2)) }

        let dataLen = UInt32(samples.count * 2)
        d.append(contentsOf: [UInt8]("RIFF".utf8)); u32(36 + dataLen)
        d.append(contentsOf: [UInt8]("WAVE".utf8))
        d.append(contentsOf: [UInt8]("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: [UInt8]("data".utf8)); u32(dataLen)

        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let c = max(-1.0, min(1.0, samples[i] * v))
            pcm[i] = Int16(c * 32000.0).littleEndian
        }
        pcm.withUnsafeBufferPointer { d.append($0) }

        players.removeAll { !$0.isPlaying }
        if let p = try? AVAudioPlayer(data: d) {
            p.prepareToPlay()
            p.play()
            players.append(p)
        }
    }

    // MARK: - Vorlesen

    func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "de-DE")
        u.volume = Float(max(0, min(100, volume))) / 100
        synth.speak(u)
    }
}
