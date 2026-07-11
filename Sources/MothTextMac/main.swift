// SPDX-License-Identifier: MPL-2.0
import Foundation
import MothApplication

// M0 platform entry point. A later paired Luna/Moth phase will attach the macOS
// Luna host here. The application interior will be Luna-rendered rather than a
// SwiftUI or AppKit widget hierarchy.
print(MothApplication.startupSummary(platform: "macOS"))
