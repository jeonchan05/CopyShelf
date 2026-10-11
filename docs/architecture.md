# Project structure

CopyShelf uses AppKit controllers with a coordinator and small services. SwiftPM separates the history model and file format in `ClipboardCore` from the macOS app in `CopyShelf`.

| Responsibility | Types |
| --- | --- |
| App lifecycle | `AppDelegate` forwards launch, activation, reopening, and termination. |
| App flows and composition | `AppCoordinator` owns the menu bar item, connects services, opens windows, and routes copy and paste requests. |
| Views and input | `HistoryPanel` renders history and handles search and selection. `SettingsWindowController` renders settings and records a shortcut. |
| Commands | `HotKeyController` validates and registers shortcuts before saving them. `LoginItemController` reads and changes the system login item state. |
| Clipboard services | `ClipboardMonitor`, `ClipboardWriter`, and `PasteService` handle clipboard access and paste attempts. |
| History repository | `HistoryStore` owns the current history and reports changes. `HistoryFile` validates and persists it; `HistoryWriter` coalesces disk writes. |
| Preferences | `AppPreferences` owns UserDefaults keys and validation. |
| Value models | `Clip`, `ClipboardImage`, `ClipboardHistory`, `PasteAttempt`, and `KeyboardShortcut` hold data and rules. |

AppKit delegates and data sources handle native view events. Controllers report actions through closures, with weak references where the coordinator or store owns the sender. Views do not start capture, perform paste, or write history files. The coordinator owns navigation and connects those actions to services.

System boundaries use dependency injection where a substitute is useful: `HotKeyService` and `LoginItemService` protocols, a pasteboard and read closures for capture, an isolated UserDefaults instance for preferences, and a file URL for history storage. Tests use these boundaries without reading a user's real history. Concrete value types remain concrete.

UI and live clipboard access stay on `MainActor`. Image conversion and coalesced file writes use separate queues; capture generations prevent stale work from returning after pause or clear. History writes use a lock to protect the pending snapshot and flush during normal termination. This preserves the same threading and storage boundaries when UI flows change.

To add a setting, put its rule and system operation in a controller or service, expose its state through `SettingsWindowController`, and connect it in `AppCoordinator`. A new history content type belongs in `ClipboardCore` first, then in capture, rendering, and clipboard writing.
