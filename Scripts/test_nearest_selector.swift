import simd
import Foundation

@main
enum NearestPartSelectorTests {
    static func main() {
        var fail = 0
        func check(_ c: Bool, _ m: String) { if !c { print("FAIL: \(m)"); fail += 1 } }
        let head = SIMD3<Float>(0, 0, 0)

        check(NearestPartSelector.select(candidatesWorld: [], headWorld: head, current: nil, switchMargin: 0.05) == nil,
              "空候選回 nil")
        let pts = [SIMD3<Float>(1,0,0), SIMD3<Float>(0.2,0,0), SIMD3<Float>(2,0,0)]
        check(NearestPartSelector.select(candidatesWorld: pts, headWorld: head, current: nil, switchMargin: 0.05) == 1,
              "首次選最近=1")
        let near = [SIMD3<Float>(1,0,0), SIMD3<Float>(0.98,0,0)]
        check(NearestPartSelector.select(candidatesWorld: near, headWorld: head, current: 0, switchMargin: 0.05) == 0,
              "差<margin 維持目前=0")
        let far = [SIMD3<Float>(1,0,0), SIMD3<Float>(0.5,0,0)]
        check(NearestPartSelector.select(candidatesWorld: far, headWorld: head, current: 0, switchMargin: 0.05) == 1,
              "差>margin 換手=1")
        check(NearestPartSelector.select(candidatesWorld: far, headWorld: head, current: 99, switchMargin: 0.05) == 1,
              "越界 current 重新挑=1")

        if fail == 0 { print("ALL TESTS PASSED") } else { exit(1) }
    }
}
