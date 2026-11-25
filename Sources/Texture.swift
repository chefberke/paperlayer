import AppKit

/// Small seeded PRNG so the texture looks the same on every launch.
struct SplitMix {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// Smooth value noise in 0...1 that wraps at `size`, so tiles are seamless.
struct ValueNoise {
    let n: Int, cell: Int, grid: [Double]

    init(size: Int, cell: Int, rng: inout SplitMix) {
        self.cell = cell
        n = size / cell
        grid = (0..<(n * n)).map { _ in rng.unit() }
    }

    func at(_ x: Int, _ y: Int) -> Double {
        let gx = Double(x) / Double(cell), gy = Double(y) / Double(cell)
        let x0 = Int(gx), y0 = Int(gy)
        let fx = gx - Double(x0), fy = gy - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func g(_ i: Int, _ j: Int) -> Double { grid[(j % n) * n + (i % n)] }
        let top = g(x0, y0) + (g(x0 + 1, y0) - g(x0, y0)) * sx
        let bottom = g(x0, y0 + 1) + (g(x0 + 1, y0 + 1) - g(x0, y0 + 1)) * sx
        return top + (bottom - top) * sy
    }
}

enum PaperTexture {
    /// Tile edge in pixels. The noise cell size divides it.
    static let size = 384

    /// Neutral mid gray matte paper: fine grain plus a faint uneven surface.
    /// Drawn at low alpha it lifts blacks and softens whites without shifting hue,
    /// which is what takes the glare and harsh contrast out of the screen.
    static func make(scale: CGFloat) -> NSImage {
        let s = size
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: s * 4, bitsPerPixel: 32)!
        let px = rep.bitmapData!
        var rng = SplitMix(state: 0x5EED)
        let surface = ValueNoise(size: s, cell: 32, rng: &rng)

        for y in 0..<s {
            for x in 0..<s {
                let v = 150 + (rng.unit() - 0.5) * 80 + (surface.at(x, y) - 0.5) * 24
                let c = UInt8(max(0, min(255, v.rounded())))
                let i = (y * s + x) * 4
                px[i] = c
                px[i + 1] = c
                px[i + 2] = c
                px[i + 3] = 255
            }
        }

        let image = NSImage(size: NSSize(width: CGFloat(s) / scale, height: CGFloat(s) / scale))
        image.addRepresentation(rep)
        return image
    }
}
