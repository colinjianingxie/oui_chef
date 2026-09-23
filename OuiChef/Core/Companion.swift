import Foundation

// The cookbook contract is independent of the model provider and the legacy catalog.
struct CompanionRecipe: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var summary: String = ""
    var sourceURL: String
    var sourceName: String
    var creator: String?
    var imageURL: String?
    var imagePath: String?
    var servings: Int?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
    var ingredients: [RecipeIngredient]
    var preparation: [String] = []
    var steps: [RecipeStep]
    var equipment: [String] = []
    var notes: [String] = []
    var adaptations: [String] = []
    var warnings: [String] = []
    var evidence: [RecipeEvidence] = []
    var modelRunID: String?
    var favorite = false
    var reviewed = false
    var createdAt: Double = Date().timeIntervalSince1970 * 1000
    var version = 1

    var timeLabel: String { totalMinutes.map { $0 >= 60 ? "\($0 / 60) hr\($0 % 60 == 0 ? "" : " \($0 % 60) min")" : "\($0) min" } ?? "Go by the cues" }
    var youtubeThumbnailURL: URL? {
        guard sourceName == "YouTube", let source = URLComponents(string: sourceURL), source.host == "www.youtube.com",
              let id = source.queryItems?.first(where: { $0.name == "v" })?.value,
              id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }
    var stages: [String] { steps.reduce(into: []) { if !$0.contains($1.stage) { $0.append($1.stage) } } }
    func validate() throws {
        guard !id.isEmpty, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...150).contains(ingredients.count), (1...150).contains(steps.count),
              Set(ingredients.map(\.id)).count == ingredients.count, Set(steps.map(\.id)).count == steps.count else {
            throw CookingError.invalid("This recipe needs ingredients and usable steps.")
        }
        let ids = Set(ingredients.map(\.id))
        for item in ingredients {
            guard !item.name.isEmpty, item.amount == nil || (item.amount!.isFinite && item.amount! > 0) else { throw CookingError.invalid("Invalid ingredient quantity.") }
        }
        for step in steps {
            guard !step.instruction.isEmpty, Set(step.ingredients.map(\.ingredientID)).isSubset(of: ids),
                  step.durationSeconds == nil || (step.durationSeconds!.isFinite && (1...604800).contains(step.durationSeconds!)),
                  step.videoSeconds == nil || (step.videoSeconds!.isFinite && step.videoSeconds! >= 0) else { throw CookingError.invalid("A recipe step contains an invalid ingredient or timer.") }
        }
    }
}

struct RecipeIngredient: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var quantity: String
    var amount: Double?
    var unit: String?
    var pantry = false
    var optional = false
    var component: String = "Main"
    var substitution: String?
    var origin: String = "source"
}

struct StepIngredient: Codable, Equatable {
    var ingredientID: String
    var quantity: String
}

struct RecipeStep: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var instruction: String
    var stage: String
    var component: String = "Main"
    var ingredients: [StepIngredient] = []
    var durationSeconds: Double?
    var timingEstimated = false
    var visualCue: String?
    var temperature: String?
    var videoSeconds: Double?
    var reminder: String?
}

struct RecipeEvidence: Codable, Equatable {
    var field: String
    var origin: String
    var detail: String
    var url: String?
    var timestamp: Double?
}

struct RecipeImport: Codable, Identifiable, Equatable {
    var id: String
    var url: String
    var status: String
    var message: String
    var recipeID: String?
    var createdAt: Double
    var source: String
    var stage: Int?
    var attempt: Int?
    var previewTitle: String?
    var previewCreator: String?
    var previewSummary: String?
    var previewIngredients: [String]?
    var previewSteps: [String]?
    var sourceTitle: String?
    var sourceDurationSeconds: Double?
    var sourceExtractor: String?
    var recipeTitle: String?
    var originalTranscript: String?
    var transcriptLanguage: String?
    var translatedTranscript: String?
    var videoObservations: String?
    var frameSeconds: [Double]?
    var extractionReason: String?
    var failurePoint: String?
    var running: Bool { ["queued", "fetching", "transcribing", "extracting", "checking"].contains(status) }
    var hasImportEvidence: Bool { sourceTitle != nil || recipeTitle != nil || originalTranscript != nil || translatedTranscript != nil || videoObservations != nil || previewIngredients != nil || failurePoint != nil }
    static let stages = ["Read metadata & transcript", "Check for a food recipe", "Translate & inspect video", "Build ingredients & steps", "Save to your cookbook"]
    var progressStage: Int {
        if let stage { return max(0, min(stage, Self.stages.count)) }
        switch status {
        case "transcribing": return 2
        case "extracting": return 3
        case "checking": return 1
        case "ready": return 5
        default: return 0
        }
    }
}

struct AttemptEvent: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var at: Double
    var kind: String
    var stepID: String?
    var detail: String
}

struct CookingMessage: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var role: String
    var text: String
    var at: Double = Date().timeIntervalSince1970 * 1000
}

struct AttemptTimer: Codable, Identifiable, Equatable {
    var id: String
    var stepID: String
    var label: String
    var cue: String
    var startedAt: Double
    var deadline: Double
    var pausedSeconds: Double?
    var acknowledged = false
    func remaining(at now: Double) -> Double { max(0, pausedSeconds ?? ((deadline - now) / 1000)) }
    func expired(at now: Double) -> Bool { pausedSeconds == nil && now >= deadline && !acknowledged }
}

struct CookAttempt: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var recipe: CompanionRecipe
    var revision = 0
    var focusIndex = 0
    var completed: [String] = []
    var skipped: [String] = []
    var timers: [AttemptTimer] = []
    var events: [AttemptEvent] = []
    var messages: [CookingMessage] = []
    var changes: [String] = []
    var startedAt: Double = Date().timeIntervalSince1970 * 1000
    var finishedAt: Double?
    var notes = ""
    var rating = 0
    var photoFile: String?
    var photoPath: String?
    var guidancePaused = false
    var deliveredReminders: [String] = []

    var currentStep: RecipeStep { recipe.steps[min(max(0, focusIndex), recipe.steps.count - 1)] }
    var finishedSteps: Int { Set(completed + skipped).count }
    var allStepsFinished: Bool { finishedSteps == recipe.steps.count }
    func count(_ kind: String, stepID: String) -> Int { events.filter { $0.kind == kind && $0.stepID == stepID }.count }

    mutating func apply(_ action: CookAction, at now: Double) throws {
        guard action.sessionID == id else { throw CookingError.invalid("Choose the active cooking session.") }
        guard !events.contains(where: { $0.id == action.id }) else { return }
        guard action.revision == revision else { throw CookingError.invalid("The cooking state changed. Please try again.") }
        guard finishedAt == nil else { throw CookingError.invalid("This attempt is finished. Start a new cook to make it again.") }
        let target = action.target ?? currentStep.id
        let step = recipe.steps.first { $0.id == target }
        var detail = action.text ?? ""
        switch action.operation {
        case "complete_step", "skip_step", "reopen_step":
            guard let step else { throw CookingError.invalid("Choose a recipe step.") }
            if action.operation == "reopen_step" {
                completed.removeAll { $0 == target }; skipped.removeAll { $0 == target }
                focusIndex = recipe.steps.firstIndex { $0.id == target }!
            } else {
                guard !completed.contains(target), !skipped.contains(target) else { return }
                if action.operation == "complete_step" { completed.append(target) } else { skipped.append(target) }
                if let next = recipe.steps.indices.first(where: { !completed.contains(recipe.steps[$0].id) && !skipped.contains(recipe.steps[$0].id) }) { focusIndex = next }
            }
            detail = step.title
        case "focus_step":
            guard let index = recipe.steps.firstIndex(where: { $0.id == target }) else { throw CookingError.invalid("Choose a recipe step.") }
            focusIndex = index
        case "start_timer":
            guard let step, let seconds = action.seconds ?? step.durationSeconds, seconds.isFinite, (1...604800).contains(seconds), timers.filter({ !$0.acknowledged }).count < 20 else { throw CookingError.invalid("Choose a timer between one second and seven days (up to 20 active timers).") }
            timers.append(AttemptTimer(id: action.id, stepID: step.id, label: action.text?.isEmpty == false ? action.text! : step.title,
                cue: step.visualCue ?? "Check whether this step is ready.", startedAt: now, deadline: now + seconds * 1000))
            detail = "\(step.title): \(Int(seconds)) seconds"
        case "pause_timer", "resume_timer", "extend_timer", "cancel_timer", "acknowledge_timer":
            guard let index = timers.firstIndex(where: { $0.id == target && !$0.acknowledged }) else { throw CookingError.invalid("Choose an active timer.") }
            if action.operation == "pause_timer" {
                guard timers[index].pausedSeconds == nil else { return }
                timers[index].pausedSeconds = timers[index].remaining(at: now)
            } else if action.operation == "resume_timer" {
                guard let seconds = timers[index].pausedSeconds else { return }
                timers[index].deadline = now + seconds * 1000; timers[index].pausedSeconds = nil
            } else if action.operation == "extend_timer" {
                guard let seconds = action.seconds, seconds.isFinite, (1...604800).contains(seconds) else { throw CookingError.invalid("Choose a valid timer extension.") }
                if let paused = timers[index].pausedSeconds { timers[index].pausedSeconds = paused + seconds }
                else { timers[index].deadline = max(now, timers[index].deadline) + seconds * 1000 }
            } else { timers[index].acknowledged = true }
            if ["resume_timer", "extend_timer"].contains(action.operation) { deliveredReminders.removeAll { $0 == target } }
            detail = timers[index].label
        case "record_change":
            guard !detail.isEmpty, detail.count <= 1000 else { throw CookingError.invalid("Describe the change you made.") }
            changes.append(detail)
        case "pause_guidance": guidancePaused = true
        case "resume_guidance": guidancePaused = false
        case "finish":
            guard allStepsFinished else { throw CookingError.invalid("Complete or skip the remaining steps first.") }
            finishedAt = now
            for index in timers.indices { timers[index].acknowledged = true }
        default: throw CookingError.invalid("That cooking action is unavailable.")
        }
        revision += 1
        events.append(AttemptEvent(id: action.id, at: now, kind: action.operation, stepID: step?.id, detail: detail))
    }
}

struct CookAction: Codable {
    var id: String = UUID().uuidString
    var operation: String
    var sessionID: String
    var revision: Int
    var target: String?
    var seconds: Double?
    var text: String?
}

enum CompanionJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    static func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T { try JSONDecoder().decode(type, from: Data(text.utf8)) }
}
