import Foundation

/// Baked-in migration presets: another app's defaults, keyed to our catalog.
/// Transcribed from rxhanson/Rectangle's spectacleDefault/alternateDefault tables.
enum WindowCommandPreset: String, CaseIterable, Sendable {
    case rectangle
    case spectacle
    case magnet

    struct Entry: Sendable {
        let command: WindowCommand.ID
        let keyCode: Int
        let carbonModifiers: Int
    }

    // HIToolbox values, restated so this file stays Foundation-only.
    private static let ctrl = 1 << 12
    private static let opt = 1 << 11
    private static let shift = 1 << 9
    private static let cmd = 1 << 8

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .spectacle: return "Spectacle"
        case .magnet: return "Magnet"
        }
    }

    var entries: [Entry] {
        switch self {
        case .rectangle: return Self.rectangleEntries
        case .spectacle: return Self.spectacleEntries
        case .magnet: return Self.magnetEntries
        }
    }

    private static let rectangleEntries: [Entry] = [
        Entry(command: .leftHalf, keyCode: 123, carbonModifiers: ctrl | opt),
        Entry(command: .rightHalf, keyCode: 124, carbonModifiers: ctrl | opt),
        Entry(command: .topHalf, keyCode: 126, carbonModifiers: ctrl | opt),
        Entry(command: .bottomHalf, keyCode: 125, carbonModifiers: ctrl | opt),
        Entry(command: .topLeftQuarter, keyCode: 32, carbonModifiers: ctrl | opt),
        Entry(command: .topRightQuarter, keyCode: 34, carbonModifiers: ctrl | opt),
        Entry(command: .bottomLeftQuarter, keyCode: 38, carbonModifiers: ctrl | opt),
        Entry(command: .bottomRightQuarter, keyCode: 40, carbonModifiers: ctrl | opt),
        Entry(command: .maximize, keyCode: 36, carbonModifiers: ctrl | opt),
        Entry(command: .center, keyCode: 8, carbonModifiers: ctrl | opt),
        Entry(command: .restore, keyCode: 51, carbonModifiers: ctrl | opt),
        Entry(command: .firstThird, keyCode: 2, carbonModifiers: ctrl | opt),
        Entry(command: .centerThird, keyCode: 3, carbonModifiers: ctrl | opt),
        Entry(command: .lastThird, keyCode: 5, carbonModifiers: ctrl | opt),
        Entry(command: .firstTwoThirds, keyCode: 14, carbonModifiers: ctrl | opt),
        Entry(command: .lastTwoThirds, keyCode: 17, carbonModifiers: ctrl | opt),
        Entry(command: .centerTwoThirds, keyCode: 15, carbonModifiers: ctrl | opt),
        Entry(command: .makeLarger, keyCode: 24, carbonModifiers: ctrl | opt),
        Entry(command: .makeSmaller, keyCode: 27, carbonModifiers: ctrl | opt),
        Entry(command: .maximizeHeight, keyCode: 126, carbonModifiers: ctrl | opt | shift),
        Entry(command: .previousDisplay, keyCode: 123, carbonModifiers: ctrl | opt | cmd),
        Entry(command: .nextDisplay, keyCode: 124, carbonModifiers: ctrl | opt | cmd),
    ]

    private static let spectacleEntries: [Entry] = [
        Entry(command: .leftHalf, keyCode: 123, carbonModifiers: cmd | opt),
        Entry(command: .rightHalf, keyCode: 124, carbonModifiers: cmd | opt),
        Entry(command: .topHalf, keyCode: 126, carbonModifiers: cmd | opt),
        Entry(command: .bottomHalf, keyCode: 125, carbonModifiers: cmd | opt),
        Entry(command: .topLeftQuarter, keyCode: 123, carbonModifiers: ctrl | cmd),
        Entry(command: .topRightQuarter, keyCode: 124, carbonModifiers: ctrl | cmd),
        Entry(command: .bottomLeftQuarter, keyCode: 123, carbonModifiers: ctrl | cmd | shift),
        Entry(command: .bottomRightQuarter, keyCode: 124, carbonModifiers: ctrl | cmd | shift),
        Entry(command: .maximize, keyCode: 3, carbonModifiers: cmd | opt),
        Entry(command: .center, keyCode: 8, carbonModifiers: cmd | opt),
        Entry(command: .restore, keyCode: 51, carbonModifiers: ctrl | opt),
        Entry(command: .makeLarger, keyCode: 124, carbonModifiers: ctrl | opt | shift),
        Entry(command: .makeSmaller, keyCode: 123, carbonModifiers: ctrl | opt | shift),
        Entry(command: .maximizeHeight, keyCode: 126, carbonModifiers: ctrl | opt | shift),
        Entry(command: .previousDisplay, keyCode: 123, carbonModifiers: ctrl | opt | cmd),
        Entry(command: .nextDisplay, keyCode: 124, carbonModifiers: ctrl | opt | cmd),
    ]

    private static let magnetEntries: [Entry] = [
        Entry(command: .leftHalf, keyCode: 123, carbonModifiers: ctrl | opt),
        Entry(command: .rightHalf, keyCode: 124, carbonModifiers: ctrl | opt),
        Entry(command: .topHalf, keyCode: 126, carbonModifiers: ctrl | opt),
        Entry(command: .bottomHalf, keyCode: 125, carbonModifiers: ctrl | opt),
        Entry(command: .topLeftQuarter, keyCode: 32, carbonModifiers: ctrl | opt),
        Entry(command: .topRightQuarter, keyCode: 34, carbonModifiers: ctrl | opt),
        Entry(command: .bottomLeftQuarter, keyCode: 38, carbonModifiers: ctrl | opt),
        Entry(command: .bottomRightQuarter, keyCode: 40, carbonModifiers: ctrl | opt),
        Entry(command: .maximize, keyCode: 36, carbonModifiers: ctrl | opt),
        Entry(command: .center, keyCode: 8, carbonModifiers: ctrl | opt),
        Entry(command: .restore, keyCode: 51, carbonModifiers: ctrl | opt),
        Entry(command: .firstThird, keyCode: 2, carbonModifiers: ctrl | opt),
        Entry(command: .centerThird, keyCode: 3, carbonModifiers: ctrl | opt),
        Entry(command: .lastThird, keyCode: 5, carbonModifiers: ctrl | opt),
        Entry(command: .firstTwoThirds, keyCode: 14, carbonModifiers: ctrl | opt),
        Entry(command: .lastTwoThirds, keyCode: 17, carbonModifiers: ctrl | opt),
    ]
}
