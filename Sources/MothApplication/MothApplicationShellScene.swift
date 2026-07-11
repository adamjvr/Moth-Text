// SPDX-License-Identifier: MPL-2.0
//
// MothApplicationShellScene.swift
//
// First real graphical Moth application shell. The scene is deliberately
// platform-neutral: Luna's platform host owns the native window and event loop,
// while this type owns Moth's visible application content and interaction state.

import LunaCore
import LunaHostCore
import LunaInput
import LunaRender

public struct MothApplicationShellScene: Sendable {
    public private(set) var framebufferSize: LunaSizeI
    public private(set) var pointerAccentIsActive: Bool
    public private(set) var keyboardEventCount: UInt64

    public init(initialSize: LunaSizeI = LunaSizeI(width: 1100, height: 720)) {
        self.framebufferSize = initialSize
        self.pointerAccentIsActive = false
        self.keyboardEventCount = 0
    }

    public var wantsContinuousRendering: Bool { false }

    public mutating func handleHostEvent(
        _ event: LunaHostInputEvent,
        framebufferSize: LunaSizeI
    ) -> LunaFrameInvalidationSet {
        self.framebufferSize = framebufferSize

        switch event {
        case .quit:
            return LunaFrameInvalidationSet()

        case .windowResized:
            return LunaFrameInvalidationSet(.windowResized)

        case .pointer(let pointer):
            if pointer.phase == .down {
                pointerAccentIsActive.toggle()
            }
            return LunaFrameInvalidationSet(.input)

        case .keyboard:
            keyboardEventCount &+= 1
            return LunaFrameInvalidationSet(.input)

        case .textInput:
            return LunaFrameInvalidationSet(.textInput)
        }
    }

    public mutating func render(into framebuffer: inout LunaFramebuffer) {
        let width = framebuffer.width
        let height = framebuffer.height

        let background = LunaRGBA8(r: 7, g: 7, b: 9)
        let chrome = LunaRGBA8(r: 19, g: 20, b: 22)
        let raised = LunaRGBA8(r: 36, g: 36, b: 38)
        let editor = LunaRGBA8(r: 15, g: 16, b: 19)
        let separator = LunaRGBA8(r: 56, g: 58, b: 64)
        let accent = pointerAccentIsActive
            ? LunaRGBA8(r: 0, g: 60, b: 255)
            : LunaRGBA8(r: 74, g: 86, b: 120)

        framebuffer.clear(background)

        // Custom Moth/Luna chrome proof: menu row, tab strip, sidebar, editor,
        // caret, minimap, and status bar are all CPU-rendered Luna pixels rather
        // than native GTK/SwiftUI/AppKit controls.
        framebuffer.fillRect(
            LunaRectI(x: 0, y: 0, w: width, h: 30),
            color: chrome
        )
        framebuffer.fillRect(
            LunaRectI(x: 0, y: 30, w: width, h: 38),
            color: raised
        )

        let statusHeight = 24
        let sidebarWidth = min(260, max(150, width / 4))
        let minimapWidth = min(110, max(60, width / 10))
        let contentTop = 68
        let contentHeight = max(1, height - contentTop - statusHeight)

        framebuffer.fillRect(
            LunaRectI(x: 0, y: contentTop, w: sidebarWidth, h: contentHeight),
            color: chrome
        )
        framebuffer.fillRect(
            LunaRectI(
                x: sidebarWidth + 1,
                y: contentTop,
                w: max(1, width - sidebarWidth - minimapWidth - 2),
                h: contentHeight
            ),
            color: editor
        )
        framebuffer.fillRect(
            LunaRectI(
                x: max(sidebarWidth + 1, width - minimapWidth),
                y: contentTop,
                w: minimapWidth,
                h: contentHeight
            ),
            color: LunaRGBA8(r: 12, g: 13, b: 16)
        )
        framebuffer.fillRect(
            LunaRectI(x: 0, y: max(0, height - statusHeight), w: width, h: statusHeight),
            color: raised
        )

        framebuffer.fillRect(
            LunaRectI(x: sidebarWidth, y: contentTop, w: 1, h: contentHeight),
            color: separator
        )
        framebuffer.fillRect(
            LunaRectI(x: 0, y: contentTop - 1, w: width, h: 1),
            color: separator
        )

        // Active tab indicator.
        framebuffer.fillRect(
            LunaRectI(x: 10, y: 63, w: min(180, max(40, width / 5)), h: 3),
            color: accent
        )

        // Sidebar rows and editor-line rhythm make the shell visually obvious
        // even before the real editor text model is connected in M1.
        for row in 0..<8 {
            let y = contentTop + 18 + (row * 25)
            let inset = row == 0 ? 16 : 30
            let rowWidth = max(20, sidebarWidth - inset - 20 - ((row % 3) * 18))
            framebuffer.fillRect(
                LunaRectI(x: inset, y: y, w: rowWidth, h: 7),
                color: row == 2 ? accent : LunaRGBA8(r: 70, g: 72, b: 78)
            )
        }

        let editorLeft = sidebarWidth + 28
        let editorRight = max(editorLeft + 1, width - minimapWidth - 24)
        for row in 0..<15 {
            let y = contentTop + 20 + (row * 24)
            if y + 5 >= height - statusHeight { break }
            let available = max(1, editorRight - editorLeft)
            let lineWidth = max(24, min(available, available / 3 + ((row * 47) % max(1, available / 2))))
            framebuffer.fillRect(
                LunaRectI(x: editorLeft, y: y, w: lineWidth, h: 5),
                color: row % 4 == 0
                    ? LunaRGBA8(r: 115, g: 122, b: 145)
                    : LunaRGBA8(r: 82, g: 85, b: 96)
            )
        }

        // Visible caret proof. Clicking anywhere toggles its accent color.
        framebuffer.fillRect(
            LunaRectI(x: editorLeft, y: contentTop + 16, w: 2, h: 18),
            color: accent
        )

        // Minimap rhythm.
        let minimapLeft = max(sidebarWidth + 1, width - minimapWidth + 10)
        for row in 0..<30 {
            let y = contentTop + 10 + row * 10
            if y + 2 >= height - statusHeight { break }
            framebuffer.fillRect(
                LunaRectI(x: minimapLeft, y: y, w: max(8, minimapWidth - 20 - (row % 5) * 7), h: 2),
                color: LunaRGBA8(r: 55, g: 58, b: 68)
            )
        }
    }
}
