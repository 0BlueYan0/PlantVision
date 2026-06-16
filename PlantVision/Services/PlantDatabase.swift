import Foundation

enum PlantDatabase {
    static let plants: [Plant] = [
        Plant(
            id: "pelargonium-hortorum",
            chineseName: "天竺葵",
            scientificName: "Pelargonium × hortorum",
            family: "牻牛兒苗科 Geraniaceae",
            genus: "Pelargonium",
            origin: "南非",
            morphology: ["莖肉質、基部漸木質化", "葉互生圓腎形、常具暗色環狀斑紋", "葉緣鈍鋸齒、揉之有特殊氣味", "繖形花序、花色紅粉白或雙色"],
            careAdvice: ["喜全日照至半日照、光線足花量多", "喜涼爽乾燥、忌高溫高濕悶熱", "土表乾再澆水、避免積水爛根", "花後摘除殘花並修剪徒長枝"],
            flowerNote: "繖形花序聚生於長梗頂端，花色紅、粉、白或雙色",
            leafNote: "葉圓腎形、互生，葉面常具暗色環狀斑紋，揉之有特殊氣味",
            demoConfidence: 0.92
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
