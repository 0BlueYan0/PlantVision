import Foundation

enum PlantDatabase {
    static let plants: [Plant] = [
        Plant(
            id: "monstera-deliciosa",
            chineseName: "龜背芋",
            scientificName: "Monstera deliciosa",
            family: "天南星科 Araceae",
            genus: "Monstera",
            origin: "墨西哥至中美洲熱帶雨林",
            morphology: ["葉片具裂孔", "葉形寬大", "葉脈清楚", "攀附型氣生根"],
            careAdvice: ["明亮散射光", "保持土壤微濕", "避免長時間積水", "提供攀附支架"],
            demoConfidence: 0.95
        ),
        Plant(
            id: "epipremnum-aureum",
            chineseName: "黃金葛",
            scientificName: "Epipremnum aureum",
            family: "天南星科 Araceae",
            genus: "Epipremnum",
            origin: "法屬玻里尼西亞",
            morphology: ["心形葉", "黃綠斑紋", "蔓性生長", "節點易生根"],
            careAdvice: ["耐半陰", "土表乾燥後澆水", "定期修剪蔓枝", "避免強烈直射光"],
            demoConfidence: 0.9
        ),
        Plant(
            id: "sansevieria-trifasciata",
            chineseName: "虎尾蘭",
            scientificName: "Dracaena trifasciata",
            family: "天門冬科 Asparagaceae",
            genus: "Dracaena",
            origin: "西非熱帶地區",
            morphology: ["直立劍形葉", "深淺綠橫紋", "厚實多肉質葉", "株型緊湊"],
            careAdvice: ["少量澆水", "可接受低光", "使用排水良好介質", "冬季減少澆水"],
            demoConfidence: 0.88
        )
    ]

    static let primaryPlant = plants[0]

    static func plant(id: String) -> Plant? {
        plants.first { $0.id == id }
    }
}
