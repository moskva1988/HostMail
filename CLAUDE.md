# HostMail — AI Email Client

## Project Description
Native iOS email client with built-in AI assistant. BYOK model (user provides own API key).

- **Stack**: SwiftUI, MailCore2, Core Data/SQLite, StoreKit 2, AdMob, Whisper API
- **Mail**: IMAP/SMTP via MailCore2 — local storage on device
- **AI**: User-provided API key (no backend server needed)
- **Monetization**: Free (ads) / Pro $5/mo (ad-free + priority AI)

## Core Features
- Auto-reply drafting, inbox categorization
- Voice + text commands (Whisper API)
- Everything on-device + user's API key

## Rules
1. **PLAN before action** — always send plan and wait for approval
2. **No code without approval** — user knows Apple/architecture constraints
3. **Legend integrity** — part of Host* app family (HostCheck, HostShell, HostMail)
4. **After every commit** — always `git push origin main`
5. **Targeted edits only** — never replace entire function for small change
6. **MVP scope** — separate MVP from nice-to-have; flag scope creep
7. **Never delete binaries** — keep old frameworks during migration

---

## Active Branch: build-deploy

# Branch: build-deploy

Сборка и развёртывание: iOS сборка, подпись, TestFlight, App Store.

## Workflow
- Claude пишет код на Linux (`/root/HostMail`) и пушит в git
- Пользователь делает `pull` на Mac и собирает/тестирует в Xcode
- Claude НЕ может собирать iOS-проекты на Linux (нужен Xcode/macOS)
- После любого изменения: коммит + `git push origin main`

## Сборка
- XcodeGen: `xcodegen generate` → HostMail.xcodeproj
- Таргеты: iOS 17+, macOS 14+
- SPM: HostMailCore как shared framework
- project.yml — конфигурация XcodeGen

## Host* семейство
- HostMail — часть семейства Host* приложений (HostCheck, HostShell, HostMail)
- Legend integrity — соблюдать единый стиль/бренд

## Репо
- GitHub public repo
- Remote: https://github.com/moskva1988/HostMail.git (public)

## Текущее состояние
- Шаг 1 выполнен: 21 файл, скелет проекта
- git init + первый коммит готовы к push