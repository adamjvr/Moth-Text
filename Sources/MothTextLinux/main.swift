// SPDX-License-Identifier: MPL-2.0

import Foundation
import LunaCore
import LunaHostCore
import LunaHostSDL
import LunaInput
import LunaRender
import MothApplication
import MothIPC

private let socketPath = "/tmp/mothtext.sock"

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func runPluginHostPingSmokeTest() throws {
    print("[MothTextLinux] Connecting to optional plugin host at \(socketPath)")
    let socket = try UnixDomainSocket.connect(toPath: socketPath)
    let request = try IPC.makePingRequest(message: "Hello from MothTextLinux IPC smoke test")
    try socket.writeLine(try IPC.encodeEnvelope(request))

    while true {
        let lines = try socket.readAvailableLines()
        if lines.isEmpty {
            throw NSError(
                domain: "MothTextLinux.IPCSmokeTest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Plugin host closed before replying"]
            )
        }
        for line in lines {
            let envelope = try IPC.decodeEnvelope(fromLine: line)
            guard envelope.id == request.id else { continue }
            if let error = envelope.error {
                throw NSError(
                    domain: "MothTextLinux.IPCSmokeTest",
                    code: error.code,
                    userInfo: [NSLocalizedDescriptionKey: error.message]
                )
            }
            guard envelope.type == .response, envelope.method == "core.ping" else { continue }
            let pong = try IPC.decodePingResult(envelope.result)
            print("[MothTextLinux] Plugin host pong: '\(pong.echoed)'")
            return
        }
    }
}

private struct LaunchOptions {
    var openPath: String?
    var scriptedSavePath: String?
    var ipcSmoke = false
    var headlessSmoke = false

    init(arguments: [String]) {
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--ipc-smoke":
                ipcSmoke = true
            case "--headless-smoke":
                headlessSmoke = true
            case "--open" where index + 1 < arguments.count:
                index += 1
                openPath = arguments[index]
            case "--save-as" where index + 1 < arguments.count:
                index += 1
                scriptedSavePath = arguments[index]
            case let argument where !argument.hasPrefix("-") && openPath == nil:
                openPath = argument
            default:
                break
            }
            index += 1
        }
    }
}

private struct MothLinuxSDLScene: LunaSDLApplicationScene {
    var shell: MothApplicationShellScene

    var wantsContinuousRendering: Bool { shell.wantsContinuousRendering }
    var cursorIntent: LunaCursorIntent { shell.cursorIntent }
    var wantsPointerCapture: Bool { shell.wantsPointerCapture }

    mutating func shouldTerminate() -> Bool {
        shell.requestApplicationTermination()
    }

    mutating func handleHostEvent(
        _ event: LunaHostInputEvent,
        framebufferSize: LunaSizeI
    ) -> LunaFrameInvalidationSet {
        shell.handleHostEvent(event, framebufferSize: framebufferSize)
    }

    mutating func updateFrameRuntimeDiagnostics(
        timingStats: LunaFrameTimingStats,
        invalidations: LunaFrameInvalidationSet,
        inputCoalescingStats: LunaInputCoalescingStats
    ) {
        shell.updateHostRuntimeDiagnostics(
            timingStats: timingStats,
            inputStats: inputCoalescingStats,
            invalidations: invalidations
        )
    }

    mutating func render(into framebuffer: inout LunaFramebuffer) {
        shell.render(into: &framebuffer)
    }

    mutating func takeFrameRenderReport() -> LunaFrameRenderReport? {
        shell.takeFrameRenderReport()
    }
}

private let options = LaunchOptions(arguments: CommandLine.arguments)
print(MothApplication.startupSummary(platform: "Linux"))

if options.ipcSmoke {
    do {
        try runPluginHostPingSmokeTest()
        print("[MothTextLinux] IPC smoke test passed")
        exit(EXIT_SUCCESS)
    } catch {
        writeError("[MothTextLinux] IPC smoke test failed: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}

let scripted = LunaScriptedDialogService(
    savePathSelections: options.scriptedSavePath.map { [$0] } ?? [],
    scriptedSelectionsAllowOverwrite: true
)
var shell = MothApplicationShellScene(
    dialogService: MothLinuxDialogService(scripted: scripted)
)

if let openPath = options.openPath {
    do {
        try shell.openDocument(at: URL(fileURLWithPath: openPath))
    } catch {
        writeError("[MothTextLinux] Could not open \(openPath): \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}

if options.headlessSmoke {
    var framebuffer = LunaFramebuffer(width: 1100, height: 720)
    shell.render(into: &framebuffer)

    let diagnostics = shell.unicodeTextDiagnostics
    if diagnostics.isUsingFallback {
        let detail = diagnostics.failureDescription ?? "unknown renderer failure"
        writeError("[MothTextLinux] Headless render smoke failed: \(detail)")
        exit(EXIT_FAILURE)
    }

    print(
        "[MothTextLinux] Headless render smoke passed with Unicode font: "
            + (diagnostics.fontPath ?? "<unknown>")
    )
    exit(EXIT_SUCCESS)
}

private var scene = MothLinuxSDLScene(shell: shell)
let result = runLunaSDLApplication(
    configuration: LunaSDLApplicationConfiguration(
        title: "Moth Text",
        initialWidth: 1100,
        initialHeight: 720
    ),
    scene: &scene
)

if result != 0 {
    writeError("[MothTextLinux] Luna host exited with code \(result)")
    exit(result)
}
