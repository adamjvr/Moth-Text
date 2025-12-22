# 🦋 Moth-Text  
### **Moth is Sublime.**

**Moth-Text** is a **from-scratch, open-source reimplementation of Sublime Text**, written entirely in **Swift** and powered by a custom UI engine called **Luna-UI**.

Like Linux in relation to UNIX, **Moth is not Sublime Text — but it *is* Sublime in behavior, compatibility, and philosophy.**

> **Moth is Sublime.**  
> Same ideas. Same workflows. Same power.  
> Clean-room implementation. Modern internals. Open future.

---

## 🎯 What “Moth is Sublime” Means

“Moth is Sublime” is not a slogan about imitation — it’s a statement of **compatibility by design**.

| Sublime Text | Moth-Text |
|-------------|----------|
| Proprietary implementation | Open-source implementation |
| C++ / Python | Swift / Python |
| Custom UI engine | **Luna-UI** |
| Plugin-driven | Plugin-driven |
| UNIX-style architecture | UNIX-style architecture |

Just as:
> **Linux is UNIX-compatible without being UNIX**

So:
> **Moth is Sublime without being Sublime Text**

---

## 🎯 Project Goals

- **Full Sublime-compatible behavior**
- **Native performance on macOS and Linux**
- **Long-term API and plugin stability**
- **Clean separation of UI, editor core, and plugins**
- **No dependency on web tech or heavyweight UI frameworks**

---

## ❌ What Moth-Text Is Not

- Not a fork of Sublime Text  
- Not a re-skin or clone UI  
- Not Electron  
- Not SwiftUI, GTK, or Qt  
- Not a web editor in disguise  

This is a **clean-room reimplementation**, built to last decades.

---

## 🧩 Sublime Compatibility Targets

Moth-Text is being built to match **Sublime’s behavior and ecosystem**, including:

### ✔ Editor Semantics
- Identical selection and multi-cursor model
- Same command-driven architecture
- Same keybinding resolution logic
- Same editing edge cases and behaviors

### ✔ Package & Plugin System
- Python 3 plugin runtime
- Sublime-style package layout
- Command registration
- Event hooks
- View / window APIs
- LSP integration

> The long-term goal is that **most Sublime packages can be ported with little or no modification**, and many will work unchanged.

---

## 🧠 Architecture Overview

Moth-Text intentionally mirrors Sublime’s proven architecture, while modernizing the internals:

```
┌─────────────────────────────┐
│         Moth-Text App       │
│                             │
│  ┌──────── Luna-UI ──────┐  │
│  │  Windowing            │  │
│  │  Rendering (GPU/CPU)  │  │
│  │  Input                │  │
│  │  Text Shaping         │  │
│  └──────────────────────┘  │
│                             │
│  ┌────── Editor Core ────┐  │
│  │  Buffers              │  │
│  │  Views                │  │
│  │  Commands             │  │
│  │  Selections           │  │
│  └──────────────────────┘  │
│                             │
│  IPC (Unix domain sockets)  │
│                             │
│  ┌────── Plugin Host ─────┐ │
│  │  Python Runtime        │ │
│  │  Packages              │ │
│  │  LSP / Tools           │ │
│  └───────────────────────┘ │
└─────────────────────────────┘
```

---

## 🌙 Luna-UI — Why Moth Can Be Sublime

**Luna-UI** is the reason this project exists at all.

### What Luna-UI Is
A **from-scratch, cross-platform UI and rendering engine**, written in Swift, designed specifically for editor-class applications.

It provides:
- Native window creation (macOS + Linux)
- GPU-accelerated rendering (CPU fallback)
- Deterministic input handling
- Pixel-perfect custom widgets
- Exact text metrics and cursor positioning
- First-class support for:
  - Ligatures
  - Complex scripts
  - High-DPI rendering

### Why Not Use Existing UI Toolkits?
General UI frameworks optimize for:
- Forms
- Buttons
- Dialogs

Editors need:
- Absolute control over text
- Predictable timing
- Zero layout surprises
- Maximum performance

Sublime solved this with a custom engine.  
**Moth does the same — openly — with Luna-UI.**

---

## 🧪 Project Status & Roadmap

### ✅ Phase 0 — Foundation *(Complete)*
- Swift toolchain validated on Linux and macOS
- Unix domain socket IPC
- JSON-based protocol
- Separate plugin host process

### ✅ Phase 0b — Persistent Runtime *(Complete)*
- Long-running app lifecycle
- IPC alongside UI event loop
- Confirms editor-class architecture

### 🚧 Phase 1 — Luna-UI Core *(In Progress)*
- Native windowing
- Render loop
- Input abstraction
- Text shaping pipeline

### 🔮 Phase 2 — Editor Core
- Buffers, views, selections
- Undo/redo model
- Multi-cursor editing
- Command engine

### 🔮 Phase 3 — Sublime-Compatible Ecosystem
- Python plugin host
- Package manager
- Command palette
- Key bindings
- Themes

---

## 📁 Repository Structure

```
src/
  IPC/              # IPC protocol and transport
  PluginHost/       # Out-of-process plugin runtime
  Apps/
    Linux/          # Linux entry point
    Mac/            # macOS entry point
```

> **Luna-UI lives in a separate repository** and will be integrated once stable.

---

## 🧠 Why This Project Exists

Sublime Text proved that:
- Editors can be fast
- Native UI matters
- Plugins can be elegant

Moth-Text asks:

> **What if we rebuilt Sublime today — openly, cleanly, and for the long term?**

---

## 🦋 Final Word

**Moth is Sublime.**

Not by copying code —  
but by honoring the ideas that made Sublime great  
and re-implementing them for the next decade.
