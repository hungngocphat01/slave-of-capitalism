# SwiftUI Native Frontend — Design Spec

**Date:** 2026-03-22
**Status:** Approved
**Target:** macOS 14+ (Sonoma)

## Overview

Port the existing SvelteKit/Tauri frontend to a native SwiftUI macOS application. The existing FastAPI backend is preserved and embedded as a subprocess. One backend endpoint must be added (budget monthly summary — see Prerequisites).

## Architecture: SwiftUI Shell + Embedded Backend

The SwiftUI app launches the PyInstaller-compiled `expense-manager-backend` binary as a child process on a random localhost port. All data flows through the existing REST API over HTTP. This preserves the battle-tested business logic, Alembic migrations, and SQLite database without modification.

```
┌─────────────────────────┐
│   SwiftUI macOS App     │
│                         │
│  Views ↔ ViewModels     │
│         ↕               │
│      APIClient          │
│    (URLSession)         │
│         ↕               │
│   http://127.0.0.1:PORT │
└────────────┬────────────┘
             │ subprocess
┌────────────▼────────────┐
│  expense-manager-backend│
│  (FastAPI + SQLite)     │
└─────────────────────────┘
```

### Why This Approach

- Zero backend rewrite — all financial logic, migrations, and 120 tests stay intact
- Proven pattern — identical to how Tauri embeds the backend today
- Incremental — only the UI layer is new
- Independent updates — backend (Python) and frontend (Swift) evolve separately

### Alternatives Considered

- **Pure SwiftUI + SwiftData**: Rejected. Would require rewriting all 6 services (50+ endpoints) of complex financial logic in Swift, reimplementing snapshot invalidation, linked entry state machines, installment logic, calibration resolution, and atomic bulk operations. High effort, high regression risk.
- **SwiftUI + GRDB (direct SQLite)**: Rejected. Same rewrite cost as above, plus replicating SQLAlchemy behavior and replacing Alembic with Swift-side migrations.
- **gRPC instead of REST**: Rejected. Localhost HTTP latency is sub-millisecond. gRPC adds protobuf compilation, heavier Swift dependencies, and breaks the existing Tauri frontend. No material benefit for a single-user local app.

## Prerequisites (Backend)

One missing endpoint must be added before the Summary screen can work:

- **`GET /budgets/summary/{year}/{month}?period_boundaries=7,14,21,31`** — returns `MonthlySummaryResponse` with budget vs actual per category, broken into sub-period columns. The Pydantic schema (`MonthlySummaryResponse`) exists but the service method and router endpoint are both missing. The current Tauri frontend calls this endpoint but it was never implemented.

- **`GET /linked-entries/transaction/{transaction_id}`** — returns the linked entry associated with a given transaction. The frontend's `ReimbursementsListModal` calls this. Neither the router endpoint nor service method exist.

Both endpoints need to be implemented before the SwiftUI app (or the current Tauri app) can fully function.

## Project Structure

```
SlaveOfCapitalism/
├── SlaveOfCapitalismApp.swift          # App entry, backend lifecycle
├── Info.plist
├── Resources/
│   └── expense-manager-backend         # Bundled PyInstaller binary
├── Backend/
│   ├── BackendManager.swift            # Launch/monitor/kill subprocess
│   └── APIClient.swift                 # HTTP client for all endpoints
├── Models/                             # Codable structs matching API schemas
│   ├── Wallet.swift
│   ├── Transaction.swift
│   ├── Category.swift
│   ├── LinkedEntry.swift
│   ├── Budget.swift
│   └── BalanceAudit.swift
├── ViewModels/                         # @Observable class per screen
│   ├── TransactionViewModel.swift
│   ├── WalletViewModel.swift
│   ├── SummaryViewModel.swift
│   ├── PendingViewModel.swift
│   ├── CategoryViewModel.swift
│   ├── BudgetViewModel.swift
│   ├── AuditViewModel.swift
│   └── SettingsViewModel.swift
├── Views/
│   ├── Sidebar.swift
│   ├── Transactions/
│   │   ├── TransactionListView.swift
│   │   ├── TransactionRow.swift
│   │   ├── AddTransactionSheet.swift
│   │   └── TransactionDetailSheet.swift
│   ├── Wallets/
│   │   ├── WalletListView.swift
│   │   ├── WalletRow.swift
│   │   └── WalletFormSheet.swift
│   ├── Summary/
│   │   ├── SummaryView.swift
│   │   └── DailyUsageChart.swift
│   ├── Pending/
│   │   └── PendingEntriesView.swift
│   ├── Categories/
│   │   └── CategoryManagementView.swift
│   ├── Data/
│   │   └── DataManagementView.swift
│   ├── Settings/
│   │   └── SettingsView.swift
│   ├── Audit/
│   │   └── AuditView.swift
│   └── Shared/
│       ├── Sheets/
│       │   ├── TransferSheet.swift
│       │   ├── CalibrateSheet.swift
│       │   ├── MarkAsSplitSheet.swift
│       │   ├── MarkAsLoanSheet.swift
│       │   ├── MarkAsDebtSheet.swift
│       │   ├── MarkAsInstallmentSheet.swift
│       │   ├── LinkToEntrySheet.swift
│       │   ├── ReclassifySheet.swift
│       │   ├── ResolveCalibrationSheet.swift
│       │   ├── MergeTransactionsSheet.swift
│       │   └── ReimbursementsSheet.swift
│       └── Components/
│           ├── MonthYearPicker.swift
│           ├── CurrencyField.swift
│           ├── TransactionInputRow.swift  # Quick-add row for transaction table
│           └── ConfirmationDialog.swift
└── Utilities/
    ├── Formatters.swift
    └── Settings.swift                  # UserDefaults wrapper
```

## Backend Process Management

`BackendManager` is an `@Observable` class injected into the SwiftUI environment.

**Lifecycle:**
1. **App launch** — Picks a random available port, launches the bundled binary via `Process` with `--port` and `--db-path` arguments
2. **Health polling** — Polls `GET /health` until backend responds (matches Tauri's `waitForBackend` pattern)
3. **Ready state** — Publishes `isReady: Bool`; views show a loading indicator until true
4. **App quit** — Sends SIGTERM, waits for graceful shutdown
5. **Crash recovery** — Monitors the process; if it dies, shows an error banner with "Retry" button. On retry, restarts the subprocess and re-polls health.
6. **Settings change (database path)** — When the user changes the database path in Settings, `BackendManager` kills the current subprocess and relaunches with the new `--db-path` argument. Views reset to loading state during restart.

**Database location:** `~/Library/Application Support/SlaveOfCapitalism/expense.db` (macOS convention). Configurable in Settings.

**Note on CORS:** URLSession does not enforce CORS (browser-only mechanism). No CORS configuration is needed for the native app.

## API Client

A single `APIClient` class using `URLSession`. All methods are `async throws`.

### Endpoint Groups

**Wallets** (9 methods):
- `list() -> [WalletWithBalance]`
- `get(id:) -> WalletWithBalance`
- `create(_:) -> WalletResponse`
- `update(id:, _:) -> WalletResponse`
- `delete(id:)`
- `transfer(_:) -> WalletTransferResponse`
- `calibrate(id:, _:) -> TransactionResponse`
- `getAudits() -> [BalanceAuditResponse]`
- `createAudit(_:) -> BalanceAuditResponse`

**Transactions** (20 methods):
- `list(filters:) -> [TransactionWithDetails]`
- `get(id:) -> TransactionWithDetails`
- `create(_:) -> TransactionResponse`
- `update(id:, _:) -> TransactionResponse`
- `delete(id:)`
- `deleteMultiple(ids:)`
- `ignore(ids:)`
- `unignore(ids:)`
- `reclassify(id:, _:) -> TransactionResponse`
- `markAsSplit(id:, _:) -> LinkedEntryResponse`
- `markAsLoan(id:, _:) -> LinkedEntryResponse`
- `markAsDebt(id:, _:) -> LinkedEntryResponse`
- `markAsInstallment(id:, _:) -> LinkedEntryResponse`
- `unclassify(id:)`
- `unlink(id:)`
- `linkToEntry(_:) -> LinkedEntryResponse`
- `merge(_:) -> TransactionResponse`
- `resolveCalibration(id:, _:) -> ResolveCalibrationResponse`
- `bulkImport(_:) -> BulkImportResponse`
- `monthlySummary(month:) -> MonthlySummaryDict`

**Categories** (7 methods):
- `list() -> [CategoryWithSubcategories]`
- `create(_:) -> CategoryResponse`
- `update(id:, _:) -> CategoryResponse`
- `delete(id:, replacementCategoryId:, replacementSubcategoryId:)`
- `createSubcategory(categoryId:, _:) -> SubcategoryResponse`
- `updateSubcategory(id:, _:) -> SubcategoryResponse`
- `deleteSubcategory(id:, replacementCategoryId:, replacementSubcategoryId:)`

**Linked Entries** (12 methods):
- `list(linkType:, status:) -> [LinkedEntryWithDetails]`
- `pending() -> [LinkedEntryWithDetails]`
- `get(id:) -> LinkedEntryWithDetails`
- `getByTransaction(transactionId:) -> LinkedEntryWithDetails` *(prerequisite — endpoint missing, see Prerequisites)*
- `create(_:) -> LinkedEntryResponse`
- `update(id:, _:) -> LinkedEntryResponse`
- `delete(id:)`
- `linkTransaction(entryId:, _:) -> LinkedEntryResponse`
- `unlinkTransaction(entryId:, linkId:) -> LinkedEntryResponse`
- `linkTransactions(entryId:, transactionIds:) -> LinkedEntryResponse` *(backend route is `POST /transactions/link`, not on linked-entries router)*
- `summaryOwed() -> OwedSummary`
- `summaryDebt() -> DebtSummary`

**Budgets** (6 methods):
- `list(year:, month:, categoryId:) -> [BudgetWithCategory]`
- `create(_:) -> BudgetResponse`
- `update(id:, _:) -> BudgetResponse`
- `delete(id:)`
- `monthlySummary(year:, month:) -> MonthlySummaryResponse`
- `dailySummary(year:, month:) -> DailySummaryResponse`

### Error Handling

Typed `APIError` enum:
- `.notFound` (404)
- `.validationError(String)` (400/422)
- `.serverError(String)` (500)
- `.networkError(Error)` (connection refused, timeout)
- `.backendNotReady` (health check not yet passing)

ViewModels catch errors and surface them as user-facing alerts via `@Observable` error state.

## Data Models

Swift `Codable` structs mirroring the Pydantic schemas 1:1.

### Enums (String-backed, Codable)

```
TransactionDirection: inflow | outflow | reserved
TransactionClassification: expense | income | lend | borrow | debt_collection |
    loan_repayment | split_payment | transfer | installment | installmt_chrge
WalletType: normal | credit
LinkType: split_payment | loan | debt | installment
LinkStatus: pending | partial | settled
```

### Response Models (~15 structs)

`WalletResponse`, `WalletWithBalance`, `TransactionResponse`, `TransactionWithDetails`, `CategoryResponse`, `CategoryWithSubcategories`, `SubcategoryResponse`, `LinkedEntryResponse`, `LinkedEntryWithDetails`, `LinkedTransactionResponse`, `BudgetResponse`, `BudgetWithCategory`, `BalanceAuditResponse`, `MonthlySummaryResponse`, `DailySummaryResponse`, `DailyCategoryData`, `DailySubcategoryData`, `CategorySummary`, `SubcategorySummary`, `WalletTransferResponse`, `ResolveCalibrationResponse`

### Request Models (~15 structs)

`WalletCreate`, `WalletUpdate`, `TransactionCreate`, `TransactionUpdate`, `WalletTransferRequest`, `MarkAsSplitRequest`, `MarkAsLoanRequest`, `MarkAsDebtRequest`, `ReclassifyRequest`, `BulkActionRequest`, `BulkLinkRequest`, `TransactionMergeRequest`, `BulkImportRequest`, `BudgetCreate`, `BudgetUpdate`, `CalibrateWalletRequest`, `ResolveCalibrationRequest`, `LinkedEntryCreate`, `LinkedEntryUpdate`, `LinkTransactionRequest`, `BalanceAuditCreate`

## State Management

### Pattern: @Observable + async/await

Using Swift 5.9 Observation framework (no Combine, no ObservableObject/Published boilerplate).

### ViewModels (one per screen)

| ViewModel | Owns | Fetches on |
|-----------|------|------------|
| `TransactionViewModel` | transactions list, selected month, filters, selection set | month change, after any mutation |
| `WalletViewModel` | wallets list | appear, after create/edit/delete |
| `SummaryViewModel` | monthly summary, daily chart data | month change |
| `PendingViewModel` | pending entries grouped by type | appear, after link/unlink |
| `CategoryViewModel` | categories with subcategories | appear, after mutation |
| `BudgetViewModel` | budgets for current month | month change, after mutation |
| `AuditViewModel` | audit snapshots list | appear, after create |
| `SettingsViewModel` | UserDefaults-backed settings | appear |

### Shared State (Environment)

- **`APIClient`** — singleton, base URL set after backend is ready
- **`BackendManager`** — backend process state (`isReady`)
- **`AppSettings`** — `@Observable` class wrapping UserDefaults for currency, decimals, language
- **`CategoryStore`** — categories needed across screens (transaction forms, budget forms); fetched once, refreshed on mutation
- **`WalletStore`** — wallet list needed in transaction forms and transfers; shared in environment

### Data Flow

1. View appears → ViewModel calls `APIClient` method (`async`)
2. ViewModel updates its `@Observable` properties
3. View re-renders automatically
4. User action → ViewModel calls mutation endpoint → re-fetches affected data
5. Shared stores (categories, wallets) notify all consumers on change

## Navigation

Two-column `NavigationSplitView`:

```
┌──────────────┬─────────────────────────────────────┐
│  Sidebar     │  Detail                             │
│              │                                     │
│  Transactions│  (selected screen content)          │
│  Summary     │                                     │
│  Wallets     │                                     │
│  Pending     │                                     │
│  Categories  │                                     │
│  Data        │                                     │
│  ─────────── │                                     │
│  Audit       │                                     │
│  Settings    │                                     │
└──────────────┴─────────────────────────────────────┘
```

Navigation state is a `@State` enum in `ContentView`:

```swift
enum Screen: Hashable {
    case transactions, summary, wallets, pending
    case categories, data, audit, settings
}
```

All screens are top-level detail views. No deep navigation stacks. Modals are presented via `.sheet(item:)`.

## Screen-by-Screen Feature Mapping

### Transactions (main screen)

The most complex screen.

**Layout:** Toolbar with month/year picker and "Add Transaction" button. macOS `Table` with columns: date, description, wallet, category, direction+amount. Multi-row selection support.

**Interactions:**
- Month/year navigation (back/forward arrows + picker)
- Add transaction → sheet
- Click row → detail sheet (view/edit)
- Right-click → context menu: Edit, Delete, Mark as Split/Loan/Debt/Installment, Reclassify, Link to Entry, Unlink, Unclassify, Resolve Calibration, See Reimbursements
- Multi-select → toolbar: Delete Selected, Ignore/Unignore, Merge, Link to Entry
- Quick-add row at table bottom
- `Cmd+K` shortcut — appends "000" to the active amount field (convenience for VND/JPY currencies where amounts are in thousands)

**Context menu conditional logic:** Items shown based on transaction state (e.g., "Mark as Split" only for EXPENSE+OUTFLOW, "Resolve" only for `is_calibration`, "Reimbursements" only when linked entry exists).

### Summary

**Layout:** Month picker at top. Two sections:
1. **Budget overview** — List of categories: emoji + name, budget vs actual, progress bar, percentage. Expandable to subcategories. Supports period columns (sub-monthly boundaries, default [7, 14, 21, 31]) via `period_boundaries` query parameter. Uses `/budgets/summary/{year}/{month}` endpoint (see Prerequisites).
2. **Daily usage chart** — Swift Charts `AreaMark` showing cumulative daily spending vs budget line. Uses `/budgets/daily-summary` endpoint.

### Wallets

**Layout:** Grid or list of wallet cards: emoji, name, type badge, balance, available credit (credit wallets). Right-click context menu: Edit, Delete, Calibrate, Transfer.

**Actions:** Add Wallet → sheet. Transfer → sheet. Calibrate → sheet.

### Pending

**Layout:** Three collapsible sections:
1. **People owe me** — splits + loans (PENDING/PARTIAL)
2. **I owe** — debts (PENDING/PARTIAL)
3. **Installments** — installment plans

Each row: counterparty, amounts, status badge, original transaction info. Expandable to show linked transactions. Link Transaction button per entry.

### Categories

**Layout:** List with disclosure groups. Category rows: emoji + name + color. Expand for subcategories. Swipe-to-delete with replacement picker. Add buttons for categories and subcategories.

### Data Management

**Layout:** Action list:
- Import from PayPay CSV → multi-step sheet wizard
- Export (placeholder)

**PayPay Import Wizard** — 4-step flow presented as a sheet with step navigation:

1. **File Selection** — `fileImporter()` modifier for CSV file + optional rules JSON file. Validates CSV format before proceeding.
2. **Wallet Mapping** — Maps PayPay payment methods to app wallets. Persists mappings in UserDefaults for reuse across imports.
3. **Preview** — Table showing parsed transactions with auto-categorization from rules. User can review and correct before importing.
4. **Confirm & Import** — Calls `/transactions/bulk-import` atomically. Shows success/error result.

The CSV parsing and rule engine logic from `frontend/src/lib/paypay-importer/` (parser, rule compiler, rule executor, transformer, translator, wallet mapper) must be reimplemented in Swift. This is ~500 lines of domain-specific parsing logic.

### Audit

**Layout:** "Take Snapshot" button + list of audit records: date, wallet balances, debts, owed, net position.

### Settings

**Layout:** macOS `Form`:
- Currency symbol (text field)
- Decimal places (stepper 0-4)
- Language (picker: English/Vietnamese)
- Database path (text field + `NSOpenPanel` folder picker)
- Backend port (auto/custom)

## Deployment & Build

### App Bundle

```
SlaveOfCapitalism.app/Contents/
├── MacOS/SlaveOfCapitalism           # Swift executable
├── Resources/expense-manager-backend # PyInstaller binary (~30MB)
├── Info.plist
└── Frameworks/
```

Backend binary added via "Copy Bundle Resources" build phase. Located at runtime via `Bundle.main.url(forResource:)`.

### Build Steps

1. Build backend binary via `make backend` (existing PyInstaller pipeline)
2. Place binary in `Resources/`
3. Standard Xcode build for SwiftUI macOS target

### Dependencies

**Zero third-party Swift packages:**
- `URLSession` — HTTP
- `JSONDecoder`/`JSONEncoder` — serialization
- Swift Charts — daily usage chart (built into macOS 14+)
- `@Observable` — state management (macOS 14+ / Swift 5.9)

### Signing & Distribution

**Distribution: Developer ID only** (direct download, not Mac App Store). MAS is incompatible with embedding a PyInstaller binary that extracts and executes code from temp directories.

**Signing strategy:**
1. The SwiftUI app is signed with a Developer ID certificate
2. The embedded PyInstaller binary must be codesigned with the same team identity (`codesign --deep --force --sign "Developer ID Application: ..."`)
3. The app requires `com.apple.security.cs.disable-library-validation` entitlement (PyInstaller extracts dylibs at runtime)
4. For notarization: run `xcrun notarytool submit` on the final `.app` bundle. PyInstaller's internal dylibs may need individual signing — test during first notarization attempt and fix as needed

### Localization

English and Vietnamese via `.xcstrings` string catalog (Xcode 15+). ~695 strings translated from `translations.ts`.

### Minimum Deployment Target

macOS 14 Sonoma — required for `@Observable`, Swift Charts, and `Table` improvements.

## Error & Empty States

**Backend lifecycle errors:**
- Backend fails to start → full-screen error with "Retry" and "Open Settings" (to change DB path/port)
- Backend crashes mid-session → error banner at top of current screen with "Reconnecting..." and auto-retry
- Backend unreachable after retry → error screen with diagnostic info (port, DB path, last error)

**API errors:**
- Network/server errors → alert dialog with error message and "OK" to dismiss
- Validation errors (400/422) → inline error messages on the relevant form fields
- 404 → silent refresh of the current list (item was deleted elsewhere)

**Empty states:**
- No transactions for month → centered message "No transactions in [Month Year]" with "Add Transaction" button
- No wallets → prompt to create first wallet
- No budgets → "No budgets set for this month" with "Create Budget" button
- No pending entries → "All settled" message per section

## Keyboard Shortcuts

| Shortcut | Action | Context |
|----------|--------|---------|
| `Cmd+K` | Append "000" to amount field | Any amount input (VND/JPY convenience) |
| `Cmd+N` | Add new transaction | Transactions screen |
| `Cmd+Delete` | Delete selected | Transactions screen with selection |
| `Escape` | Dismiss sheet/cancel | Any sheet |

Additional shortcuts may be added during implementation; these are the minimum set.

## Testing Strategy

- **APIClient**: Protocol-based with a `MockAPIClient` conformance for unit testing ViewModels without a running backend
- **ViewModels**: XCTest unit tests using `MockAPIClient` — verify state transitions, error handling, data transformation
- **Integration**: Manual testing against the real backend (same test patterns as the existing Tauri app)
- **UI tests**: Deferred to post-launch; focus on ViewModel coverage first

## Migration from Tauri App

- **Database**: The SwiftUI app defaults to `~/Library/Application Support/SlaveOfCapitalism/expense.db`. On first launch, if this file doesn't exist but the Tauri-era database exists at the previous path, offer to copy or point to it via Settings.
- **Settings**: Currency, language, and decimal preferences must be re-entered (Tauri stores them in localStorage, not accessible from Swift). This is acceptable for a one-time migration.
- **Coexistence**: Both apps can run simultaneously against different database files, or the same file if only one is active at a time (SQLite handles single-writer).

## Scope Summary

| Area | Count |
|------|-------|
| Screens | 8 |
| Sheets/modals | 14 |
| ViewModels | 8 |
| API methods | ~54 |
| Codable models | ~35 structs/enums |
| Shared components | ~6 |
| Third-party dependencies | 0 |
| Backend changes required | 2 endpoints (budget monthly summary, linked entry by transaction) |
