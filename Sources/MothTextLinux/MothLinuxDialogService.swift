// SPDX-License-Identifier: MPL-2.0
//
// Linux desktop dialog adapter owned by the Moth application host.
// Luna defines the neutral dialog protocol; Moth chooses the native helper.

import Foundation
import LunaHostCore

struct MothLinuxDialogService: LunaDialogService {
    var scripted: LunaScriptedDialogService
    var environment: [String: String]
    var currentDirectory: String

    init(
        scripted: LunaScriptedDialogService = LunaScriptedDialogService(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) {
        self.scripted = scripted
        self.environment = environment
        self.currentDirectory = currentDirectory
    }

    var providerDescription: String {
        if scripted.hasScriptedOpenSelection || scripted.hasScriptedSaveSelection || scripted.hasScriptedUnsavedDecision {
            return "scripted Moth dialogs"
        }
        return selectedHelper()?.rawValue ?? "Linux desktop dialogs unavailable"
    }

    mutating func confirmUnsavedChanges(_ request: LunaUnsavedChangesDialogRequest) -> LunaUnsavedChangesDialogResult {
        if scripted.hasScriptedUnsavedDecision {
            return scripted.confirmUnsavedChanges(request)
        }
        guard let helper = selectedHelper() else {
            return .cancel("Install zenity, yad, or kdialog to confirm unsaved changes")
        }
        let message = "Save changes to \(request.title)?"
        switch helper {
        case .zenity, .yad:
            let result = run(helper.rawValue, [
                "--question", "--title=Save Changes?", "--text=\(message)",
                "--ok-label=Save", "--cancel-label=Cancel", "--extra-button=Don't Save",
            ])
            if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Don't Save" {
                return .discard("Don't Save selected")
            }
            return result.exitCode == 0 ? .save("Save selected") : .cancel("Close cancelled")
        case .kdialog:
            let result = run(helper.rawValue, [
                "--title", "Save Changes?", "--warningyesnocancel", message,
                "--yes-label", "Save", "--no-label", "Don't Save", "--cancel-label", "Cancel",
            ])
            if result.exitCode == 0 { return .save("Save selected") }
            if result.exitCode == 1 { return .discard("Don't Save selected") }
            return .cancel("Close cancelled")
        }
    }

    mutating func chooseFileToOpen(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        if scripted.hasScriptedOpenSelection {
            return scripted.chooseFileToOpen(request)
        }
        guard let helper = selectedHelper() else {
            return .unavailable(
                "Install zenity, yad, or kdialog, or launch Moth with a file path",
                providerName: providerDescription
            )
        }
        let initial = request.defaultDirectory ?? currentDirectory
        switch helper {
        case .zenity, .yad:
            var arguments = ["--file-selection", "--title=\(request.title)", "--filename=\(directoryPath(initial))"]
            if request.allowsMultipleSelection {
                arguments += ["--multiple", "--separator=\n"]
            }
            return selectedResult(run(helper.rawValue, arguments), provider: helper.rawValue, operation: "Open")
        case .kdialog:
            return selectedResult(
                run(helper.rawValue, ["--getopenfilename", initial]),
                provider: helper.rawValue,
                operation: "Open"
            )
        }
    }

    mutating func chooseFileToSave(_ request: LunaFileDialogRequest) -> LunaFileDialogResult {
        if scripted.hasScriptedSaveSelection {
            return scripted.chooseFileToSave(request)
        }
        guard let helper = selectedHelper() else {
            return .unavailable(
                "Install zenity, yad, or kdialog, or use --save-as PATH",
                providerName: providerDescription
            )
        }
        let directory = request.defaultDirectory ?? currentDirectory
        let filename = request.defaultFileName?.isEmpty == false ? request.defaultFileName! : "untitled.txt"
        let defaultPath = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(filename).path
        let result: ProcessResult
        switch helper {
        case .zenity, .yad:
            result = run(helper.rawValue, [
                "--file-selection", "--save", "--confirm-overwrite",
                "--title=\(request.title)", "--filename=\(defaultPath)",
            ])
        case .kdialog:
            result = run(helper.rawValue, ["--getsavefilename", defaultPath])
        }
        let selected = selectedResult(result, provider: helper.rawValue, operation: "Save As")
        guard selected.didSelect else { return selected }
        return LunaFileDialogResult(
            outcome: selected.outcome,
            selectedPaths: selected.selectedPaths,
            allowsOverwrite: true,
            providerName: selected.providerName,
            statusMessage: selected.statusMessage
        )
    }

    private enum Helper: String, CaseIterable {
        case zenity
        case yad
        case kdialog
    }

    private func selectedHelper() -> Helper? {
        if let forced = environment["MOTH_DIALOG_HELPER"]?.lowercased(), let helper = Helper(rawValue: forced) {
            return commandExists(helper.rawValue) ? helper : nil
        }
        return Helper.allCases.first { commandExists($0.rawValue) }
    }

    private func commandExists(_ name: String) -> Bool {
        run("/usr/bin/env", ["sh", "-lc", "command -v '\(name)' >/dev/null 2>&1"]).exitCode == 0
    }

    private func directoryPath(_ value: String) -> String {
        value.hasSuffix("/") ? value : value + "/"
    }

    private func selectedResult(_ result: ProcessResult, provider: String, operation: String) -> LunaFileDialogResult {
        guard result.exitCode == 0 else {
            return .cancelled("\(operation) cancelled", providerName: provider)
        }
        let paths = result.stdout
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paths.isEmpty
            ? .cancelled("\(operation) returned no path", providerName: provider)
            : .selected(paths, providerName: provider, statusMessage: "\(operation) selected \(paths.count) path(s)")
    }

    private func run(_ executable: String, _ arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = executable.hasPrefix("/")
            ? URL(fileURLWithPath: executable)
            : URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = executable.hasPrefix("/") ? arguments : [executable] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
            return ProcessResult(
                exitCode: process.terminationStatus,
                stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            )
        } catch {
            return ProcessResult(exitCode: 127, stdout: "", stderr: error.localizedDescription)
        }
    }

    private struct ProcessResult {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }
}
