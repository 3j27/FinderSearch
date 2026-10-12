import AppKit
import CoreServices

/// Keep Launch Services' on-disk icon current, including after the app quits.
@MainActor enum ApplicationIcon {
    private static var registered = false
    static func registerBundle() {
        guard !registered, Bundle.main.bundleURL.pathExtension == "app",
            Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil
        else { return }
        registered = LSRegisterURL(Bundle.main.bundleURL as CFURL, true) == noErr
    }
}
