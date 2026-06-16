import simd

/// 從候選點挑離使用者頭部最近的一個，帶遲滯避免在近等距點間抖動。
/// 純數學，不依賴 RealityKit/ARKit，可獨立單元測試。
enum NearestPartSelector {
    /// - candidatesWorld: 候選點世界座標
    /// - headWorld: 頭部世界座標
    /// - current: 目前選中 index（nil = 尚未選）
    /// - switchMargin: 另一候選需比目前選中近超過此距離(公尺)才換手
    /// - Returns: 新選中 index；候選為空回 nil
    static func select(candidatesWorld: [SIMD3<Float>],
                       headWorld: SIMD3<Float>,
                       current: Int?,
                       switchMargin: Float) -> Int? {
        guard !candidatesWorld.isEmpty else { return nil }
        var bestIndex = 0
        var bestDist = simd_distance(candidatesWorld[0], headWorld)
        for i in 1..<candidatesWorld.count {
            let d = simd_distance(candidatesWorld[i], headWorld)
            if d < bestDist { bestDist = d; bestIndex = i }
        }
        if let cur = current, cur >= 0, cur < candidatesWorld.count {
            let curDist = simd_distance(candidatesWorld[cur], headWorld)
            if curDist - bestDist <= switchMargin { return cur }
        }
        return bestIndex
    }
}
