# Vault

> A minimalist, local-first personal finance tracker for macOS — with a built-in AI financial advisor (Deepseek-R1) and on-device speech input (WhisperKit).

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?logo=swift" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/UI-SwiftUI-blue?logo=swift" alt="SwiftUI">
  <img src="https://img.shields.io/badge/AI-100%25%20local-green" alt="Local AI">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

---

## Why Vault?

Most personal finance apps are either bloated SaaS that ingest your bank data, or barebones spreadsheets. **Vault** sits in the middle: a native macOS app that gives you a **CFO-grade dashboard** of your wealth, runs an **AI financial advisor on your own machine**, and never sends a byte off your computer.

It is designed to feel like the kind of dashboard a private wealth manager would hand a client — net worth, asset allocation, cash-flow forecasting, runway, savings rate — but built for **one person, on their own Mac, with full privacy.**

> **Add to your screenshots / GIF here.** _Place captures into `docs/assets/` and reference them below._

```
docs/assets/dashboard.png   ← suggested name
docs/assets/assistant.gif
docs/assets/forecast.png
```

---

## ✨ Features

### 📊 Wealth dashboard
- **Net worth** = assets − liabilities, rolled up across every account
- **Cash-flow** (month-to-date + 6-month history bar chart)
- **Savings rate** vs. 20 % target
- **Runway** in months (liquidity ÷ average burn)
- **Asset allocation** donut (cash / invested / property / other)
- **Top spending categories** of the month
- **Upcoming recurring transactions**

### 💳 Multi-account banking simulation
Six account types with their own semantics:

| Kind          | Balance source                | Counts as |
|---------------|-------------------------------|-----------|
| Checking      | Sum of transactions           | Liquid asset |
| Savings       | Sum of transactions           | Liquid asset |
| Cash          | Sum of transactions           | Liquid asset |
| Investment    | Manual valuation              | Invested asset |
| Real estate   | Manual valuation              | Property |
| Credit / debt | Sum of transactions           | **Liability** (negative net worth) |

### 🔁 Recurring transactions
Salary, rent, subscriptions, passive income, automated investments — defined once with a cadence (`weekly` / `biweekly` / `monthly` / `quarterly` / `yearly`), then **auto-applied** when due. Each generated transaction is linked back to its source recurrence.

### 📈 Forecasting engine
A month-by-month projection of your net worth over 3 / 6 / 12 / 24 / 60 months, computed from your **active recurrences**. Two charts:
- Net worth trajectory (area)
- Cumulative income vs. cumulative expense

### 🎯 Budgets
Per-category monthly ceilings + automatic **50 / 30 / 20 rule** dashboard (needs / wants / savings) computed from transaction categories.

### 🤖 AI Assistant (100 % local)
A chat assistant that:
- Runs **Deepseek-R1 14B** via [Ollama](https://ollama.com) on your local machine
- Receives a **structured summary of your real financial situation** as system context (no hallucinated numbers)
- Streams responses with separated **reasoning** (`<think>` block) and **answer**
- Accepts **voice input** via [WhisperKit](https://github.com/argmaxinc/WhisperKit) running Whisper Large-v3 on the Apple Neural Engine
- Persists conversations in `~/Library/Application Support/Vault/conversation.json`

Nothing leaves your Mac. No telemetry. No accounts. No subscription.

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                        │
│  Dashboard · Accounts · Transactions · Recurring · Forecast │
│            · Budgets · Assistant · Settings                 │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
               ▼                              ▼
       ┌──────────────┐               ┌───────────────┐
       │    Store     │◀─────────────▶│ ChatViewModel │
       │ (ObservableO)│               │               │
       └──────┬───────┘               └───┬───────┬───┘
              │                           │       │
              ▼                           ▼       ▼
     ┌────────────────┐         ┌──────────┐  ┌────────────────┐
     │ JSON on disk   │         │LLMClient │  │SpeechRecognizer│
     │ store.json     │         │(Ollama)  │  │(WhisperKit)    │
     └────────────────┘         └────┬─────┘  └──────┬─────────┘
                                     │               │
                                     ▼               ▼
                              ┌───────────┐   ┌──────────────┐
                              │  Ollama   │   │ Hugging Face │
                              │ localhost │   │  (1st run)   │
                              │  :11434   │   └──────────────┘
                              └───────────┘
```

### Why these choices

| Concern              | Decision                       | Rationale |
|----------------------|--------------------------------|-----------|
| UI framework         | SwiftUI + Swift Charts         | Native fluidity, declarative, zero overhead, free dark mode |
| Persistence          | Plain `Codable` JSON           | No SwiftData macro toolchain dependency → builds with Command Line Tools only. Easy backup, easy debug, easy export. |
| Reactivity           | `ObservableObject` + `@Published` | Predictable, debuggable, low-magic |
| LLM                  | Deepseek-R1 14B via Ollama HTTP | Strong reasoning model, runs locally, separable `<think>` channel |
| Speech-to-text       | WhisperKit (Whisper Large-v3)  | Hugging Face models, runs on Apple Neural Engine via CoreML, no server |
| Concurrency          | `async/await` + `AsyncThrowingStream` | Native streaming of token deltas |
| Bundle production    | Plain shell script             | `.app` produced without Xcode — only Command Line Tools required |

---

## 🛠 Tech Stack

- **Swift 6.0** (language mode 5 for WhisperKit compatibility)
- **SwiftUI** + **Swift Charts**
- **WhisperKit** ≥ 0.9 — on-device speech-to-text
- **Ollama** local server — LLM inference
- **macOS 14+** (Sonoma) — minimum deployment target

No CocoaPods, no Carthage. SwiftPM only.

---

## 🚀 Quick Start

### Prerequisites

```bash
# Xcode Command Line Tools (gives you Swift + the macOS SDK)
xcode-select --install

# Ollama + the Deepseek-R1 model (≈ 9 GB)
brew install ollama
ollama pull deepseek-r1:14b
ollama serve   # if not already running as a service
```

> Optional: full Xcode is **not required** to build Vault. The included `build.sh` uses the Command Line Tools toolchain.

### Build & run

```bash
git clone https://github.com/<you>/vault.git
cd vault
./build.sh           # produces Vault.app
open Vault.app
```

First launch:
- A blank store is created at `~/Library/Application Support/Vault/store.json`
- 17 default categories and one Checking account are seeded
- On first use of the AI Assistant, WhisperKit downloads Whisper Large-v3 (~3 GB) from Hugging Face

### Development build

```bash
swift build            # debug build
swift run              # build & run as a CLI executable (no window chrome)
./build.sh             # release build wrapped into a proper .app bundle
```

---

## 📁 Project Structure

```
Vault/
├── Package.swift                 ← SwiftPM manifest (WhisperKit dependency)
├── build.sh                      ← Wraps `swift build` into a real .app bundle
├── Bundle/
│   └── Info.plist                ← Bundle metadata (mic permission, bundle ID)
├── Sources/Vault/
│   ├── VaultApp.swift            ← @main entry, store injection, scene setup
│   ├── Models/                   ← Pure value types (Codable, no framework deps)
│   │   ├── Account.swift
│   │   ├── Transaction.swift
│   │   ├── RecurringTransaction.swift
│   │   ├── Category.swift
│   │   └── Budget.swift
│   ├── Services/                 ← Domain logic, no SwiftUI
│   │   ├── Store.swift           ← Persistence + lookups + mutations
│   │   ├── AnalyticsEngine.swift ← Net worth, cash-flow, ratios, runway
│   │   ├── ForecastEngine.swift  ← Monthly net worth projection
│   │   ├── RecurrenceEngine.swift← Auto-applies due recurrences
│   │   ├── SeedData.swift        ← First-launch bootstrap
│   │   ├── LLMClient.swift       ← Ollama streaming + <think> parser
│   │   ├── SpeechRecognizer.swift← WhisperKit + AVAudioRecorder
│   │   ├── FinancialContext.swift← Store → text summary for LLM
│   │   └── ChatViewModel.swift   ← Conversation state + persistence
│   ├── Theme/                    ← Design system
│   │   ├── Theme.swift           ← Colors, palette, spacing constants
│   │   └── Formatters.swift      ← Money, Date, Percentage formatters
│   └── Views/                    ← SwiftUI screens
│       ├── RootView.swift        ← NavigationSplitView + sidebar
│       ├── Components/           ← Reusable UI (Card, Pill, MarkdownText)
│       ├── Dashboard/
│       ├── Accounts/
│       ├── Transactions/
│       ├── Recurring/
│       ├── Forecast/
│       ├── Budget/
│       ├── Assistant/
│       └── Settings/
└── docs/
    └── assets/                   ← Put screenshots / GIFs here
```

---

## 🧮 Financial concepts

The dashboard implements ratios and rules of thumb from standard personal finance and wealth management practice:

- **Net worth** = Σ(assets) − Σ(liabilities)
- **Savings rate** = (income − expense) / income — target ≥ 20 %
- **Runway** = liquid assets / avg monthly expenses — target ≥ 6 months
- **50 / 30 / 20 rule** — needs (fixed + variable) / wants (discretionary) / savings
- **Asset allocation** — diversification across liquid / invested / property / other
- **Cash-flow forecasting** — extrapolation of recurring streams over a horizon

Each is computed in [`AnalyticsEngine.swift`](Sources/Vault/Services/AnalyticsEngine.swift) and [`ForecastEngine.swift`](Sources/Vault/Services/ForecastEngine.swift) — pure, testable functions over the Store.

---

## 🤖 AI Assistant — design notes

- **System context injection** — before each user message, `FinancialContext.summary(for:)` serialises the current Store state into a structured Markdown brief (net worth, accounts with balances, cash-flow ratios, top expenses, recurrences, last 15 transactions). The LLM never has to ask "what is your balance?" — it already knows.
- **`<think>` channel separation** — Deepseek-R1 emits reasoning inline with `<think>…</think>` tags. `LLMClient` is a small state machine that splits the stream into `.thinking` and `.answer` channels with a tail-buffer trick to avoid cutting tag boundaries mid-chunk.
- **Block-aware Markdown rendering** — [`MarkdownText`](Sources/Vault/Views/Components/MarkdownText.swift) parses the response into structured blocks (headings, paragraphs, lists, code) and renders each with explicit vertical spacing. Inline formatting uses `AttributedString(markdown:)`.
- **Voice in French (or whichever locale)** — WhisperKit is invoked with `DecodingOptions(task: .transcribe, language: "fr", detectLanguage: false)` to prevent auto-translation to English.

---

## ⚙️ Configuration

Stored under `~/Library/Application Support/Vault/`:

| File                | Purpose                                |
|---------------------|----------------------------------------|
| `store.json`        | All accounts, transactions, categories, budgets, recurrences |
| `conversation.json` | Chat history with the AI assistant     |

Stored in `UserDefaults`:

| Key                  | Default  | Notes                          |
|----------------------|----------|--------------------------------|
| `vault.currencyCode` | `"EUR"`  | EUR / USD / GBP / CHF / JPY    |
| `vault.colorScheme`  | `"system"` | `"system"` / `"light"` / `"dark"` |

---

## 🗺 Roadmap

- [ ] CSV / OFX bank statement import
- [ ] Savings goals with progress tracking
- [ ] Scenario simulation in the Assistant (_"what if I save 500 € more per month?"_)
- [ ] Multi-currency support with FX rates
- [ ] iCloud sync (opt-in)
- [ ] iOS companion app
- [ ] Unit + snapshot tests for the engines

---

## 🤝 Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow.

---

## 📜 License

[MIT](LICENSE) — do whatever you want, just keep the copyright.

---

<p align="center">
  Built with care for people who want to <strong>own their data and understand their money</strong>.
</p>
