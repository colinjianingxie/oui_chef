import Foundation

struct ChefPreferences: Codable, Equatable {
    var onboardingComplete = false
    var dietary = Set<String>()
    var allergies = Set<String>()
    var allergyAnswer = "Not specified"
    var equipment = Set<String>()
    var spice = 0.5
    var sweetness = 0.5
    var salt = 0.5
    var detailedGuidance = true
    var avoidAlcohol = false
    var analyticsEnabled = false
    var keepScreenAwake = true
}

enum VoiceCommand: Equatable {
    case pause, resume, mute, repeatStep, status, done, yes, notYet, start, quieter, detailed
    case recipe(String)
    case unknown

    static func parse(_ text: String) -> Self {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let sentence = words.joined(separator: " ")
        // ponytail: exact command grammar for the offline prototype; open-ended intent uses the cloud specialist later.
        switch sentence {
        case "pause", "pause recipe", "pause guidance", "stop": return .pause
        case "resume", "resume recipe", "continue", "play": return .resume
        case "mute", "stop listening", "end conversation": return .mute
        case "repeat", "repeat that", "repeat step": return .repeatStep
        case "where are we", "what s next", "what is next", "status", "how much time is left": return .status
        case "done", "i m done", "i am done", "finished", "i m finished", "i am finished", "ready", "it s ready": return .done
        case "yes": return .yes
        case "not yet", "no", "needs more time", "still pale": return .notYet
        case "start", "i ve started", "start step", "it s cooking": return .start
        case "less talking", "quieter": return .quieter
        case "talk me through it", "more guidance": return .detailed
        default:
            if ["spaghetti", "pasta", "make spaghetti", "find pasta", "i want pasta"].contains(sentence) { return .recipe("spaghetti") }
            if ["bread", "make bread", "find bread", "i want to bake bread"].contains(sentence) { return .recipe("bread") }
            if ["margarita", "margaritas", "make a margarita", "find a margarita"].contains(sentence) { return .recipe("margarita") }
            return .unknown
        }
    }
}
