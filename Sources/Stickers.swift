import UIKit
import ImageIO

/// Eingebaute Pixel-Sticker (identisch zu Chat.exe / chat.html)
enum Stickers {
    static let names = ["smile", "cool", "sad", "heart", "star", "fire", "skull", "ghost", "cat"]

    private static let maps: [String: [String]] = [
        "smile": ["....KKKK....", "..KKYYYYKK..", ".KYYYYYYYYK.", ".KYYKYYKYYK.", "KYYYKYYKYYYK", "KYYYYYYYYYYK",
                  "KYYYYYYYYYYK", "KYKYYYYYYKYK", ".KYKKYYKKYK.", ".KYYYKKYYYK.", "..KKYYYYKK..", "....KKKK...."],
        "cool":  ["....KKKK....", "..KKYYYYKK..", ".KYYYYYYYYK.", "KKKKKKKKKKKK", "KYKKKYYKKKYK", "KYYKYYYYKYYK",
                  "KYYYYYYYYYYK", "KYYYYYYYKYYK", ".KYYYYYKKYK.", ".KYYKKKYYYK.", "..KKYYYYKK..", "....KKKK...."],
        "sad":   ["....KKKK....", "..KKYYYYKK..", ".KYYYYYYYYK.", ".KYKKYYKKYK.", "KYYYKYYKYYYK", "KYYBYYYYYYYK",
                  "KYYBYYYYYYYK", "KYBBYKKYYYYK", ".KYYKYYKYYK.", ".KYYYYYYYYK.", "..KKYYYYKK..", "....KKKK...."],
        "heart": ["............", ".KKK....KKK.", "KRRRK..KRRRK", "KRWRRKKRRRRK", "KRWRRRRRRRRK", "KRRRRRRRRRRK",
                  ".KRRRRRRRRK.", "..KRRRRRRK..", "...KRRRRK...", "....KRRK....", ".....KK.....", "............"],
        "star":  [".....KK.....", "....KYYK....", "....KYYK....", "...KYYYYK...", "KKKKYYYYKKKK", "KYYYYYYYYYYK",
                  ".KYYYYYYYYK.", "..KYYYYYYK..", "..KYYYYYYK..", ".KYYYKKYYYK.", ".KYKK..KKYK.", ".KK......KK."],
        "fire":  [".....R......", "....RR......", "....RRR..R..", "...RRRR.RR..", "..RRORRRRR..", "..RROORRRRR.",
                  ".RROOOORRRR.", ".RROYYOORRR.", ".RROYYYORRR.", ".RROYYYOORR.", "..RROYYORR..", "...RRRRRR..."],
        "skull": ["...KKKKKK...", "..KWWWWWWK..", ".KWWWWWWWWK.", ".KWWWWWWWWK.", ".KWKKWWKKWK.", ".KWKKWWKKWK.",
                  ".KWWWKKWWWK.", "..KWWWWWWK..", "...KWKWKWK..", "...KWWWWWK..", "....KKKKK...", "............"],
        "ghost": ["....KKKK....", "..KKWWWWKK..", ".KWWWWWWWWK.", ".KWWKWWKWWK.", "KWWWKWWKWWWK", "KWWWWWWWWWWK",
                  "KWWWWKKWWWWK", "KWWWWKKWWWWK", "KWWWWWWWWWWK", "KWWWWWWWWWWK", "KWKWWKKWWKWK", ".K.KK..KK.K."],
        "cat":   [".K........K.", ".KK......KK.", ".KNK....KNK.", ".KNNKKKKNNK.", "KNNNNNNNNNNK", "KNNKNNNNKNNK",
                  "KNNKNNNNKNNK", "KNPNNKKNNPNK", "KNNNNNNNNNNK", ".KNNKNNKNNK.", "..KNNKKNNK..", "...KKKKKK..."],
    ]

    private static let palette: [Character: UIColor] = [
        "K": .black,
        "Y": UIColor(red: 1, green: 220 / 255, blue: 0, alpha: 1),
        "R": UIColor(red: 220 / 255, green: 0, blue: 0, alpha: 1),
        "W": .white,
        "O": UIColor(red: 1, green: 136 / 255, blue: 0, alpha: 1),
        "B": UIColor(red: 0, green: 120 / 255, blue: 1, alpha: 1),
        "N": UIColor(red: 160 / 255, green: 96 / 255, blue: 40 / 255, alpha: 1),
        "P": UIColor(red: 1, green: 140 / 255, blue: 180 / 255, alpha: 1),
    ]

    private static var cache: [String: UIImage] = [:]

    static func exists(_ name: String) -> Bool { maps[name] != nil }

    /// 12×12-Pixel-Bild; in der Anzeige mit .interpolation(.none) vergrößern
    static func image(_ name: String) -> UIImage {
        if let c = cache[name] { return c }
        let map = maps[name] ?? []
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12), format: format).image { ctx in
            for (y, row) in map.enumerated() {
                for (x, ch) in row.enumerated() {
                    if let color = palette[ch] {
                        color.setFill()
                        ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
            }
        }
        cache[name] = img
        return img
    }
}

/// Lädt GIFs (auch animiert), PNG und JPEG
enum Gif {
    static func image(from data: Data) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(src)
        if count <= 1 {
            guard let img = UIImage(data: data), img.size.width >= 1, img.size.height >= 1,
                  img.size.width <= 4000, img.size.height <= 4000 else { return nil }
            return img
        }
        var frames: [UIImage] = []
        var total = 0.0
        for i in 0..<min(count, 300) {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            var delay = 0.1
            if let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any],
               let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
                if let u = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double, u > 0.011 {
                    delay = u
                } else if let c = gif[kCGImagePropertyGIFDelayTime] as? Double, c > 0.011 {
                    delay = c
                }
            }
            frames.append(UIImage(cgImage: cg))
            total += delay
        }
        if frames.isEmpty { return nil }
        if frames.count == 1 { return frames[0] }
        return UIImage.animatedImage(with: frames, duration: total)
    }
}
