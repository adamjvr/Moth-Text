// SPDX-License-Identifier: MPL-2.0
//
// Moth-owned product theme. Luna supplies semantic tokens; Moth supplies the
// actual product identity and may replace this resource without changing Luna.

import LunaRender
import LunaTheme

public struct MothApplicationRenderPalette: Hashable, Sendable {
    public var windowBackground: LunaRender.LunaRGBA8
    public var chromeBackground: LunaRender.LunaRGBA8
    public var raisedBackground: LunaRender.LunaRGBA8
    public var editorBackground: LunaRender.LunaRGBA8
    public var minimapBackground: LunaRender.LunaRGBA8
    public var separator: LunaRender.LunaRGBA8
    public var text: LunaRender.LunaRGBA8
    public var mutedText: LunaRender.LunaRGBA8
    public var accent: LunaRender.LunaRGBA8
    public var accentStrong: LunaRender.LunaRGBA8
    public var selection: LunaRender.LunaRGBA8
}

public enum MothApplicationTheme {
    public static let theme: LunaTheme = {
        var ui = LunaUIThemeColors.lunaDefaultDark

        ui.windowBackground = .hex("#070709")
        ui.editorBackground = .hex("#0F1013")
        ui.editorForeground = .hex("#CED1DA")
        ui.chromeBackground = .hex("#131416")
        ui.panelBackground = .hex("#131416")
        ui.panelBorder = .hex("#383A40")
        ui.panelTitleBackground = .hex("#242426")
        ui.fieldBackground = .hex("#0F1013")
        ui.fieldBorder = .hex("#383A40")
        ui.overlayBackdrop = .hex("#070709D8")
        ui.hudBackground = .hex("#242426")
        ui.statusText = .hex("#CED1DA")
        ui.movingBlock = .hex("#705AFF")
        ui.movingBlockBorder = .hex("#B8AAFF")

        ui.editor.background = .hex("#0F1013")
        ui.editor.foreground = .hex("#CED1DA")
        ui.editor.gutterBackground = .hex("#0F1013")
        ui.editor.gutterForeground = .hex("#707480")
        ui.editor.currentLineBackground = .hex("#18191D")
        ui.editor.selectionBackground = .hex("#4A3EB2A8")
        ui.editor.caret = .hex("#B8AAFF")
        ui.editor.minimapBackground = .hex("#0C0D10")
        ui.editor.minimapViewport = .hex("#705AFF80")

        ui.chrome.titleBarBackground = .hex("#131416")
        ui.chrome.titleBarForeground = .hex("#CED1DA")
        ui.chrome.menuBarBackground = .hex("#131416")
        ui.chrome.menuBarForeground = .hex("#A4A7B0")
        ui.chrome.menuBarHoveredBackground = .hex("#242426")
        ui.chrome.menuBarActiveForeground = .hex("#F4F2FF")
        ui.chrome.menuBarActiveUnderline = .hex("#705AFF")
        ui.chrome.tabStripBackground = .hex("#242426")
        ui.chrome.windowBorder = .hex("#383A40")
        ui.chrome.separator = .hex("#383A40")

        ui.tabs.stripBackground = .hex("#242426")
        ui.tabs.activeBackground = .hex("#0F1013")
        ui.tabs.inactiveBackground = .hex("#242426")
        ui.tabs.hoveredBackground = .hex("#303034")
        ui.tabs.activeForeground = .hex("#F4F2FF")
        ui.tabs.inactiveForeground = .hex("#A4A7B0")
        ui.tabs.divider = .hex("#383A40")
        ui.tabs.dirtyIndicator = .hex("#B8AAFF")
        ui.tabs.closeButton = .hex("#A4A7B0")

        ui.sidebar.background = .hex("#131416")
        ui.sidebar.sectionForeground = .hex("#CED1DA")
        ui.sidebar.rowForeground = .hex("#CED1DA")
        ui.sidebar.rowMutedForeground = .hex("#707480")
        ui.sidebar.rowHoveredBackground = .hex("#242426")
        ui.sidebar.rowSelectedBackground = .hex("#392F85")
        ui.sidebar.rowSelectedForeground = .hex("#F4F2FF")
        ui.sidebar.disclosureForeground = .hex("#8D909A")
        ui.sidebar.border = .hex("#383A40")

        ui.statusBar.background = .hex("#242426")
        ui.statusBar.foreground = .hex("#CED1DA")
        ui.statusBar.mutedForeground = .hex("#8D909A")
        ui.statusBar.border = .hex("#383A40")
        ui.statusBar.accent = .hex("#705AFF")

        ui.controlColors.accent = .hex("#705AFF")
        ui.controlColors.accentStrong = .hex("#B8AAFF")
        ui.controlColors.focusedBorder = .hex("#B8AAFF")

        return LunaTheme(
            name: "Moth Midnight",
            background: .hex("#0F1013"),
            foreground: .hex("#CED1DA"),
            caret: .hex("#B8AAFF"),
            selection: .hex("#4A3EB2A8"),
            ui: ui
        )
    }()

    public static let renderPalette: MothApplicationRenderPalette = {
        let theme = MothApplicationTheme.theme
        return MothApplicationRenderPalette(
            windowBackground: theme.ui.windowBackground.asRenderColor,
            chromeBackground: theme.ui.chrome.titleBarBackground.asRenderColor,
            raisedBackground: theme.ui.tabs.stripBackground.asRenderColor,
            editorBackground: theme.ui.editor.background.asRenderColor,
            minimapBackground: theme.ui.editor.minimapBackground.asRenderColor,
            separator: theme.ui.chrome.separator.asRenderColor,
            text: theme.ui.editor.foreground.asRenderColor,
            mutedText: theme.ui.sidebar.rowMutedForeground.asRenderColor,
            accent: theme.ui.statusBar.accent.asRenderColor,
            accentStrong: theme.ui.controlColors.accentStrong.asRenderColor,
            selection: theme.ui.editor.selectionBackground.asRenderColor
        )
    }()
}
