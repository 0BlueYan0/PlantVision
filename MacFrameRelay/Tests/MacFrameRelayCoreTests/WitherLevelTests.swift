import Foundation
import Testing
@testable import MacFrameRelayCore

@Test
func witherLevelHealthyBelowFirstThreshold() {
    #expect(WitherLevel.level(forRatio: 0.0) == WitherLevel.healthy)
    #expect(WitherLevel.level(forRatio: 0.09) == WitherLevel.healthy)
}

@Test
func witherLevelMildInLowBand() {
    #expect(WitherLevel.level(forRatio: 0.10) == WitherLevel.mild)
    #expect(WitherLevel.level(forRatio: 0.34) == WitherLevel.mild)
}

@Test
func witherLevelModerateInMidBand() {
    #expect(WitherLevel.level(forRatio: 0.35) == WitherLevel.moderate)
    #expect(WitherLevel.level(forRatio: 0.64) == WitherLevel.moderate)
}

@Test
func witherLevelSevereInHighBand() {
    #expect(WitherLevel.level(forRatio: 0.65) == WitherLevel.severe)
    #expect(WitherLevel.level(forRatio: 1.0) == WitherLevel.severe)
}

@Test
func witherLevelsAreMonotonicWithRatio() {
    // 比例越高，等級不應下降（單調不遞減）
    let ratios = stride(from: 0.0, through: 1.0, by: 0.05)
    var previous = WitherLevel.level(forRatio: 0.0)
    for ratio in ratios {
        let level = WitherLevel.level(forRatio: ratio)
        #expect(level >= previous)
        previous = level
    }
}
