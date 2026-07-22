// SPDX-License-Identifier: MPL-2.0
//
// MothCommandSystem.swift
//
// Moth-owned command vocabulary and product policy built on Luna's reusable
// command runtime. Luna owns descriptors, key matching, availability projection,
// and surface routing. Moth owns stable command IDs and every editor/file action.

import LunaCommands

/// Stable product command identifiers.
///
/// These strings are persistence-facing API. Future keymaps, menu resources,
/// packages, plugins, and Sublime-compatibility adapters may refer to them, so
/// rename them only through an explicit compatibility migration.
public enum MothCommandID {
    public static let newFile: LunaCommandID = "moth.file.new"
    public static let openFile: LunaCommandID = "moth.file.open"
    public static let save: LunaCommandID = "moth.file.save"
    public static let saveAs: LunaCommandID = "moth.file.saveAs"

    public static let undo: LunaCommandID = "moth.edit.undo"
    public static let redo: LunaCommandID = "moth.edit.redo"
    public static let selectAll: LunaCommandID = "moth.edit.selectAll"

    public static let showFind: LunaCommandID = "moth.find.show"

    public static let nextPane: LunaCommandID = "moth.view.nextPane"
    public static let previousPane: LunaCommandID = "moth.view.previousPane"

    public static let showCommandPalette: LunaCommandID = "moth.tools.commandPalette"

    public static let all: [LunaCommandID] = [
        newFile,
        openFile,
        save,
        saveAs,
        undo,
        redo,
        selectAll,
        showFind,
        nextPane,
        previousPane,
        showCommandPalette,
    ]
}

enum MothCommandSystem {
    static func makeRuntime() -> LunaCommandRuntime<MothApplicationShellScene> {
        var runtime = LunaCommandRuntime<MothApplicationShellScene>()

        let handler: LunaCommandHandler<MothApplicationShellScene> = { command, host, context in
            host.performRegisteredCommand(command, context: context)
        }
        let availability: LunaCommandAvailabilityProvider<MothApplicationShellScene> = { command, host, context in
            host.registeredCommandAvailability(command, context: context)
        }

        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.newFile,
                title: "New File",
                defaultKey: LunaKeyEquivalent("N", modifiers: [.primary]),
                menuPath: ["File"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.openFile,
                title: "Open File…",
                defaultKey: LunaKeyEquivalent("O", modifiers: [.primary]),
                menuPath: ["File"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.save,
                title: "Save",
                defaultKey: LunaKeyEquivalent("S", modifiers: [.primary]),
                menuPath: ["File"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.saveAs,
                title: "Save As…",
                defaultKey: LunaKeyEquivalent("S", modifiers: [.primary, .shift]),
                menuPath: ["File"]
            ),
            handler: handler,
            availability: availability
        )

        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.undo,
                title: "Undo",
                defaultKey: LunaKeyEquivalent("Z", modifiers: [.primary]),
                menuPath: ["Edit"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.redo,
                title: "Redo",
                defaultKey: LunaKeyEquivalent("Z", modifiers: [.primary, .shift]),
                menuPath: ["Edit"]
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
            LunaCommandDescriptor(
                id: MothCommandID.selectAll,
                title: "Select All",
                defaultKey: LunaKeyEquivalent("A", modifiers: [.primary]),
                menuPath: ["Selection"]
            ),
            handler: handler,
            availability: availability
        )

        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.showFind,
                title: "Find…",
                defaultKey: LunaKeyEquivalent("F", modifiers: [.primary]),
                menuPath: ["Find"]
            ),
            handler: handler,
            availability: availability
        )

        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.nextPane,
                title: "Next Pane",
                defaultKey: LunaKeyEquivalent("Tab", modifiers: [.primary]),
                menuPath: ["View"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.register(
            LunaCommandDescriptor(
                id: MothCommandID.previousPane,
                title: "Previous Pane",
                menuPath: ["View"]
            ),
            handler: handler,
            availability: availability
        )
        runtime.registerKeyBinding(
            LunaKeyBinding(
                command: MothCommandID.previousPane,
                keyEquivalent: LunaKeyEquivalent("Tab", modifiers: [.primary, .shift]),
                priority: 10
            )
        )

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
