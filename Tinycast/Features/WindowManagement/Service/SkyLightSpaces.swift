import ColorSync
import CoreGraphics
import Darwin
import Foundation
/// SkyLight reads plus the symbolic-hotkey setup, runtime-resolved with no private linkage.
enum SkyLightSpaces {
    struct DisplaySpaces: Sendable {
        let displayKey: String
        let displayID: CGDirectDisplayID
        let spaces: [UInt64]
        let activeSpaceID: UInt64
        let activeIndex: Int
    }

    /// The cursor display's list; the Dock routes a swipe there, not to the focused display.
    static func spaceInfo(cursorPoint: CGPoint) -> DisplaySpaces? {
        guard let handle = dlopen(skylightPath, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        typealias MainConnection = @convention(c) () -> Int32
        typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
        typealias ActiveSpace = @convention(c) (Int32) -> UInt64
        guard
            let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
            let copySymbol = dlsym(handle, "SLSCopyManagedDisplaySpaces"),
            let activeSymbol = dlsym(handle, "SLSGetActiveSpace")
        else { return nil }
        let mainConnection = unsafeBitCast(mainSymbol, to: MainConnection.self)
        let copySpaces = unsafeBitCast(copySymbol, to: CopySpaces.self)
        let getActive = unsafeBitCast(activeSymbol, to: ActiveSpace.self)
        let connection = mainConnection()
        guard let unmanaged = copySpaces(connection) else { return nil }
        let displays = unmanaged.takeRetainedValue() as NSArray
        let activeSpaceID = getActive(connection)
        return pickDisplay(displays: displays, activeSpaceID: activeSpaceID, cursorPoint: cursorPoint)
    }

    /// While on, symbolic hotkeys 79/81 go dark live and on disk; while off they come back.
    nonisolated static func applySystemConfiguration(enabled: Bool) {
        if enabled {
            setSymbolicHotKeys(enabled: false)
            persistSymbolicHotKeys(enabled: false)
            clearStaleAutoSwoosh()
        } else if currentPersistedHotKeysEnabled() == false {
            setSymbolicHotKeys(enabled: true)
            persistSymbolicHotKeys(enabled: true)
        }
    }

    // MARK: - Reads

    private static let skylightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

    private static func pickDisplay(
        displays: NSArray, activeSpaceID: UInt64, cursorPoint: CGPoint
    ) -> DisplaySpaces? {
        var fallback: DisplaySpaces?
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(cursorPoint, 1, nil, &count) == .success else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(max(count, 1)))
        var fetched: UInt32 = 0
        guard
            CGGetDisplaysWithPoint(cursorPoint, UInt32(ids.count), &ids, &fetched) == .success,
            fetched > 0
        else { return matchActive(displays: displays, activeSpaceID: activeSpaceID) }
        let cursorID = ids[0]
        let cursorUUID = SkyLightSpaces.displayUUID(cursorID)
        for element in displays {
            guard let info = parseDisplay(element) else { continue }
            if !cursorUUID.isEmpty, info.uuid == cursorUUID {
                return info.make(cursorID: cursorID, activeSpaceID: activeSpaceID)
            }
            if fallback == nil, info.spaces.contains(activeSpaceID) {
                fallback = info.make(cursorID: cursorID, activeSpaceID: activeSpaceID)
            }
        }
        if let fallback { return fallback }
        return matchActive(displays: displays, activeSpaceID: activeSpaceID)
    }

    private static func matchActive(displays: NSArray, activeSpaceID: UInt64) -> DisplaySpaces? {
        for element in displays {
            guard let info = parseDisplay(element) else { continue }
            if info.spaces.contains(activeSpaceID) {
                return info.make(cursorID: CGMainDisplayID(), activeSpaceID: activeSpaceID)
            }
        }
        return nil
    }

    private struct ParsedDisplay {
        let uuid: String
        let spaces: [UInt64]
        let currentSpaceID: UInt64?

        func make(cursorID: CGDirectDisplayID, activeSpaceID: UInt64) -> DisplaySpaces? {
            guard !spaces.isEmpty else { return nil }
            let resolved = currentSpaceID ?? activeSpaceID
            let key = uuid.isEmpty ? "display:\(cursorID)" : uuid
            let index = spaces.firstIndex(of: resolved) ?? spaces.firstIndex(of: activeSpaceID) ?? 0
            return DisplaySpaces(
                displayKey: key, displayID: cursorID, spaces: spaces,
                activeSpaceID: spaces[index], activeIndex: index)
        }
    }

    private static func displayUUID(_ displayID: CGDirectDisplayID) -> String {
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
        guard let string = CFUUIDCreateString(kCFAllocatorDefault, uuid) as String? else { return "" }
        return string
    }

    private static func parseDisplay(_ element: Any) -> ParsedDisplay? {
        guard let dict = element as? NSDictionary else { return nil }
        let uuid =
            dict["Display Identifier"] as? String ?? dict["DisplayID"] as? String
            ?? dict["UUID"] as? String ?? ""
        let rawSpaces =
            dict["Spaces"] as? NSArray ?? dict["ManagedSpaces"] as? NSArray ?? []
        var spaces: [UInt64] = []
        for raw in rawSpaces {
            if let number = raw as? NSNumber {
                spaces.append(number.uint64Value)
            } else if let spaceDict = raw as? NSDictionary {
                if let id = spaceID(spaceDict) { spaces.append(id) }
            }
        }
        var current: UInt64?
        if let currentDict = dict["Current Space"] as? NSDictionary ?? dict["CurrentSpace"] as? NSDictionary {
            current = spaceID(currentDict)
        }
        guard !spaces.isEmpty else { return nil }
        return ParsedDisplay(uuid: uuid, spaces: spaces, currentSpaceID: current)
    }

    private static func spaceID(_ dict: NSDictionary) -> UInt64? {
        if let number = dict["id64"] as? NSNumber { return number.uint64Value }
        if let number = dict["ManagedSpaceID"] as? NSNumber { return number.uint64Value }
        if let number = dict["SpaceID"] as? NSNumber { return number.uint64Value }
        if let number = dict["id"] as? NSNumber { return number.uint64Value }
        return nil
    }

    // MARK: - Setup

    private static func setSymbolicHotKeys(enabled: Bool) {
        guard let handle = dlopen(skylightPath, RTLD_NOW) else { return }
        defer { dlclose(handle) }
        typealias SetEnabled = @convention(c) (Int32, Bool) -> Void
        guard let symbol = dlsym(handle, "SLSSetSymbolicHotKeyEnabled") else { return }
        let setEnabled = unsafeBitCast(symbol, to: SetEnabled.self)
        setEnabled(79, enabled)
        setEnabled(81, enabled)
    }

    private static func persistSymbolicHotKeys(enabled: Bool) {
        let flag = enabled ? 1 : 0
        for (key, arrow) in [(79, 123), (81, 124)] {
            let value =
                "{enabled = \(flag); value = { parameters = (65535, \(arrow), 8650752); type = standard; };}"
            _ = shell(
                "/usr/bin/defaults",
                ["write", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys", "-dict-add", "\(key)", value])
        }
    }

    private static func currentPersistedHotKeysEnabled() -> Bool? {
        let read = shell(
            "/usr/bin/defaults", ["read", "com.apple.symbolichotkeys", "AppleSymbolicHotKeys"])
        guard read.status == 0 else { return nil }
        if read.stdout.contains("enabled = 0") { return false }
        if read.stdout.contains("enabled = 1") { return true }
        return nil
    }

    private static func clearStaleAutoSwoosh() {
        let read = shell("/usr/bin/defaults", ["read", "com.apple.dock", "workspaces-auto-swoosh"])
        guard read.status == 0 else { return }
        _ = shell("/usr/bin/defaults", ["delete", "com.apple.dock", "workspaces-auto-swoosh"])
        _ = shell("/usr/bin/killall", ["Dock"])
    }

    private struct ShellResult {
        let status: Int32
        let stdout: String
    }

    private static func shell(_ executable: String, _ arguments: [String]) -> ShellResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ShellResult(status: 1, stdout: "") }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return ShellResult(
            status: process.terminationStatus, stdout: String(data: data, encoding: .utf8) ?? "")
    }
}
