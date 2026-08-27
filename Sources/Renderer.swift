import Foundation
import CoreGraphics
import AppKit

/// Все размеры — в точках принтера: 203.2 dpi = 8 точек на миллиметр.
enum P {
    static let dotsPerMM: CGFloat = 8
    static let headDots = 384                 // ширина печатающей головки = 48 мм
    static func mm(_ v: CGFloat) -> CGFloat { v * dotsPerMM }
}

/// Что пользователь накрутил в окне.
struct Layout: Equatable {
    var labelMM: CGFloat = 50                 // шаг подачи: высота наклейки с зазором
    var printMM: CGFloat = 40                 // диаметр самого рисунка
    var zoom: CGFloat = 1.0                   // масштаб картинки внутри круга
    var panX: CGFloat = 0                     // сдвиг картинки, доли диаметра
    var panY: CGFloat = 0
    var shiftXMM: CGFloat = 0                 // калибровка печати: вправо +
    var shiftYMM: CGFloat = 0                 // калибровка печати: вниз +
    var brightness: CGFloat = 0               // -1 … +1
    var contrast: CGFloat = 1                 // 0.5 … 2
    var dither = false                        // Флойд—Стайнберг: для фото; для рисунка — порог
    var threshold: Int = 190                  // граница чёрного при печати рисунка
    var cleanBG: CGFloat = 0.06               // «почти белое» считать белым: убирает шум JPEG
    var invert = false
    var density = 15                          // 1…15, нагрев головки
    var speed = 1                             // 1 — медленно и чётко, 5 — быстро
    /// Зеркало и переворот — компенсация того, как головка кладёт точки.
    /// На превью не влияют: там всегда видно, как наклейка ляжет в руку.
    var mirror = true
    var flip180 = false
    var copies = 1

    /// Высота холста = высота наклейки: столько ленты принтер протянет.
    var canvasHeight: Int { Int((P.mm(labelMM)).rounded()) }
    /// Диаметр рисунка в точках. Шире головки не бывает.
    var circleDots: CGFloat { min(P.mm(printMM), CGFloat(P.headDots)) }
}

enum Renderer {

    /// Центр круга с учётом калибровочного сдвига и прямоугольник картинки.
    static func geometry(image: CGImage?, layout L: Layout)
        -> (center: CGPoint, diameter: CGFloat, rect: CGRect?) {
        let w = CGFloat(P.headDots), h = CGFloat(L.canvasHeight)
        let c = CGPoint(x: w / 2 + P.mm(L.shiftXMM), y: h / 2 - P.mm(L.shiftYMM))
        let d = L.circleDots
        guard let img = image else { return (c, d, nil) }
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let fill = max(d / iw, d / ih) * L.zoom
        let dw = iw * fill, dh = ih * fill
        return (c, d, CGRect(x: c.x - dw / 2 + L.panX * d,
                             y: c.y - dh / 2 - L.panY * d, width: dw, height: dh))
    }

    /// Превью для глаз: вне круга — ярко-зелёное, внутри — ровно то, что напечатается.
    /// Заезжающая за край картинка видна приглушённой, чтобы было куда целиться.
    static func colorPreview(image: CGImage?, layout L: Layout, printed: Bool) -> CGImage? {
        let w = P.headDots, h = L.canvasHeight
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(red: 0.925, green: 0.118, blue: 0.471, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let g = geometry(image: image, layout: L)
        if let img = image, let rect = g.rect {          // обрезаемое — призраком
            ctx.saveGState()
            ctx.setAlpha(0.28)
            ctx.draw(img, in: rect)
            ctx.restoreGState()
        }

        guard let inside = compose(image: image, layout: L) else { return ctx.makeImage() }
        let shown = printed ? (preview1bit(inside, layout: L) ?? inside) : inside
        let circle = CGRect(x: g.center.x - g.diameter / 2, y: g.center.y - g.diameter / 2,
                            width: g.diameter, height: g.diameter)
        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        ctx.draw(shown, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()

        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: circle)

        // край физической наклейки — пунктиром, печать должна остаться внутри
        let ld = P.mm(L.labelMM)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [5, 5])
        ctx.strokeEllipse(in: CGRect(x: g.center.x - ld / 2, y: g.center.y - ld / 2,
                                     width: ld, height: ld))
        ctx.setLineDash(phase: 0, lengths: [])
        return ctx.makeImage()
    }

    /// Рисует итоговую наклейку: круг с вписанной картинкой, всё вне круга — белое.
    /// Возвращает серую картинку шириной 384 и высотой под наклейку.
    static func compose(image: CGImage?, layout L: Layout) -> CGImage? {
        let w = P.headDots, h = L.canvasHeight
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let g = geometry(image: image, layout: L)
        let c = g.center, d = g.diameter
        let circle = CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)

        if let img = image, let rect = g.rect {
            ctx.saveGState()
            ctx.addEllipse(in: circle)
            ctx.clip()
            ctx.draw(img, in: rect)
            ctx.restoreGState()
        } else {
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(2)
            ctx.strokeEllipse(in: circle)
        }
        guard let out = ctx.makeImage() else { return nil }
        return adjust(out, layout: L)
    }

    /// Яркость, контраст, инверсия — по пикселям, дёшево и предсказуемо.
    private static func adjust(_ img: CGImage, layout L: Layout) -> CGImage? {
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 255, count: w * h)
        px.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        let b = L.brightness * 255
        for i in 0..<px.count {
            var v = (CGFloat(px[i]) - 128) * L.contrast + 128 + b
            if L.invert { v = 255 - v }
            px[i] = UInt8(max(0, min(255, v)))
        }
        return makeImage(px, w, h)
    }

    private static func makeImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        var data = px
        return data.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    /// Картинка ровно такая, какой её выплюнет принтер: только чёрное и белое.
    static func preview1bit(_ img: CGImage, layout L: Layout) -> CGImage? {
        let (w, h, bw) = binarize(img, dither: L.dither,
                                  threshold: L.threshold, cleanBG: L.cleanBG)
        var px = [UInt8](repeating: 255, count: w * h)
        for i in 0..<(w * h) { px[i] = bw[i] ? 0 : 255 }
        return makeImage(px, w, h)
    }

    /// Порог или Флойд—Стайнберг. true = точка чёрная.
    private static func binarize(_ img: CGImage, dither: Bool,
                                 threshold: Int = 128, cleanBG: CGFloat = 0) -> (Int, Int, [Bool]) {
        let w = img.width, h = img.height
        var gray = [UInt8](repeating: 255, count: w * h)
        gray.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        // «почти белое» — в чистый белый: снимает шум JPEG и серый фон
        if cleanBG > 0 {
            let cut = UInt8(max(0, min(255, 255 - cleanBG * 255)))
            for i in 0..<(w * h) where gray[i] >= cut { gray[i] = 255 }
        }
        var out = [Bool](repeating: false, count: w * h)
        if !dither {
            let t = UInt8(clamping: threshold)
            for i in 0..<(w * h) { out[i] = gray[i] < t }
            return (w, h, out)
        }
        var f = gray.map { Float($0) }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let old = f[i]
                let new: Float = old < 128 ? 0 : 255
                out[i] = new == 0
                let err = old - new
                func spread(_ dx: Int, _ dy: Int, _ k: Float) {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { return }
                    f[ny * w + nx] += err * k
                }
                spread(1, 0, 7.0 / 16); spread(-1, 1, 3.0 / 16)
                spread(0, 1, 5.0 / 16); spread(1, 1, 1.0 / 16)
            }
        }
        return (w, h, out)
    }

    /// Растр для принтера: 48 байт на строку, MSB — левый пиксель, 1 = чёрное.
    /// CoreGraphics хранит строки снизу вверх, принтер печатает сверху вниз.
    static func raster(_ img: CGImage, layout L: Layout) -> (data: Data, lines: Int) {
        let mirror = L.mirror, flip180 = L.flip180
        let (w, h, bw) = binarize(img, dither: L.dither,
                                  threshold: L.threshold, cleanBG: L.cleanBG)
        let bytesPerLine = P.headDots / 8
        var out = Data(count: bytesPerLine * h)
        out.withUnsafeMutableBytes { dst in
            let d = dst.bindMemory(to: UInt8.self)
            for y in 0..<h {
                // CoreGraphics хранит строки снизу вверх; flip180 отменяет переворот
                let srcRow = (flip180 ? y : h - 1 - y) * w
                for x in 0..<min(w, P.headDots) {
                    let sx = (mirror != flip180) ? (w - 1 - x) : x
                    if bw[srcRow + sx] {
                        d[y * bytesPerLine + x / 8] |= UInt8(0x80) >> UInt8(x % 8)
                    }
                }
            }
        }
        return (out, h)
    }

    /// Загрузка файла картинки (PNG, JPEG, HEIC — всё, что понимает macOS).
    static func load(url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return img
    }
}
