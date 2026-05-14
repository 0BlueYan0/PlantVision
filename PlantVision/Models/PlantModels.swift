import Foundation

struct Plant: Identifiable, Equatable, Hashable {
    let id: String
    let chineseName: String
    let scientificName: String
    let family: String
    let genus: String
    let origin: String
    let morphology: [String]
    let careAdvice: [String]
    let demoConfidence: Double
}

enum GrowthStage: String, CaseIterable, Identifiable {
    case sprout
    case leafGrowth
    case flowering
    case mature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sprout: "發芽"
        case .leafGrowth: "長葉"
        case .flowering: "開花"
        case .mature: "成熟"
        }
    }

    var detail: String {
        switch self {
        case .sprout: "種子萌發，根系開始固定。"
        case .leafGrowth: "葉片展開，吸收光線與水分。"
        case .flowering: "植株進入開花或繁殖階段。"
        case .mature: "株型穩定，進入成熟觀察狀態。"
        }
    }

    var progress: Double {
        switch self {
        case .sprout: 0.2
        case .leafGrowth: 0.48
        case .flowering: 0.74
        case .mature: 1
        }
    }
}

struct RecognitionResult: Identifiable, Equatable {
    let id = UUID()
    let plant: Plant
    let confidence: Double
    let source: RecognitionSource
    let detectedAt: Date
    let note: String
}

enum RecognitionSource: String {
    case camera = "Vision Pro 主鏡頭"
    case demo = "Demo 樣本"
}

struct PlantHistoryRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let plantID: String
    let chineseName: String
    let scientificName: String
    let confidence: Double
    let source: String
    let createdAt: Date
}
