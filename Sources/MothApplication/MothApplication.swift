// SPDX-License-Identifier: MPL-2.0
import Foundation
import LunaCore
import LunaUI
import MothEditor
import MothIPC
import MothTextCore
import MothWorkspace

/// Shared product bootstrap used by every platform entry point.
/// Platform executables remain thin and do not construct their UI with SwiftUI,
/// GTK widgets, AppKit widgets, or another native widget hierarchy.
public enum MothApplication {
    public static let productName = "Moth Text"

    public static func startupSummary(platform: String) -> String {
        "\(productName) \(platform) host: Luna linked; Moth architecture v\(MothTextCore.architectureVersion)"
    }
}
