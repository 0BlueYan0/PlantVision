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
            flowerNote: "唇形花冠，花色藍紫、粉或白",
            leafNote: "葉片小而互生，株型低矮叢生",
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
            flowerNote: "五瓣花全年開放，花色粉紅、紫紅或白",
            leafNote: "葉對生橢圓形，葉面光亮深綠",
            demoConfidence: 0.9
        ),
        Plant(
            id: "lantana-camara",
            chineseName: "馬纓丹",
            scientificName: "Lantana camara",
            family: "馬鞭草科 Verbenaceae",
            genus: "Lantana",
            origin: "熱帶美洲",
            morphology: ["莖方形常具逆刺", "葉對生卵形表面粗糙", "密集繖形花序", "花色由黃橙轉紅粉同序多色"],
            careAdvice: ["喜全日照與高溫", "耐旱排水需良好", "花後修剪促進開花", "全株含毒未熟果尤甚避免誤食"],
            flowerNote: "密集繖形花序，花色由黃橙轉紅粉、同一花序多色",
            leafNote: "葉對生卵形、表面粗糙具氣味，莖具逆刺",
            demoConfidence: 0.9
        )
    ]

    static let primaryPlant = plants[0]

    static func plant(id: String) -> Plant? {
        plants.first { $0.id == id }
    }
}
