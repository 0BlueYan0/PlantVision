import Foundation
import Testing
@testable import MacFrameRelayCore

@Test
func yellowingLevelNoneBelowFirstThreshold() {
    #expect(LeafYellowingLevel.level(forRatio: 0.0) == LeafYellowingLevel.none)
    #expect(LeafYellowingLevel.level(forRatio: 0.14) == LeafYellowingLevel.none)
}

@Test
func yellowingLevelMildInLowBand() {
    #expect(LeafYellowingLevel.level(forRatio: 0.15) == LeafYellowingLevel.mild)
    #expect(LeafYellowingLevel.level(forRatio: 0.34) == LeafYellowingLevel.mild)
}

@Test
func yellowingLevelModerateInMidBand() {
    #expect(LeafYellowingLevel.level(forRatio: 0.35) == LeafYellowingLevel.moderate)
    #expect(LeafYellowingLevel.level(forRatio: 0.59) == LeafYellowingLevel.moderate)
}

@Test
func yellowingLevelSevereInHighBand() {
    #expect(LeafYellowingLevel.level(forRatio: 0.60) == LeafYellowingLevel.severe)
    #expect(LeafYellowingLevel.level(forRatio: 1.0) == LeafYellowingLevel.severe)
}

@Test
func yellowingLevelsAreMonotonicWithRatio() {
    let ratios = stride(from: 0.0, through: 1.0, by: 0.05)
    var previous = LeafYellowingLevel.level(forRatio: 0.0)
    for ratio in ratios {
        let level = LeafYellowingLevel.level(forRatio: ratio)
        #expect(level >= previous)
        previous = level
    }
}
