import Foundation

struct PreferenceOption: Identifiable, Equatable {
    let id: String
    let name: String
    var aliases: [String] = []

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || ([name] + aliases).contains { $0.localizedStandardContains(query) }
    }
}

enum PreferenceSection: String, Identifiable, CaseIterable {
    case allergies, restrictions, dislikes, equipment
    var id: String { rawValue }
    var title: String {
        switch self {
        case .allergies: "Allergies"
        case .restrictions: "Dietary restrictions"
        case .dislikes: "Foods to avoid"
        case .equipment: "Kitchen equipment"
        }
    }
    var options: [PreferenceOption] {
        switch self {
        case .allergies: Self.commonAllergies + Self.foods.filter { !["milk", "eggs", "egg", "peanuts", "peanut", "soy", "sesame", "wheat"].contains($0.id) }
        case .restrictions: Self.restrictionOptions
        case .dislikes: Self.foods
        case .equipment: Self.equipmentOptions
        }
    }
    func label(_ id: String) -> String { options.first { $0.id == id }?.name ?? id }
    func names(_ ids: Set<String>) -> [String] { ids.map(label).sorted() }
    // ponytail: use the bundled food catalog for this beta; expand it as more choices are needed.
    static let foods: [PreferenceOption] = ((try? IngredientLibrary.bundled().foods) ?? []).map {
        PreferenceOption(id: $0.id, name: $0.name, aliases: $0.aliases ?? [])
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    static let commonAllergies = [
        PreferenceOption(id: "allergen.peanuts", name: "Peanuts", aliases: ["groundnuts"]),
        PreferenceOption(id: "allergen.tree_nuts", name: "Tree nuts", aliases: ["almonds", "cashews", "walnuts", "pecans", "pistachios", "hazelnuts", "macadamia", "Brazil nuts"]),
        PreferenceOption(id: "allergen.milk", name: "Milk / dairy", aliases: ["casein", "whey"]),
        PreferenceOption(id: "allergen.eggs", name: "Eggs", aliases: ["egg white", "egg yolk"]),
        PreferenceOption(id: "allergen.fish", name: "Fish", aliases: ["salmon", "tuna", "cod"]),
        PreferenceOption(id: "allergen.crustaceans", name: "Crustaceans", aliases: ["shellfish", "shrimp", "prawns", "crab", "lobster", "crayfish"]),
        PreferenceOption(id: "allergen.molluscs", name: "Molluscs", aliases: ["shellfish", "mollusks", "clams", "mussels", "oysters", "scallops", "squid", "octopus"]),
        PreferenceOption(id: "allergen.wheat", name: "Wheat"),
        PreferenceOption(id: "allergen.soy", name: "Soy", aliases: ["soya", "soybeans"]),
        PreferenceOption(id: "allergen.sesame", name: "Sesame", aliases: ["tahini"]),
        PreferenceOption(id: "allergen.mustard", name: "Mustard"),
        PreferenceOption(id: "allergen.celery", name: "Celery", aliases: ["celeriac"]),
        PreferenceOption(id: "allergen.lupin", name: "Lupin", aliases: ["lupine"])
    ]
    static let restrictionOptions = [
        PreferenceOption(id: "gluten_free", name: "Gluten-free", aliases: ["gluten", "celiac", "coeliac"]),
        PreferenceOption(id: "dairy_free", name: "Dairy-free", aliases: ["milk"]),
        PreferenceOption(id: "lactose_free", name: "Lactose-free", aliases: ["lactose intolerance"]),
        PreferenceOption(id: "halal", name: "Halal"),
        PreferenceOption(id: "kosher", name: "Kosher"),
        PreferenceOption(id: "no_pork", name: "No pork"),
        PreferenceOption(id: "no_alcohol", name: "No alcohol")
    ]
    static let equipmentOptions = [
        PreferenceOption(id: "oven", name: "Oven"), PreferenceOption(id: "microwave", name: "Microwave"),
        PreferenceOption(id: "air_fryer", name: "Air fryer"), PreferenceOption(id: "blender", name: "Blender"),
        PreferenceOption(id: "food_processor", name: "Food processor"), PreferenceOption(id: "stand_mixer", name: "Stand mixer"),
        PreferenceOption(id: "hand_mixer", name: "Hand mixer"), PreferenceOption(id: "dutch_oven", name: "Dutch oven", aliases: ["casserole pot"]),
        PreferenceOption(id: "skillet", name: "Skillet", aliases: ["frying pan"]), PreferenceOption(id: "saucepan", name: "Saucepan"),
        PreferenceOption(id: "wok", name: "Wok"), PreferenceOption(id: "baking_trays", name: "Baking trays", aliases: ["baking sheets", "sheet pan"]),
        PreferenceOption(id: "thermometer", name: "Thermometer"), PreferenceOption(id: "rice_cooker", name: "Rice cooker"),
        PreferenceOption(id: "pressure_cooker", name: "Pressure cooker", aliases: ["Instant Pot"])
    ]
}

enum AllergyStatus: String, Codable { case unspecified, noneKnown, selected }

struct CookProfile: Codable, Equatable {
    var onboardingComplete = false
    var diet = "Everything"
    var allergyIDs: Set<String> = []
    var restrictionIDs: Set<String> = []
    var dislikedFoodIDs: Set<String> = []
    var equipmentIDs: Set<String> = []
    var allergyStatus = AllergyStatus.unspecified
    var spice = "Medium"
    var salt = "Balanced"
    var experience = "Home cook"
    var servings = 2
    var householdSize = 2
    var units = "Metric"
    var voiceLanguage = "English"
    var keepAwake = true
    var gentleGuidance = true
    // Preserve earlier free text for both the user and AI until the user explicitly reviews it.
    var previousPreferencesPendingReview: [String: String] = [:]

    func selectedIDs(_ section: PreferenceSection) -> Set<String> {
        switch section {
        case .allergies: allergyIDs
        case .restrictions: restrictionIDs
        case .dislikes: dislikedFoodIDs
        case .equipment: equipmentIDs
        }
    }
    mutating func select(_ ids: Set<String>, for section: PreferenceSection) {
        switch section {
        case .allergies: allergyIDs = ids; allergyStatus = ids.isEmpty ? .unspecified : .selected
        case .restrictions: restrictionIDs = ids
        case .dislikes: dislikedFoodIDs = ids
        case .equipment: equipmentIDs = ids
        }
    }
    mutating func setNoKnownAllergies() { allergyIDs = []; allergyStatus = .noneKnown }
    var needsPreferenceReview: Bool { !previousPreferencesPendingReview.isEmpty }
    init() {}

    private enum CodingKeys: String, CodingKey {
        case profileVersion, onboardingComplete, diet, allergyIDs, restrictionIDs, dislikedFoodIDs, equipmentIDs, allergyStatus
        case spice, salt, experience, servings, householdSize, units, voiceLanguage, keepAwake, gentleGuidance, previousPreferencesPendingReview
        case allergies, restrictions, dislikes, equipment
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboardingComplete = try c.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        diet = try c.decodeIfPresent(String.self, forKey: .diet) ?? "Everything"
        allergyIDs = try c.decodeIfPresent(Set<String>.self, forKey: .allergyIDs) ?? []
        restrictionIDs = try c.decodeIfPresent(Set<String>.self, forKey: .restrictionIDs) ?? []
        dislikedFoodIDs = try c.decodeIfPresent(Set<String>.self, forKey: .dislikedFoodIDs) ?? []
        equipmentIDs = try c.decodeIfPresent(Set<String>.self, forKey: .equipmentIDs) ?? []
        allergyStatus = try c.decodeIfPresent(AllergyStatus.self, forKey: .allergyStatus) ?? .unspecified
        if !allergyIDs.isEmpty { allergyStatus = .selected }
        if allergyIDs.isEmpty && allergyStatus == .selected { allergyStatus = .unspecified }
        spice = try c.decodeIfPresent(String.self, forKey: .spice) ?? "Medium"
        salt = try c.decodeIfPresent(String.self, forKey: .salt) ?? "Balanced"
        experience = try c.decodeIfPresent(String.self, forKey: .experience) ?? "Home cook"
        servings = try c.decodeIfPresent(Int.self, forKey: .servings) ?? 2
        householdSize = try c.decodeIfPresent(Int.self, forKey: .householdSize) ?? 2
        units = try c.decodeIfPresent(String.self, forKey: .units) ?? "Metric"
        voiceLanguage = try c.decodeIfPresent(String.self, forKey: .voiceLanguage) ?? "English"
        keepAwake = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        gentleGuidance = try c.decodeIfPresent(Bool.self, forKey: .gentleGuidance) ?? true
        previousPreferencesPendingReview = try c.decodeIfPresent([String: String].self, forKey: .previousPreferencesPendingReview) ?? [:]
        if try c.decodeIfPresent(Int.self, forKey: .profileVersion) == nil {
            for key in [CodingKeys.allergies, .dislikes, .equipment] {
                if let old = try c.decodeIfPresent(String.self, forKey: key), !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    previousPreferencesPendingReview[key.rawValue] = old
                }
            }
            if diet == "Other" { previousPreferencesPendingReview["diet"] = diet; diet = "Everything" }
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(2, forKey: .profileVersion)
        try c.encode(onboardingComplete, forKey: .onboardingComplete)
        try c.encode(diet, forKey: .diet)
        try c.encode(allergyIDs.sorted(), forKey: .allergyIDs)
        try c.encode(restrictionIDs.sorted(), forKey: .restrictionIDs)
        try c.encode(dislikedFoodIDs.sorted(), forKey: .dislikedFoodIDs)
        try c.encode(equipmentIDs.sorted(), forKey: .equipmentIDs)
        try c.encode(allergyStatus, forKey: .allergyStatus)
        try c.encode(spice, forKey: .spice)
        try c.encode(salt, forKey: .salt)
        try c.encode(experience, forKey: .experience)
        try c.encode(servings, forKey: .servings)
        try c.encode(householdSize, forKey: .householdSize)
        try c.encode(units, forKey: .units)
        try c.encode(voiceLanguage, forKey: .voiceLanguage)
        try c.encode(keepAwake, forKey: .keepAwake)
        try c.encode(gentleGuidance, forKey: .gentleGuidance)
        try c.encode(previousPreferencesPendingReview, forKey: .previousPreferencesPendingReview)
        // The same Firebase payload goes to import, question and voice agents: include readable labels.
        try c.encode(PreferenceSection.allergies.names(allergyIDs), forKey: .allergies)
        try c.encode(PreferenceSection.restrictions.names(restrictionIDs), forKey: .restrictions)
        try c.encode(PreferenceSection.dislikes.names(dislikedFoodIDs), forKey: .dislikes)
        try c.encode(PreferenceSection.equipment.names(equipmentIDs), forKey: .equipment)
    }
}
