import Foundation

// MARK: - Log Entry Types
enum LogType: String, CaseIterable, Codable {
    case weight = "weight"
    case workout = "workout"
    case food = "food"
    case water = "water"
    case sleep = "sleep"

    var displayName: String {
        switch self {
        case .weight: return "Weight"
        case .workout: return "Workout"
        case .food: return "Food"
        case .water: return "Water"
        case .sleep: return "Sleep"
        }
    }

    var icon: String {
        switch self {
        case .weight: return "scalemass"
        case .workout: return "figure.run"
        case .food: return "fork.knife"
        case .water: return "drop.fill"
        case .sleep: return "bed.double.fill"
        }
    }
}

// MARK: - Weight Log Entry
struct WeightLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let time: Date
    let weight: Double
    let unit: WeightUnit
    let userId: String
    
    init(weight: Double, unit: WeightUnit, userId: String, date: Date = Date(), time: Date = Date()) {
        self.id = UUID().uuidString
        self.date = date
        self.time = time
        self.weight = weight
        self.unit = unit
        self.userId = userId
    }
    
    // Computed property for backward compatibility
    var timestamp: Date {
        Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: time),
                            minute: Calendar.current.component(.minute, from: time),
                            second: 0,
                            of: date) ?? date
    }
}

enum WeightUnit: String, CaseIterable, Codable {
    case pounds = "lbs"
    case kilograms = "kg"
    
    var displayName: String {
        switch self {
        case .pounds: return "lbs"
        case .kilograms: return "kg"
        }
    }
}

// MARK: - Workout Type
enum WorkoutType: String, CaseIterable, Codable, Identifiable {
    case archery = "archery"
    case badminton = "badminton"
    case barre = "barre"
    case baseball = "baseball"
    case basketball = "basketball"
    case bowling = "bowling"
    case boxing = "boxing"
    case climbing = "climbing"
    case cooldown = "cooldown"
    case coreTraining = "core_training"
    case cricket = "cricket"
    case crossTraining = "cross_training"
    case curling = "curling"
    case cycling = "cycling"
    case dance = "dance"
    case discSports = "disc_sports"
    case elliptical = "elliptical"
    case equestrianSports = "equestrian_sports"
    case fencing = "fencing"
    case fishing = "fishing"
    case fitnessGaming = "fitness_gaming"
    case flexibility = "flexibility"
    case americanFootball = "american_football"
    case australianFootball = "australian_football"
    case functionalStrengthTraining = "functional_strength_training"
    case golf = "golf"
    case gymnastics = "gymnastics"
    case handCycling = "hand_cycling"
    case handball = "handball"
    case hiit = "hiit"
    case hiking = "hiking"
    case hockey = "hockey"
    case hunting = "hunting"
    case jumpRope = "jump_rope"
    case kickboxing = "kickboxing"
    case lacrosse = "lacrosse"
    case martialArts = "martial_arts"
    case mindAndBody = "mind_and_body"
    case mixedCardio = "mixed_cardio"
    case multisport = "multisport"
    case paddling = "paddling"
    case pickleball = "pickleball"
    case pilates = "pilates"
    case play = "play"
    case racquetball = "racquetball"
    case rolling = "rolling"
    case rowing = "rowing"
    case rugby = "rugby"
    case running = "running"
    case sailing = "sailing"
    case skating = "skating"
    case crossCountrySkiing = "cross_country_skiing"
    case downhillSkiing = "downhill_skiing"
    case snowSports = "snow_sports"
    case snowboarding = "snowboarding"
    case soccer = "soccer"
    case socialDance = "social_dance"
    case softball = "softball"
    case squash = "squash"
    case stairStepper = "stair_stepper"
    case stairs = "stairs"
    case stepTraining = "step_training"
    case surfing = "surfing"
    case swimming = "swimming"
    case tableTennis = "table_tennis"
    case taiChi = "tai_chi"
    case tennis = "tennis"
    case trackAndField = "track_and_field"
    case traditionalStrengthTraining = "traditional_strength_training"
    case volleyball = "volleyball"
    case walking = "walking"
    case waterFitness = "water_fitness"
    case waterPolo = "water_polo"
    case waterSports = "water_sports"
    case wheelchair = "wheelchair"
    case wrestling = "wrestling"
    case yoga = "yoga"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .archery: return "Archery"
        case .badminton: return "Badminton"
        case .barre: return "Barre"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .bowling: return "Bowling"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .cooldown: return "Cooldown"
        case .coreTraining: return "Core Training"
        case .cricket: return "Cricket"
        case .crossTraining: return "Cross Training"
        case .curling: return "Curling"
        case .cycling: return "Cycling"
        case .dance: return "Dance"
        case .discSports: return "Disc Sports"
        case .elliptical: return "Elliptical"
        case .equestrianSports: return "Equestrian Sports"
        case .fencing: return "Fencing"
        case .fishing: return "Fishing"
        case .fitnessGaming: return "Fitness Gaming"
        case .flexibility: return "Flexibility"
        case .americanFootball: return "American Football"
        case .australianFootball: return "Australian Football"
        case .functionalStrengthTraining: return "Functional Strength Training"
        case .golf: return "Golf"
        case .gymnastics: return "Gymnastics"
        case .handCycling: return "Hand Cycling"
        case .handball: return "Handball"
        case .hiit: return "HIIT"
        case .hiking: return "Hiking"
        case .hockey: return "Hockey"
        case .hunting: return "Hunting"
        case .jumpRope: return "Jump Rope"
        case .kickboxing: return "Kickboxing"
        case .lacrosse: return "Lacrosse"
        case .martialArts: return "Martial Arts"
        case .mindAndBody: return "Mind & Body"
        case .mixedCardio: return "Mixed Cardio"
        case .multisport: return "Multisport"
        case .paddling: return "Paddling"
        case .pickleball: return "Pickleball"
        case .pilates: return "Pilates"
        case .play: return "Play"
        case .racquetball: return "Racquetball"
        case .rolling: return "Rolling"
        case .rowing: return "Rowing"
        case .rugby: return "Rugby"
        case .running: return "Running"
        case .sailing: return "Sailing"
        case .skating: return "Skating"
        case .crossCountrySkiing: return "Cross Country Skiing"
        case .downhillSkiing: return "Downhill Skiing"
        case .snowSports: return "Snow Sports"
        case .snowboarding: return "Snowboarding"
        case .soccer: return "Soccer"
        case .socialDance: return "Social Dance"
        case .softball: return "Softball"
        case .squash: return "Squash"
        case .stairStepper: return "Stair Stepper"
        case .stairs: return "Stairs"
        case .stepTraining: return "Step Training"
        case .surfing: return "Surfing"
        case .swimming: return "Swimming"
        case .tableTennis: return "Table Tennis"
        case .taiChi: return "Tai Chi"
        case .tennis: return "Tennis"
        case .trackAndField: return "Track & Field"
        case .traditionalStrengthTraining: return "Traditional Strength Training"
        case .volleyball: return "Volleyball"
        case .walking: return "Walking"
        case .waterFitness: return "Water Fitness"
        case .waterPolo: return "Water Polo"
        case .waterSports: return "Water Sports"
        case .wheelchair: return "Wheelchair"
        case .wrestling: return "Wrestling"
        case .yoga: return "Yoga"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .archery: return "figure.archery"
        case .badminton: return "figure.badminton"
        case .barre: return "figure.barre"
        case .baseball: return "figure.baseball"
        case .basketball: return "figure.basketball"
        case .bowling: return "figure.bowling"
        case .boxing: return "figure.boxing"
        case .climbing: return "figure.climbing"
        case .cooldown: return "figure.cooldown"
        case .coreTraining: return "figure.core.training"
        case .cricket: return "figure.cricket"
        case .crossTraining: return "figure.cross.training"
        case .curling: return "figure.curling"
        case .cycling: return "bicycle"
        case .dance: return "figure.dance"
        case .discSports: return "figure.disc.sports"
        case .elliptical: return "figure.elliptical"
        case .equestrianSports: return "figure.equestrian.sports"
        case .fencing: return "figure.fencing"
        case .fishing: return "figure.fishing"
        case .fitnessGaming: return "gamecontroller.fill"
        case .flexibility: return "figure.flexibility"
        case .americanFootball: return "figure.american.football"
        case .australianFootball: return "figure.australian.football"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .golf: return "figure.golf"
        case .gymnastics: return "figure.gymnastics"
        case .handCycling: return "figure.hand.cycling"
        case .handball: return "figure.handball"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .hiking: return "figure.hiking"
        case .hockey: return "figure.hockey"
        case .hunting: return "figure.hunting"
        case .jumpRope: return "figure.jumprope"
        case .kickboxing: return "figure.kickboxing"
        case .lacrosse: return "figure.lacrosse"
        case .martialArts: return "figure.martial.arts"
        case .mindAndBody: return "figure.mind.and.body"
        case .mixedCardio: return "figure.mixed.cardio"
        case .multisport: return "figure.run"
        case .paddling: return "figure.rower"
        case .pickleball: return "figure.pickleball"
        case .pilates: return "figure.pilates"
        case .play: return "figure.play"
        case .racquetball: return "figure.racquetball"
        case .rolling: return "figure.rolling"
        case .rowing: return "figure.rower"
        case .rugby: return "figure.rugby"
        case .running: return "figure.run"
        case .sailing: return "figure.sailing"
        case .skating: return "figure.skating"
        case .crossCountrySkiing: return "figure.skiing.crosscountry"
        case .downhillSkiing: return "figure.skiing.downhill"
        case .snowSports: return "snowflake"
        case .snowboarding: return "figure.snowboarding"
        case .soccer: return "figure.soccer"
        case .socialDance: return "figure.socialdance"
        case .softball: return "figure.softball"
        case .squash: return "figure.squash"
        case .stairStepper: return "figure.stair.stepper"
        case .stairs: return "figure.stairs"
        case .stepTraining: return "figure.step.training"
        case .surfing: return "figure.surfing"
        case .swimming: return "figure.pool.swim"
        case .tableTennis: return "figure.table.tennis"
        case .taiChi: return "figure.taichi"
        case .tennis: return "figure.tennis"
        case .trackAndField: return "figure.track.and.field"
        case .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .volleyball: return "figure.volleyball"
        case .walking: return "figure.walk"
        case .waterFitness: return "figure.water.fitness"
        case .waterPolo: return "figure.waterpolo"
        case .waterSports: return "figure.open.water.swim"
        case .wheelchair: return "figure.roll"
        case .wrestling: return "figure.wrestling"
        case .yoga: return "figure.yoga"
        case .other: return "figure.run"
        }
    }
}

// MARK: - Workout Log Entry
struct WorkoutLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let name: String
    let workoutTypeRaw: String?
    let userId: String
    let createdAt: Date

    init(date: Date, name: String, workoutType: WorkoutType, userId: String) {
        self.id = UUID().uuidString
        self.date = date
        self.name = name
        self.workoutTypeRaw = workoutType.rawValue
        self.userId = userId
        self.createdAt = Date()
    }

    init(id: String, date: Date, name: String, workoutTypeRaw: String?, userId: String, createdAt: Date) {
        self.id = id
        self.date = date
        self.name = name
        self.workoutTypeRaw = workoutTypeRaw
        self.userId = userId
        self.createdAt = createdAt
    }

    var workoutType: WorkoutType {
        if let raw = workoutTypeRaw, let type = WorkoutType(rawValue: raw) {
            return type
        }
        // Legacy entries stored type rawValue in name field
        if let type = WorkoutType(rawValue: name) {
            return type
        }
        return .other
    }

    var displayIcon: String {
        workoutType.icon
    }
}

// MARK: - Food Log Entry
struct FoodLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let name: String
    let userId: String
    let createdAt: Date

    init(date: Date, name: String, userId: String) {
        self.id = UUID().uuidString
        self.date = date
        self.name = name
        self.userId = userId
        self.createdAt = Date()
    }
}

// MARK: - Water Log Entry
struct WaterLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let cupsConsumed: Int
    let userId: String
    let createdAt: Date
    let updatedAt: Date

    init(date: Date, cupsConsumed: Int, userId: String) {
        self.id = UUID().uuidString
        self.date = date
        self.cupsConsumed = cupsConsumed
        self.userId = userId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(id: String, date: Date, cupsConsumed: Int, userId: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.date = date
        self.cupsConsumed = cupsConsumed
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Sleep Log Entry
struct SleepLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let wakeUpTime: Date?
    let bedTime: Date?
    let userId: String
    let createdAt: Date
    let updatedAt: Date

    init(date: Date, wakeUpTime: Date?, bedTime: Date?, userId: String) {
        self.id = UUID().uuidString
        self.date = date
        self.wakeUpTime = wakeUpTime
        self.bedTime = bedTime
        self.userId = userId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(id: String, date: Date, wakeUpTime: Date?, bedTime: Date?, userId: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.date = date
        self.wakeUpTime = wakeUpTime
        self.bedTime = bedTime
        self.userId = userId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var sleepDuration: TimeInterval? {
        guard let wake = wakeUpTime, let bed = bedTime else { return nil }
        // Calculate duration considering bed time might be on previous day
        if wake > bed {
            // Normal case: went to bed on previous day, woke up on current day
            return wake.timeIntervalSince(bed)
        } else {
            // Edge case: both times on same day (shouldn't normally happen)
            return bed.timeIntervalSince(wake) + 86400 // Add 24 hours
        }
    }

    var sleepDurationFormatted: String? {
        guard let duration = sleepDuration else { return nil }
        let decimalHours = duration / 3600
        return String(format: "%.1f h", decimalHours)
    }
}

// MARK: - Scrapbook Entry
struct ScrapbookEntry: Identifiable, Codable, Hashable {
    let id: String
    let date: Date
    let pdfURL: String // Local file URL or external URL
    let userId: String
    let accountKind: String
    let createdAt: Date
    let title: String?
    
    init(date: Date, pdfURL: String, userId: String, accountKind: GoogleAuthManager.AccountKind, title: String? = nil) {
        self.id = UUID().uuidString
        self.date = date
        self.pdfURL = pdfURL
        self.userId = userId
        self.accountKind = accountKind.rawValue
        self.createdAt = Date()
        self.title = title
    }
}

// MARK: - Log Entry Protocol
protocol LogEntry {
    var id: String { get }
    var date: Date { get }
    var userId: String { get }
}

extension WeightLogEntry: LogEntry {
    // date property is already defined in the struct
}

extension WorkoutLogEntry: LogEntry {}
extension FoodLogEntry: LogEntry {}
extension WaterLogEntry: LogEntry {}
extension SleepLogEntry: LogEntry {}
extension ScrapbookEntry: LogEntry {} 