# MothText — Phase 0 (src layout)

This is the Phase 0 scaffold for **MothText** using the repo convention:

- **All project code lives under `src/`**
- `Package.swift` stays at the repo root

Phase 0 goal here:
- Verify **Unix-domain-socket IPC** works end-to-end (async-first message model, line-delimited JSON)
- Provide two executables:
  - `MothTextPluginHost` (server)
  - `MothTextLinux` (client ping demo; no GTK yet)

## Build

```bash
swift build
```

## Run (two terminals)

Terminal 1:
```bash
swift run MothTextPluginHost
```

Terminal 2:
```bash
swift run MothTextLinux
```

Expected output:
- Host prints it accepted a client and replied to `core.ping`
- Client prints the echoed message + server timestamp

## Next
Phase 0b will add:
- GTK4 window shell on Linux
- structured logs + reconnect loop
- start of EditorCore
