import XCTest
import SwiftUI
import UIKit
import QingJiCore
@testable import QingJi

final class BudgetPresentationTests: XCTestCase {
    func testCurrentMonthFollowsDateChangeAndHistoricalSelectionStays() {
        let december = BudgetCivilDay(year: 2026, month: 12, day: 31)
        let january = BudgetCivilDay(year: 2027, month: 1, day: 1)
        XCTAssertEqual(BudgetMonthNavigation.refreshedMonthIndex(displayed: december.monthIndex,
                                                                previousToday: december, currentToday: january),
                       january.monthIndex)
        let historical = BudgetCivilDay(year: 2026, month: 8, day: 1).monthIndex
        XCTAssertEqual(BudgetMonthNavigation.refreshedMonthIndex(displayed: historical,
                                                                previousToday: december, currentToday: january),
                       historical)
        XCTAssertEqual(BudgetMonthNavigation.refreshedMonthIndex(displayed: december.monthIndex,
                                                                previousToday: december, currentToday: december),
                       december.monthIndex)
    }

    func testSavedFortyPercentOpacityIsPreserved() {
        let preferences = AppThemePreferences(presetKey: "pink", intensity: 0.6, cardAlpha: 0.4)
        XCTAssertEqual(preferences.preset, .pink)
        XCTAssertEqual(preferences.intensity, 0.6)
        XCTAssertEqual(preferences.cardAlpha, 0.4)
        let dark = AppThemePalette(preferences: preferences, colorScheme: .dark)
        XCTAssertEqual(UIColor(dark.card).cgColor.alpha, 0.55, accuracy: 0.001)
    }

    func testNightOverridesAppearanceWithoutChangingOtherPresets() {
        let night = AppThemePreferences(presetKey: "night", intensity: 1, cardAlpha: 0.8)
        XCTAssertEqual(night.colorScheme(appearanceMode: .light), .dark)
        let white = AppThemePreferences(presetKey: "white", intensity: 1, cardAlpha: 0.4)
        XCTAssertEqual(white.colorScheme(appearanceMode: .light), .light)
        XCTAssertNil(white.colorScheme(appearanceMode: .system))
        XCTAssertEqual(AppThemePreset.allCases.map(\.rawValue), ["warm", "white", "pink", "mint", "blue", "night"])
    }

    func testInvalidPreferencesFallBackAndThemeInputsRemainVisible() {
        let invalid = AppThemePreferences(presetKey: "missing", intensity: .nan, cardAlpha: .infinity)
        XCTAssertEqual(invalid.preset, .warm)
        XCTAssertEqual(invalid.intensity, 1)
        XCTAssertEqual(invalid.cardAlpha, AppThemePreferences.defaultCardAlpha)
        for preset in AppThemePreset.allCases {
            let preferences = AppThemePreferences(presetKey: preset.rawValue, intensity: 1, cardAlpha: 0.4)
            let theme = AppThemePalette(preferences: preferences, colorScheme: .light)
            XCTAssertNotEqual(UIColor(theme.fill), UIColor(theme.sheet), preset.rawValue)
        }
    }

    func testNightBackgroundUsesItsTopColorAndIntensity() {
        let full = AppThemePalette(preferences: AppThemePreferences(presetKey: "night", intensity: 1, cardAlpha: 0.4),
                                   colorScheme: .dark)
        let flat = AppThemePalette(preferences: AppThemePreferences(presetKey: "night", intensity: 0, cardAlpha: 0.4),
                                   colorScheme: .dark)
        XCTAssertEqual(UIColor(full.backgroundTop), AppThemePreset.night.top)
        XCTAssertEqual(UIColor(full.backgroundBottom), AppThemePreset.night.bottom)
        XCTAssertEqual(UIColor(flat.backgroundTop), UIColor(flat.backgroundBottom))
        XCTAssertNotEqual(UIColor(full.backgroundTop), UIColor(flat.backgroundTop))
    }

    func testLightSegmentTrackUsesThemeInkAndSelectedWhite() {
        for preset in AppThemePreset.allCases where preset != .night {
            for intensity in [0.0, 0.6, 1.0] {
                let theme = AppThemePalette(preferences: AppThemePreferences(presetKey: preset.rawValue,
                                                                            intensity: intensity, cardAlpha: 0.4),
                                            colorScheme: .light)
                var topR: CGFloat = 0, topG: CGFloat = 0, topB: CGFloat = 0, topA: CGFloat = 0
                var bottomR: CGFloat = 0, bottomG: CGFloat = 0, bottomB: CGFloat = 0, bottomA: CGFloat = 0
                XCTAssertTrue(preset.top.getRed(&topR, green: &topG, blue: &topB, alpha: &topA))
                XCTAssertTrue(preset.bottom.getRed(&bottomR, green: &bottomG, blue: &bottomB, alpha: &bottomA))
                let amount = CGFloat(intensity)
                assertColor(theme.segmentTrack,
                            red: (bottomR + (topR - bottomR) * amount) * 0.45,
                            green: (bottomG + (topG - bottomG) * amount) * 0.45,
                            blue: (bottomB + (topB - bottomB) * amount) * 0.45, alpha: 0.12)
                assertColor(theme.segmentSelected, red: 1, green: 1, blue: 1, alpha: 0.65)
                XCTAssertNotEqual(UIColor(theme.segmentTrack), UIColor(theme.fill), preset.rawValue)
            }
        }
    }

    func testDarkAndNightSegmentsUseWhiteTrackAndWarmGraySelection() {
        for (preset, scheme) in [(AppThemePreset.warm, ColorScheme.dark), (.night, .dark), (.night, .light)] {
            let theme = AppThemePalette(preferences: AppThemePreferences(presetKey: preset.rawValue,
                                                                        intensity: 0.6, cardAlpha: 0.4),
                                        colorScheme: scheme)
            assertColor(theme.segmentTrack, red: 1, green: 1, blue: 1, alpha: 0.08)
            assertColor(theme.segmentSelected, red: CGFloat(0x4A) / 255, green: CGFloat(0x45) / 255,
                        blue: CGFloat(0x40) / 255, alpha: 0.75)
        }
    }

    private func assertColor(_ color: Color, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat,
                             file: StaticString = #filePath, line: UInt = #line) {
        var actualR: CGFloat = 0, actualG: CGFloat = 0, actualB: CGFloat = 0, actualA: CGFloat = 0
        XCTAssertTrue(UIColor(color).getRed(&actualR, green: &actualG, blue: &actualB, alpha: &actualA),
                      file: file, line: line)
        XCTAssertEqual(actualR, red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualG, green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualB, blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualA, alpha, accuracy: 0.001, file: file, line: line)
    }
}
