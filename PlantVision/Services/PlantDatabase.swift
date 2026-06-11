import Foundation

enum PlantDatabase {
    static let plants: [Plant] = [
        Plant(
            id: "lobelia-erinus",
            chineseName: "六倍利",
            scientificName: "Lobelia erinus",
            family: "桔梗科 Campanulaceae",
            genus: "Lobelia",
            origin: "南非",
            morphology: ["株型低矮叢生", "葉片小而互生", "唇形花冠", "花色藍紫、粉或白"],
            careAdvice: ["喜全日照至半日照", "涼爽季節生長旺盛", "保持介質濕潤", "花後修剪促進分枝"],
            demoConfidence: 0.92
        ),
        Plant(
            id: "catharanthus-roseus",
            chineseName: "日日春",
            scientificName: "Catharanthus roseus",
            family: "夾竹桃科 Apocynaceae",
            genus: "Catharanthus",
            origin: "馬達加斯加",
            morphology: ["葉對生橢圓形", "葉面光亮深綠", "五瓣花全年開放", "花色粉紅、紫紅或白"],
            careAdvice: ["喜高溫與充足日照", "耐旱不耐積水", "土表乾燥再澆水", "全株具毒性避免誤食"],
            demoConfidence: 0.9
        )
    ]

    static let primaryPlant = plants[0]

    static func plant(id: String) -> Plant? {
        plants.first { $0.id == id }
    }
}
