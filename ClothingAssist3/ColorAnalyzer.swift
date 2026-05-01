import UIKit
import CoreImage

final class ColorAnalyzer: Sendable {
    nonisolated static let lowConfidenceMessage = "I’m not confident what I’m seeing. Try better lighting or separating the clothes."

    struct GridSample: Sendable {
        let name: String
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat
    }

    enum Confidence: String, Sendable {
        case high
        case medium
        case low
    }

    struct QualityCheck: Sendable {
        let confidence: Confidence
        let colors: [String]
        let retryMessage: String?
    }

    // MARK: - Color naming

    // Map raw RGB into one of our named color buckets.
    nonisolated static func colorName(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let hue = h * 360

        if v < 0.15 { return "black" }
        if v > 0.85 && s < 0.15 { return "white" }
        if s < 0.15 { return "gray" }

        // Beige is usually light, warm, and not very saturated.
        if v > 0.7 && s < 0.3 && hue >= 20 && hue < 60 { return "beige" }

        // Brown sits in warm orange, just darker.
        if hue >= 15 && hue < 40 && v < 0.5 { return "brown" }

        // Navy is dark blue.
        if hue >= 210 && hue < 250 && v < 0.35 { return "navy" }

        switch hue {
        case 0..<15:    return "red"
        case 15..<40:   return "orange"
        case 40..<70:   return "yellow"
        case 70..<165:  return "green"
        case 165..<210: return "blue" // Treat cyan as blue for matching.
        case 210..<260: return "blue"
        case 260..<290: return "purple"
        case 290..<330: return "pink"
        default:        return "red"  // Hue wraps back to red near 360.
        }
    }

    // MARK: - Grid sampling

    // Sample a 3x3 grid so one bright area does not dominate the result.
    nonisolated static func sampleGrid(from image: UIImage) -> [GridSample] {
        guard let ci = CIImage(image: image) else { return [] }

        let ctx = CIContext()
        let ext = ci.extent
        let cols = 3, rows = 3
        let cellW = ext.width  / CGFloat(cols)
        let cellH = ext.height / CGFloat(rows)

        var samples: [GridSample] = []

        for row in 0..<rows {
            for col in 0..<cols {
                let rect = CGRect(
                    x: ext.minX + CGFloat(col) * cellW,
                    y: ext.minY + CGFloat(row) * cellH,
                    width: cellW,
                    height: cellH
                )

                guard let filter = CIFilter(name: "CIAreaAverage") else { continue }
                filter.setValue(ci, forKey: kCIInputImageKey)
                filter.setValue(CIVector(cgRect: rect), forKey: "inputExtent")
                guard let out = filter.outputImage else { continue }

                // Render one pixel from CIAreaAverage for this grid cell.
                var pixel = [UInt8](repeating: 0, count: 4)
                ctx.render(out,
                           toBitmap: &pixel,
                           rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8,
                           colorSpace: CGColorSpaceCreateDeviceRGB())

                let r = CGFloat(pixel[0]) / 255
                let g = CGFloat(pixel[1]) / 255
                let b = CGFloat(pixel[2]) / 255
                var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
                UIColor(red: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
                samples.append(GridSample(name: colorName(r: r, g: g, b: b),
                                          r: r,
                                          g: g,
                                          b: b,
                                          saturation: s,
                                          brightness: v))
            }
        }

        return samples
    }

    nonisolated static func sampleGridColors(from image: UIImage) -> [String] {
        let samples = sampleGrid(from: image)
        let names = samples.map { $0.name }
        return names
    }

    // Sort colors by how many grid cells they appear in.
    nonisolated static func dominantColors(from image: UIImage) -> [String] {
        let names = sampleGridColors(from: image)
        var counts: [String: Int] = [:]
        for n in names { counts[n, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }

    nonisolated static func dominantColors(from samples: [GridSample]) -> [String] {
        var counts: [String: Int] = [:]
        for sample in samples { counts[sample.name, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map { $0.key }
    }

    // MARK: - Confidence checks

    nonisolated static func qualityCheck(samples: [GridSample]) -> QualityCheck {
        guard samples.count >= 6 else {
            return QualityCheck(confidence: .low,
                                colors: [],
                                retryMessage: lowConfidenceMessage)
        }

        let averageBrightness = samples.map(\.brightness).reduce(0, +) / CGFloat(samples.count)
        if averageBrightness < 0.24 {
            return QualityCheck(confidence: .low,
                                colors: [],
                                retryMessage: lowConfidenceMessage)
        }

        let colors = dominantColors(from: samples)
        let strongColors = strongDistinctColors(from: samples)
        if strongColors.count < 2 {
            return QualityCheck(confidence: .low,
                                colors: strongColors,
                                retryMessage: lowConfidenceMessage)
        }

        if colorDistanceRange(samples: samples) < 0.18 {
            return QualityCheck(confidence: .low,
                                colors: strongColors,
                                retryMessage: lowConfidenceMessage)
        }

        let topCounts = colorCounts(samples: samples)
            .filter { strongColors.contains($0.key) }
            .sorted { $0.value > $1.value }

        if strongColors.count >= 3 || topCounts.prefix(2).map(\.value).reduce(0, +) >= 4 {
            return QualityCheck(confidence: .high, colors: colors, retryMessage: nil)
        }

        return QualityCheck(confidence: .medium, colors: colors, retryMessage: nil)
    }

    nonisolated static func colorCounts(samples: [GridSample]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for sample in samples { counts[sample.name, default: 0] += 1 }
        return counts
    }

    nonisolated static func strongDistinctColors(from samples: [GridSample]) -> [String] {
        let usable = samples.filter { sample in
            sample.brightness > 0.18 && (sample.saturation > 0.10 || neutralColors.contains(sample.name) || sample.name == "navy")
        }

        let counts = colorCounts(samples: usable)
        return counts
            .filter { $0.value >= 1 }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    nonisolated static func colorDistanceRange(samples: [GridSample]) -> CGFloat {
        guard samples.count >= 2 else { return 0 }

        var maxDistance: CGFloat = 0
        for i in 0..<samples.count {
            for j in (i + 1)..<samples.count {
                let dr = samples[i].r - samples[j].r
                let dg = samples[i].g - samples[j].g
                let db = samples[i].b - samples[j].b
                let distance = sqrt(dr * dr + dg * dg + db * db)
                maxDistance = max(maxDistance, distance)
            }
        }

        return maxDistance
    }

    // MARK: - Color groups

    nonisolated static let warmColors   = Set(["red", "orange", "yellow", "brown", "pink"])
    nonisolated static let coolColors   = Set(["blue", "green", "purple", "navy"])
    nonisolated static let neutralColors = Set(["black", "white", "gray", "beige"])

    nonisolated static func tone(of color: String) -> String {
        if warmColors.contains(color) { return "warm" }
        if coolColors.contains(color) { return "cool" }
        return "neutral"
    }

    // MARK: - Harmony rules

    // These pairs usually clash unless the colors are very muted.
    nonisolated static let clashPairs: [Set<String>] = [
        Set(["red", "green"]),
        Set(["orange", "purple"]),
        Set(["yellow", "purple"])
    ]

    nonisolated static func matchScore(a: String, b: String) -> String {
        if neutralColors.contains(a) || neutralColors.contains(b) { return "great match" }

        let pair = Set([a, b])
        if clashPairs.contains(pair) { return "clashes" }

        // Warm-with-warm and cool-with-cool usually works better.
        return tone(of: a) == tone(of: b) ? "decent match" : "clashes"
    }

    // Check every non-neutral pair and count clashes.
    nonisolated static func overallScore(colors: [String]) -> String {
        let chromatic = colors.filter { !neutralColors.contains($0) }
        guard chromatic.count >= 2 else { return "great match" }

        var clashes = 0, total = 0
        for i in 0..<chromatic.count {
            for j in (i + 1)..<chromatic.count {
                total += 1
                if matchScore(a: chromatic[i], b: chromatic[j]) == "clashes" { clashes += 1 }
            }
        }

        let ratio = Double(clashes) / Double(total)
        if ratio > 0.5  { return "clashes" }
        if ratio > 0    { return "decent match" }
        return "great match"
    }

    // MARK: - Main entry point

    nonisolated static func analyze(image: UIImage, intent: UserIntent) -> String {
        let samples = sampleGrid(from: image)
        let quality = qualityCheck(samples: samples)

        if let retryMessage = quality.retryMessage {
            return retryMessage
        }

        let colors = quality.colors
        guard colors.count >= 2, quality.confidence == .medium || quality.confidence == .high else {
            return lowConfidenceMessage
        }

        let note = preferenceSentence(for: intent)

        switch intent.type {
        case .colorIdentify: return colorIdentifyResult(colors: colors, note: note)
        case .matchCheck:    return matchCheckResult(colors: colors, note: note)
        case .outfitPick:    return outfitPickResult(image: image, colors: colors, note: note)
        }
    }

    // MARK: - Result strings (spoken aloud, so keep them short)

    nonisolated static func colorIdentifyResult(colors: [String], note: String) -> String {
        let top = Array(colors.prefix(3))
        let listed = readableList(top)
        return withNote("I can see \(listed), with \(top[0]) looking strongest.", note: note)
    }

    nonisolated static func matchCheckResult(colors: [String], note: String) -> String {
        let score = overallScore(colors: colors)
        let chromatic = colors.filter { !neutralColors.contains($0) }
        let neutrals  = colors.filter { neutralColors.contains($0) }

        switch score {
        case "great match":
            if chromatic.isEmpty {
                return withNote("These look like a good match because the neutral tones work cleanly together.", note: note)
            }
            let tones = Set(chromatic.map { tone(of: $0) })
            if tones.count == 1, let t = tones.first {
                return withNote("These look like a good match because both are \(t) tones and work well together.", note: note)
            }
            if let c = chromatic.first, let n = neutrals.first {
                return withNote("These look like a good match because the \(n) balances the \(c).", note: note)
            }
            return withNote("These look like a good match because the colors feel balanced.", note: note)

        case "decent match":
            let pair = chromatic.prefix(2).joined(separator: " and ")
            return withNote("These are a decent match, but keep the rest of the outfit neutral around the \(pair).", note: note)

        default: // Clashing combo.
            let pair = chromatic.prefix(2).joined(separator: " and ")
            return withNote("The \(pair) combination may clash, so I would swap one piece for white, black, gray, beige, or navy.", note: note)
        }
    }

    nonisolated static func outfitPickResult(image: UIImage, colors: [String], note: String) -> String {
        // Use up to three unique grid colors as outfit pieces.
        let grid = sampleGridColors(from: image)
        var distinct: [String] = []
        for c in grid {
            if !distinct.contains(c) { distinct.append(c) }
            if distinct.count == 3 { break }
        }

        guard !distinct.isEmpty else {
            return lowConfidenceMessage
        }

        if distinct.count == 1 {
            return lowConfidenceMessage
        }

        let score = overallScore(colors: distinct)
        let listed = distinct.prefix(3).joined(separator: ", ")
        let best = bestPair(from: distinct)

        switch score {
        case "great match":
            if let best {
                return withNote("I would pick the \(best.0) piece with the \(best.1) piece because they work well together.", note: note)
            }
            return withNote("I would pick this combination because the \(listed) work well together.", note: note)
        case "decent match":
            if let best {
                return withNote("The safest choice is the \(best.0) piece with the \(best.1) piece, and a neutral item would make it stronger.", note: note)
            }
            return withNote("The \(listed) could work together, but a neutral option would be safer.", note: note)
        default:
            let swap = distinct.first ?? "that piece"
            if let best {
                return withNote("I would avoid wearing all of these together; the best pair is \(best.0) with \(best.1), and I would leave out \(swap).", note: note)
            }
            return withNote("The \(listed) is a tough combination, so I would swap \(swap) for something neutral.", note: note)
        }
    }

    nonisolated static func bestPair(from colors: [String]) -> (String, String)? {
        guard colors.count >= 2 else { return nil }

        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                if matchScore(a: colors[i], b: colors[j]) == "great match" {
                    return (colors[i], colors[j])
                }
            }
        }

        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                if matchScore(a: colors[i], b: colors[j]) == "decent match" {
                    return (colors[i], colors[j])
                }
            }
        }

        return (colors[0], colors[1])
    }

    nonisolated static func preferenceSentence(for intent: UserIntent) -> String {
        var parts: [String] = []
        if let brightness = intent.brightness { parts.append(brightness) }
        if let style = intent.style { parts.append(style) }
        if let tone = intent.colorTone { parts.append("\(tone)-toned") }

        guard !parts.isEmpty else {
            return ""
        }

        return "Since you asked for \(parts.joined(separator: ", ")), keep the look simple."
    }

    nonisolated static func readableList(_ colors: [String]) -> String {
        if colors.count <= 1 { return colors.first ?? "colors" }
        if colors.count == 2 { return "\(colors[0]) and \(colors[1])" }
        return colors.dropLast().joined(separator: ", ") + " and " + colors.last!
    }

    nonisolated static func withNote(_ sentence: String, note: String) -> String {
        guard !note.isEmpty else { return sentence }
        return "\(sentence) \(note)"
    }
}
