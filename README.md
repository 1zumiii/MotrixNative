# Motrix Native

Native macOS menu bar download manager powered by its own bundled aria2 engine.

## What works

- Runs as a menu bar app with no Dock icon.
- Shows a Dock icon while the main window is open, then hides back to the menu bar when the window is closed.
- Stores all runtime data in `~/Library/Application Support/Motrix Native`.
- On first launch, copies compatible settings and `download.session` from Motrix when available.
- Uses a bundled aria2 binary and configuration; the original Motrix app is not required at runtime.
- Connects to an already-running compatible aria2 RPC server, or starts its own bundled engine.
- Shows weighted download progress in the menu bar with a compact ring icon.
- Uses a warning status icon when the aria2 RPC engine is unavailable.
- Provides a SwiftUI native task window with rounded sidebar filters, search, and grouped task cards.
- Includes a preferences page for key Motrix basic/advanced settings.
- Adds a compact add-task sheet for URLs and `.torrent` files.
- Shows active, waiting, and stopped task counts.
- Lists active, waiting, and recent stopped tasks.
- Adds HTTP/FTP/magnet links.
- Pauses, resumes, and removes tasks.
- Provides task context menus for common operations.
- Opens a native detail page with progress, transfer statistics, files, source, location, errors, and task ID.
- Saves settings to Motrix Native's independent `system.json` and `user.json`.
- Can disable BitTorrent seeding entirely; restarting the engine reloads the latest saved settings.
- Removes stale `.aria2` control files only after aria2 reports the task as fully complete.
- Provides high-throughput adaptive HTTP connection tuning with per-host learned profiles and a balanced 48-connection starting point.
- Opens task files, task locations, and the download directory.
- Keeps config, aria2 log, engine info, and restart controls under the Advanced submenu.
- Only the menu bar Quit command exits the app. Closing the main window just hides it.
- Registers and removes the main app through macOS Login Items when "Open at Login" changes.
- Sends native download-complete notifications, including when a BitTorrent task starts seeding.
- Applies the configured removal confirmation in both the main window and menu bar menu.
- Saves the aria2 session and requests an RPC shutdown before terminating the owned engine.
- Shows a small engine info panel with the inherited connection/split/limit values.
- Monitors RPC health and attempts to restart the bundled aria2 engine with backoff when it becomes unavailable.
- Provides a manual "Restart Engine" menu item.

## Build

```sh
cd MotrixNative
xcrun swift build
```

## Package

```sh
MotrixNative/Scripts/package-app.sh
```

The development app bundle is written to:

```text
MotrixNative/.build/app/Motrix Native.app
```

## Notes

The packaged app is self-contained. Removing the original Motrix app does not remove Motrix Native's engine or settings. Launch Motrix Native once before deleting Motrix data so the one-time configuration and session migration can complete.
