# HostMail

Native iOS + macOS email client with built-in AI assistant.

Part of the Host* app family (HostCheck, HostShell, HostMail).

## Stack

- **UI**: SwiftUI (iOS 17+, macOS 14+)
- **Mail**: MailCore2 (IMAP/SMTP) — local storage on device
- **Storage**: Core Data with CloudKit sync
- **AI**: Apple Foundation Models (default, on-device) + BYOK for Claude / OpenAI / Yandex / GigaChat
- **Monetization**: StoreKit 2 (Pro $5/mo, ad-free) + AdMob (Free tier)

## Project layout

```
HostMail/
├── project.yml               # XcodeGen config — generates HostMail.xcodeproj
├── HostMailCore/             # Shared Swift Package (iOS + macOS)
│   └── Sources/HostMailCore/
│       ├── Models/           # User-facing data types
│       ├── Storage/          # Core Data + CloudKit
│       ├── Mail/             # MailCore2 wrapper
│       ├── AI/               # AIProvider protocol + implementations
│       ├── Auth/             # Keychain access
│       ├── Sync/             # CloudKit sync logic
│       └── UI/               # Cross-platform SwiftUI views
├── HostMail-iOS/             # iOS app target
└── HostMail-macOS/           # macOS app target
```

## Build (macOS only — requires Xcode)

### One-time setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   brew install xcodegen
   ```

2. Clone and generate the Xcode project:
   ```bash
   git clone <repo-url> HostMail
   cd HostMail
   xcodegen generate
   open HostMail.xcodeproj
   ```

### Regenerating the project

Whenever `project.yml` or `HostMailCore/Package.swift` change:

```bash
xcodegen generate
```

The `.xcodeproj` is **not** checked into git — it's regenerated from `project.yml`.

### Running

- Select scheme `HostMail-iOS` → build & run on simulator or device
- Select scheme `HostMail-macOS` → build & run on Mac

## AI provider setup

Out of the box, HostMail uses **Apple Foundation Models** (on-device, free, requires iOS 26+ / macOS 26+). No API key needed.

If you want to use Claude, OpenAI, Yandex, or GigaChat, add your own API key in **Settings → AI**. Keys are stored in Keychain and synced via iCloud (per-user, private).

## Development workflow

- **Linux** (`/root/HostMail`): code development, commits, git push
- **macOS**: pull, `xcodegen generate` if `project.yml` changed, build & test in Xcode

## Status

**v0.1 MVP — in progress.** See project board for roadmap.
