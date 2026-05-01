import Foundation

// What the user is asking us to do.
enum IntentType {
    case matchCheck    // "do these match?"
    case colorIdentify // "what color is this?"
    case outfitPick    // "which outfit should I wear?"
}

struct UserIntent: Sendable {
    var type: IntentType
    var colorTone: String?  // warm / cool / neutral
    var brightness: String? // light / dark
    var style: String?      // casual / formal
}

struct IntentParser {

    static func parse(_ transcript: String) -> UserIntent {
        let t = transcript.lowercased()

        let type: IntentType
        if t.contains("match") || t.contains("go together") || t.contains("work together") {
            type = .matchCheck
        } else if t.contains("what color") || t.contains("what colors") ||
                  t.contains("color is") || t.contains("colors are") ||
                  t.contains("what colour") || t.contains("what colours") ||
                  t.contains("colour is") || t.contains("colours are") {
            type = .colorIdentify
        } else if t.contains("pick") || t.contains("choose") ||
                  t.contains("which one") || t.contains("lay out") {
            type = .outfitPick
        } else {
            // If we can't tell, use match check as the safest default.
            type = .matchCheck
        }

        let colorTone: String?
        if t.contains("warm") || t.contains("earthy") {
            colorTone = "warm"
        } else if t.contains("cool") || t.contains("cold") {
            colorTone = "cool"
        } else if t.contains("neutral") {
            colorTone = "neutral"
        } else {
            colorTone = nil
        }

        let brightness: String?
        if t.contains("light") || t.contains("bright") || t.contains("pale") {
            brightness = "light"
        } else if t.contains("dark") || t.contains("deep") {
            brightness = "dark"
        } else {
            brightness = nil
        }

        let style: String?
        if t.contains("casual") || t.contains("everyday") || t.contains("relaxed") {
            style = "casual"
        } else if t.contains("formal") || t.contains("office") || t.contains("business") {
            style = "formal"
        } else {
            style = nil
        }

        return UserIntent(type: type, colorTone: colorTone, brightness: brightness, style: style)
    }
}
