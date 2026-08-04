// SPDX-License-Identifier: MPL-2.0
//
// MothCommandSystem.swift
//
// Moth-owned command vocabulary and product policy built on Luna's reusable
// command runtime. M3A assigns document-tab workflow to Moth while Luna remains
// responsible for generic key matching and command-surface projection.

import LunaCommands

public enum MothCommandID {
    public static let newFile: LunaCommandID = "moth.file.new"
    public static let openFile: LunaCommandID = "moth.file.open"
    public static let save: LunaCommandID = "moth.file.save"
    public static let saveAs: LunaCommandID = "moth.file.saveAs"
    public static let closeTab: LunaCommandID = "moth.file.closeTab"

    public static let undo: LunaCommandID = "moth.edit.undo"
    public static let redo: LunaCommandID = "moth.edit.redo"
    public static let selectAll: LunaCommandID = "moth.edit.selectAll"

    public static let showFind: LunaCommandID = "moth.find.show"

    public static let nextTab: LunaCommandID = "moth.view.nextTab"
    public static let previousTab: LunaCommandID = "moth.view.previousTab"
    public static let nextPane: LunaCommandID = "moth.view.nextPane"
    public static let previousPane: LunaCommandID = "moth.view.previousPane"

    public static let showCommandPalette: LunaCommandID = "moth.tools.commandPalette"

    public static let selectTabCommands: [LunaCommandID] = (1...9).map {
        LunaCommandID(rawValue: "moth.view.selectTab\($0)")
    }

    public static func tabIndex(for command: LunaCommandID) -> Int? {
        selectTabCommands.firstIndex(of: command)
    }

    public static let all: [LunaCommandID] = [
        newFile,
        openFile,
        save,
        saveAs,
        closeTab,
        undo,
        redo,
        selectAll,
        showFind,
        nextTab,
        previousTab,
        nextPane,
        previousPane,
        showCommandPalette,
    ] + selectTabCommands
}

enum MothCommandSystem {
    static func makeRuntime() -> LunaCommandRuntime<MothApplicationShellScene> {
        var runtime = LunaCommandRuntime<MothApplicationShellScene>()

        let handler: LunaCommandHandler<MothApplicationShellScene> = {
            command, host, context in
            host.performRegisteredCommand(command, context: context)
        }
        let availability: LunaCommandAvailabilityProvider<MothApplicationShellScene> = {
            command, host, context in
            host.registeredCommandAvailability(command, context: context)
        }

        func descriptor(
            _ id: LunaCommandID,
            _ title: String,
            key: LunaKeyEquivalent? = nil,
            menu: [String]
        ) -> LunaCommandDescriptor {
            LunaCommandDescriptor(
                id: id,
                title: title,
                defaultKey: key,
                menuPath: menu
            )
        }

        runtime.register(
            descriptor(
                MothCommandID.newFile,
                "New File",
                key: LunaKeyEquivalent("N", modifiers: [.primary]),
                menu: ["File"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.registerKeyBinding(
            LunaKeyBinding(
                command: MothCommandID.newFile,
                keyEquivalent: LunaKeyEquivalent("T", modifiers: [.primary]),
                priority: 10
            )
        )
        runtime.register(
            descriptor(
                MothCommandID.openFile,
                "Open File…",
                key: LunaKeyEquivalent("O", modifiers: [.primary]),
                menu: ["File"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            descriptor(
                MothCommandID.save,
                "Save",
                key: LunaKeyEquivalent("S", modifiers: [.primary]),
                menu: ["File"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            descriptor(
                MothCommandID.saveAs,
                "Save As…",
                key: LunaKeyEquivalent("S", modifiers: [.primary, .shift]),
                menu: ["File"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            descriptor(
                MothCommandID.closeTab,
                "Close Tab",
                key: LunaKeyEquivalent("W", modifiers: [.primary]),
                menu: ["File"]
            ),
            handler: handler,
            availability: availability
        )

        runtime.register(
            descriptor(
                MothCommandID.undo,
                "Undo",
                key: LunaKeyEquivalent("Z", modifiers: [.primary]),
                menu: ["Edit"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            descriptor(
                MothCommandID.redo,
                "Redo",
                key: LunaKeyEquivalent("Z", modifiers: [.primary, .shift]),
                menu: ["Edit"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.registerKeyBinding(
            LunaKeyBinding(
                command: MothCommandID.redo,
                keyEquivalent: LunaKeyEquivalent("Y", modifiers: [.primary]),
                priority: 10
            )
        )
        runtime.register(
            descriptor(
                MothCommandID.selectAll,
                "Select All",
                key: LunaKeyEquivalent("A", modifiers: [.primary]),
                menu: ["Selection"]
            ),
            handler: handler,
            availability: availability
        )

        runtime.register(
            descriptor(
                MothCommandID.showFind,
                "Find…",
                key: LunaKeyEquivalent("F", modifiers: [.primary]),
                menu: ["Find"]
            ),
            handler: handler,
            availability: availability
        )

        runtime.register(
            descriptor(
                MothCommandID.nextTab,
                "Next Tab",
                key: LunaKeyEquivalent("Tab", modifiers: [.primary]),
                menu: ["View"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.registerKeyBinding(
            LunaKeyBinding(
                command: MothCommandID.nextTab,
                keyEquivalent: LunaKeyEquivalent("PageDown", modifiers: [.primary]),
                priority: 10
            )
        )
        runtime.register(
            descriptor(
                MothCommandID.previousTab,
                "Previous Tab",
                menu: ["View"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.registerKeyBinding(
            LunaKeyBinding(
                command: MothCommandID.previousTab,
                keyEquivalent: LunaKeyEquivalent("Tab", modifiers: [.primary, .shift]),
                priority: 10
            )
        )
        runtime.registerKeyBinding(
            LunaKeyBinding(
                command: MothCommandID.previousTab,
                keyEquivalent: LunaKeyEquivalent("PageUp", modifiers: [.primary]),
                priority: 10
            )
        )

        runtime.register(
            descriptor(
                MothCommandID.nextPane,
                "Next Pane",
                key: LunaKeyEquivalent("Tab", modifiers: [.primary, .option]),
                menu: ["View"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            descriptor(
                MothCommandID.previousPane,
                "Previous Pane",
                menu: ["View"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.registerKeyBinding(
            LunaKeyBinding(
                command: MothCommandID.previousPane,
                keyEquivalent: LunaKeyEquivalent(
                    "Tab",
                    modifiers: [.primary, .option, .shift]
                ),
                priority: 10
            )
        )

        for (index, command) in MothCommandID.selectTabCommands.enumerated() {
            runtime.register(
                descriptor(
                    command,
                    "Select Tab \(index + 1)",
                    key: LunaKeyEquivalent("\(index + 1)", modifiers: [.option]),
                    menu: ["View"]
                ),
                handler: handler,
                availability: availability
            )
        }

        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.showCommandPalette,
                title: "Command Palette…",
                defaultKey: LunaKeyEquivalent("P", modifiers: [.primary, .shift]),
                menuPath: ["Tools"],
                isPaletteVisible: false
            ),
            handler: handler,
            availability: availability
        )

        return runtime
    }
}
