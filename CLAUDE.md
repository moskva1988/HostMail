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

## Active Branch: settings

# Branch: settings

Параметры: API ключи пользователя, предпочтения, конфигурация.

## API-ключи
- 4 BYOK провайдера: Claude, OpenAI, Yandex Alice, GigaChat
- MVP: только ввод API key, OAuth/подписка отложены
- Хранение через Keychain (HostMailCore/Auth/)

## Синхронизация настроек
- CloudKit/iCloud синхронизация между Mac ↔ iOS
- API-ключи через Keychain-CloudKit
- Настройки, категории, AI-предпочтения — всё синхронизируется

## MVP шаги
- Шаг 6: UI настройки IMAP/SMTP + Keychain
- Шаг 11: BYOK экран — ввод API-ключей для 4 провайдеров
- Шаг 12: Переключатель AI-провайдера в настройках

---

## Cross-Branch Changes (from other branches)
Review these for context — other branches made these changes:

# Cross-Branch Change Tracker


## 2026-04-21 14:47 [build-deploy]
- Created commit be8668c modifying 21 files with 437 lines of code
- Затрагивает: build-deploy

---

## Active Branch: ai-assistant

# Branch: ai-assistant

AI-помощник: автоответы, категоризация входящих, интеллектуальные команды.

## AI-провайдеры
MVP поддерживает 5 реализаций протокола `AIProvider`:
1. **ApplePrivateProvider** — Apple Foundation Models (default, без ключа)
2. **ClaudeProvider** — Anthropic Claude (BYOK)
3. **OpenAIProvider** — OpenAI (BYOK)
4. **YandexProvider** — Yandex Alice (BYOK)
5. **GigaChatProvider** — GigaChat Sber (BYOK)

**MVP — только API key (BYOK)**. Режим подписок/OAuth отложен (v0.2+).
Claude Code CLI bridge — тоже v0.2 (нишевая фича, Mac-only).

Протокол `AIProvider` спроектирован так, чтобы добавить новый провайдер одним файлом без рефакторинга.

У пользователя НЕТ API-ключа Claude — тестирование через Apple Foundation Models, Ollama, бесплатные кредиты Anthropic Console.

## Функции
- **Draft Reply** (Шаг 10 MVP) — кнопка "AI reply" → провайдер → вставка в compose
- Категоризация входящих писем
- Текстовые команды через AI
- Всё на устройстве + ключ пользователя (без бэкенда)

## Файлы
- HostMailCore/Sources/HostMailCore/AI/AIProvider.swift — протокол
- HostMailCore/Sources/HostMailCore/AI/ApplePrivateProvider.swift
- HostMailCore/Sources/HostMailCore/AI/ClaudeProvider.swift
- HostMailCore/Sources/HostMailCore/AI/OpenAIProvider.swift
- HostMailCore/Sources/HostMailCore/AI/YandexProvider.swift
- HostMailCore/Sources/HostMailCore/AI/GigaChatProvider.swift

## v0.2 (после MVP)
- Whisper API голосовые команды
- Claude Code CLI bridge

---

## Cross-Branch Changes (from other branches)
Review these for context — other branches made these changes:

# Cross-Branch Change Tracker


## 2026-04-21 14:47 [build-deploy]
- Created commit be8668c modifying 21 files with 437 lines of code
- Затрагивает: build-deploy