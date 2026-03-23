# SwiftUI Native Frontend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the SwiftUI frontend work correctly end-to-end first (decode/runtime stability + build/test gate), then continue porting remaining screens while preserving the embedded FastAPI backend architecture.

**Architecture:** SwiftUI shell launches the PyInstaller-compiled backend as a child process on localhost. All data flows through REST/HTTP. Zero third-party Swift dependencies. @Observable pattern for state management.

**Tech Stack:** Swift 5.9+, SwiftUI (macOS 14+), URLSession, Swift Charts, XCTest

**Spec:** `docs/superpowers/specs/2026-03-22-swiftui-port-design.md`

---

## File Structure

```
SlaveOfCapitalism/                              # Xcode project root
├── SlaveOfCapitalism.xcodeproj/
├── SlaveOfCapitalism/
│   ├── SlaveOfCapitalismApp.swift              # App entry point, environment setup
│   ├── ContentView.swift                       # NavigationSplitView shell
│   ├── Info.plist
│   ├── SlaveOfCapitalism.entitlements          # disable-library-validation for PyInstaller
│   ├── Resources/
│   │   └── expense-manager-backend             # Bundled PyInstaller binary (build artifact)
│   ├── Backend/
│   │   ├── BackendManager.swift                # Subprocess lifecycle management
│   │   └── APIClient.swift                     # URLSession HTTP client (54 methods)
│   ├── Models/
│   │   ├── Enums.swift                         # TransactionDirection, Classification, WalletType, LinkType, LinkStatus
│   │   ├── Wallet.swift                        # WalletResponse, WalletWithBalance, WalletCreate, WalletUpdate, WalletTransferRequest/Response
│   │   ├── Transaction.swift                   # TransactionResponse, TransactionWithDetails, TransactionCreate, TransactionUpdate, + mark/merge/bulk request types
│   │   ├── Category.swift                      # CategoryResponse, CategoryWithSubcategories, SubcategoryResponse, CategoryCreate/Update, SubcategoryCreate/Update
│   │   ├── LinkedEntry.swift                   # LinkedEntryResponse, LinkedEntryWithDetails, LinkedTransactionResponse, LinkedEntryCreate/Update, LinkTransactionRequest, MarkAs*Request
│   │   ├── Budget.swift                        # BudgetResponse, BudgetWithCategory, BudgetCreate/Update, MonthlySummaryResponse, DailySummaryResponse, CategorySummary, etc.
│   │   └── BalanceAudit.swift                  # BalanceAuditResponse, BalanceAuditCreate
│   ├── Stores/
│   │   ├── CategoryStore.swift                 # @Observable shared category cache
│   │   ├── WalletStore.swift                   # @Observable shared wallet cache
│   │   └── AppSettings.swift                   # UserDefaults wrapper for currency, decimals, language, dbPath
│   ├── ViewModels/
│   │   ├── TransactionViewModel.swift          # Transactions screen state
│   │   ├── WalletViewModel.swift               # Wallets screen state
│   │   ├── SummaryViewModel.swift              # Summary screen state (budget + chart)
│   │   ├── PendingViewModel.swift              # Pending entries screen state
│   │   ├── CategoryViewModel.swift             # Category management state
│   │   ├── BudgetViewModel.swift               # Budget CRUD state (used within Summary)
│   │   ├── AuditViewModel.swift                # Audit screen state
│   │   └── SettingsViewModel.swift             # Settings screen state
│   ├── Views/
│   │   ├── Sidebar.swift                       # Sidebar with navigation items
│   │   ├── LoadingView.swift                   # Backend startup loading indicator
│   │   ├── ErrorView.swift                     # Backend error/crash screen
│   │   ├── Transactions/
│   │   │   ├── TransactionListView.swift       # Table with month picker, multi-select, context menu
│   │   │   ├── TransactionRow.swift            # Single table row formatting
│   │   │   ├── AddTransactionSheet.swift       # Create transaction form
│   │   │   └── TransactionDetailSheet.swift    # View/edit transaction
│   │   ├── Wallets/
│   │   │   ├── WalletListView.swift            # Wallet grid with summary cards
│   │   │   ├── WalletCard.swift                # Single wallet card
│   │   │   └── WalletFormSheet.swift           # Create/edit wallet
│   │   ├── Summary/
│   │   │   ├── SummaryView.swift               # Budget table + chart
│   │   │   └── DailyUsageChart.swift           # Swift Charts area chart
│   │   ├── Pending/
│   │   │   └── PendingEntriesView.swift        # Grouped pending entries
│   │   ├── Categories/
│   │   │   └── CategoryManagementView.swift    # Category editor with subcategories
│   │   ├── Data/
│   │   │   ├── DataManagementView.swift        # Import/export actions
│   │   │   └── PayPayImport/
│   │   │       ├── PayPayWizardSheet.swift     # 4-step wizard container
│   │   │       ├── PayPayFileStep.swift        # Step 1: file selection
│   │   │       ├── PayPayMappingStep.swift     # Step 2: wallet mapping
│   │   │       ├── PayPayPreviewStep.swift     # Step 3: preview table
│   │   │       ├── PayPayConfirmStep.swift     # Step 4: import confirmation
│   │   │       ├── PayPayParser.swift          # CSV parsing logic
│   │   │       ├── PayPayRuleEngine.swift      # Rule compilation + execution
│   │   │       └── PayPayTransformer.swift     # Row transformation + wallet mapping
│   │   ├── Audit/
│   │   │   └── AuditView.swift                 # Snapshot list + take snapshot
│   │   ├── Settings/
│   │   │   └── SettingsView.swift              # macOS Form with preferences
│   │   └── Shared/
│   │       ├── Sheets/
│   │       │   ├── TransferSheet.swift         # Wallet transfer
│   │       │   ├── CalibrateSheet.swift        # Balance calibration
│   │       │   ├── MarkAsSplitSheet.swift      # Split payment marking
│   │       │   ├── MarkAsLoanSheet.swift       # Loan marking
│   │       │   ├── MarkAsDebtSheet.swift       # Debt marking
│   │       │   ├── MarkAsInstallmentSheet.swift # Installment marking
│   │       │   ├── LinkToEntrySheet.swift      # Link transaction to entry
│   │       │   ├── ReclassifySheet.swift       # Change classification
│   │       │   ├── ResolveCalibrationSheet.swift # Resolve calibration
│   │       │   ├── MergeTransactionsSheet.swift  # Merge selected transactions
│   │       │   └── ReimbursementsSheet.swift   # View linked transactions
│   │       └── Components/
│   │           ├── MonthYearPicker.swift        # Month/year navigation control
│   │           ├── CurrencyField.swift         # Decimal input with Cmd+K support
│   │           └── ConfirmationDialog.swift    # Reusable delete confirmation
│   └── Utilities/
│       ├── Formatters.swift                    # Currency, date, number formatters
│       └── Localizable.xcstrings               # String catalog (EN + VI)
├── SlaveOfCapitalismTests/
│   ├── MockAPIClient.swift                     # Protocol-based mock for testing
│   ├── TransactionViewModelTests.swift
│   ├── WalletViewModelTests.swift
│   ├── SummaryViewModelTests.swift
│   ├── PendingViewModelTests.swift
│   ├── CategoryViewModelTests.swift
│   ├── BudgetViewModelTests.swift
│   ├── AuditViewModelTests.swift
│   ├── BackendManagerTests.swift
│   └── PayPayParserTests.swift
```

### Backend changes (prerequisite)

```
backend/
├── app/routers/budgets.py          # Modify: add GET /summary/{year}/{month} endpoint
├── app/routers/linked_entries.py   # Modify: add GET /transaction/{transaction_id} endpoint
├── app/services/budget_service.py  # Modify: add calculate_monthly_summary method (if missing)
├── tests/test_budget_summary.py    # Create: tests for monthly summary endpoint
└── tests/test_linked_entry_by_tx.py # Create: tests for linked entry by transaction lookup
```

---

## Task 1: Backend Prerequisites — Budget Monthly Summary Endpoint

The Summary screen depends on `GET /budgets/summary/{year}/{month}`. The `MonthlySummaryResponse` Pydantic schema and `calculate_monthly_summary` service method exist, but the router endpoint is missing.

**Files:**
- Modify: `backend/app/routers/budgets.py`
- Test: `backend/tests/test_budget_summary.py`

**Reference:**
- Schema: `backend/app/schemas/budget.py` — `MonthlySummaryResponse`, `CategorySummary`, `SubcategorySummary`
- Service: `backend/app/services/budget_service.py` — `calculate_monthly_summary(db, year, month, period_boundaries)`
- Existing router: `backend/app/routers/budgets.py` — has `GET /daily-summary/{year}/{month}` as a pattern to follow

- [ ] **Step 1: Write failing test for budget monthly summary endpoint**

Create `backend/tests/test_budget_summary.py`:
```python
"""Tests for GET /budgets/summary/{year}/{month} endpoint."""
from decimal import Decimal


def test_monthly_summary_empty(client):
    """Returns empty summary when no budgets exist."""
    resp = client.get("/api/budgets/summary/2026/3")
    assert resp.status_code == 200
    data = resp.json()
    assert data["year"] == 2026
    assert data["month"] == 3
    assert data["categories"] == []
    assert float(data["total_budget"]) == 0.0
    assert float(data["total_actual"]) == 0.0


def test_monthly_summary_with_budget_and_transactions(client, sample_wallet, sample_category):
    """Returns budget vs actual with category breakdown."""
    # Create a budget
    client.post("/api/budgets/", json={
        "category_id": sample_category["id"],
        "year": 2026,
        "month": 3,
        "amount": 500.00,
    })
    # Create an expense transaction
    client.post("/api/transactions/", json={
        "date": "2026-03-15",
        "wallet_id": sample_wallet["id"],
        "direction": "outflow",
        "amount": 150.00,
        "classification": "expense",
        "category_id": sample_category["id"],
    })
    resp = client.get("/api/budgets/summary/2026/3")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["categories"]) == 1
    cat = data["categories"][0]
    assert cat["category_id"] == sample_category["id"]
    assert float(cat["budget"]) == 500.0
    assert float(cat["actual"]) == 150.0


def test_monthly_summary_with_period_boundaries(client, sample_wallet, sample_category):
    """Period boundaries split spending into sub-period columns."""
    client.post("/api/budgets/", json={
        "category_id": sample_category["id"],
        "year": 2026,
        "month": 3,
        "amount": 1000.00,
    })
    client.post("/api/transactions/", json={
        "date": "2026-03-05",
        "wallet_id": sample_wallet["id"],
        "direction": "outflow",
        "amount": 100.00,
        "classification": "expense",
        "category_id": sample_category["id"],
    })
    resp = client.get("/api/budgets/summary/2026/3?period_boundaries=7,14,21,31")
    assert resp.status_code == 200
    data = resp.json()
    assert data["period_boundaries"] == [7, 14, 21, 31]
    cat = data["categories"][0]
    assert len(cat["periods"]) == 4
    assert cat["periods"][0] == 100.0  # day 5 falls in period 1 (1-7)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && python -m pytest tests/test_budget_summary.py -v
```
Expected: 404 errors (endpoint doesn't exist yet).

- [ ] **Step 3: Add the router endpoint**

In `backend/app/routers/budgets.py`, add this endpoint (follow the pattern of `get_daily_summary`):

```python
@router.get("/summary/{year}/{month}", response_model=MonthlySummaryResponse)
def get_monthly_summary(
    year: int,
    month: int,
    period_boundaries: str = Query(default="7,14,21,31", description="Comma-separated day boundaries"),
    db: Session = Depends(get_db),
):
    """Get budget vs actual summary for a month, optionally split by sub-periods."""
    boundaries = [int(x.strip()) for x in period_boundaries.split(",")]
    return budget_service.calculate_monthly_summary(db, year, month, boundaries)
```

Ensure imports include `Query` from fastapi and `MonthlySummaryResponse` from schemas.

**Important:** This endpoint must be placed BEFORE the `/{budget_id}` route to avoid path parameter conflicts.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && python -m pytest tests/test_budget_summary.py -v
```
Expected: All 3 tests PASS.

- [ ] **Step 5: Run full test suite to check for regressions**

```bash
cd backend && python -m pytest -x -q
```
Expected: All existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add backend/app/routers/budgets.py backend/tests/test_budget_summary.py
git commit -m "feat: add GET /budgets/summary/{year}/{month} endpoint"
```

---

## Task 2: Backend Prerequisites — Linked Entry by Transaction Endpoint

The Pending screen and ReimbursementsSheet depend on looking up a linked entry by its transaction ID.

**Files:**
- Modify: `backend/app/routers/linked_entries.py`
- Modify: `backend/app/services/linked_entry_service.py` (add lookup method if missing)
- Test: `backend/tests/test_linked_entry_by_transaction.py`

**Reference:**
- Existing router: `backend/app/routers/linked_entries.py` — has `GET /{entry_id}` as a pattern
- Service: `backend/app/services/linked_entry_service.py`

- [ ] **Step 1: Write failing test**

Create `backend/tests/test_linked_entry_by_transaction.py`:
```python
"""Tests for GET /linked-entries/transaction/{transaction_id} endpoint."""


def test_get_linked_entry_by_transaction_not_found(client):
    """Returns 404 when transaction has no linked entry."""
    resp = client.get("/api/linked-entries/transaction/99999")
    assert resp.status_code == 404


def test_get_linked_entry_by_transaction(client, sample_wallet, sample_category):
    """Returns linked entry for a transaction that has one."""
    # Create a transaction
    tx_resp = client.post("/api/transactions/", json={
        "date": "2026-03-15",
        "wallet_id": sample_wallet["id"],
        "direction": "outflow",
        "amount": 200.00,
        "classification": "expense",
        "category_id": sample_category["id"],
    })
    tx_id = tx_resp.json()["id"]

    # Mark it as split
    split_resp = client.post(f"/api/transactions/{tx_id}/mark-split", json={
        "counterparty_name": "Alice",
        "user_amount": 100.00,
    })
    assert split_resp.status_code == 200

    # Look up by transaction ID
    resp = client.get(f"/api/linked-entries/transaction/{tx_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["primary_transaction_id"] == tx_id
    assert data["counterparty_name"] == "Alice"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd backend && python -m pytest tests/test_linked_entry_by_transaction.py -v
```
Expected: 404/405 errors.

- [ ] **Step 3: Add service method and router endpoint**

In `backend/app/services/linked_entry_service.py`, add:
```python
def get_linked_entry_by_transaction(db: Session, transaction_id: int):
    """Get a linked entry by its primary transaction ID."""
    return db.query(LinkedEntry).filter(
        LinkedEntry.primary_transaction_id == transaction_id
    ).first()
```

In `backend/app/routers/linked_entries.py`, add (before `/{entry_id}` to avoid path conflicts):
```python
@router.get("/transaction/{transaction_id}", response_model=LinkedEntryWithDetails)
def get_linked_entry_by_transaction(transaction_id: int, db: Session = Depends(get_db)):
    """Get the linked entry associated with a transaction."""
    entry = linked_entry_service.get_linked_entry_by_transaction(db, transaction_id)
    if not entry:
        raise HTTPException(status_code=404, detail="No linked entry found for this transaction")
    return _entry_to_response(entry, db)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && python -m pytest tests/test_linked_entry_by_transaction.py -v
```

- [ ] **Step 5: Run full test suite**

```bash
cd backend && python -m pytest -x -q
```

- [ ] **Step 6: Commit**

```bash
git add backend/app/routers/linked_entries.py backend/app/services/linked_entry_service.py backend/tests/test_linked_entry_by_transaction.py
git commit -m "feat: add GET /linked-entries/transaction/{transaction_id} endpoint"
```

---

## Task 3: Xcode Project Setup

Create the Xcode project with correct structure, entitlements, and build settings.

**Files:**
- Create: `SlaveOfCapitalism/` directory with Xcode project
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/SlaveOfCapitalismApp.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ContentView.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/SlaveOfCapitalism.entitlements`

- [ ] **Step 1: Create Xcode project via command line**

```bash
cd /Volumes/Documents/sources/slave-of-capitalism
mkdir -p SlaveOfCapitalism/SlaveOfCapitalism
mkdir -p SlaveOfCapitalism/SlaveOfCapitalismTests
```

- [ ] **Step 2: Create the app entry point**

Create `SlaveOfCapitalism/SlaveOfCapitalism/SlaveOfCapitalismApp.swift`:
```swift
import SwiftUI

@main
struct SlaveOfCapitalismApp: App {
    @State private var backendManager = BackendManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(backendManager)
                .environment(backendManager.apiClient)
        }
    }
}
```

- [ ] **Step 3: Create placeholder ContentView**

Create `SlaveOfCapitalism/SlaveOfCapitalism/ContentView.swift`:
```swift
import SwiftUI

enum Screen: String, Hashable, CaseIterable {
    case transactions = "Transactions"
    case summary = "Summary"
    case wallets = "Wallets"
    case pending = "Pending"
    case categories = "Categories"
    case data = "Data"
    case audit = "Audit"
    case settings = "Settings"
}

struct ContentView: View {
    @Environment(BackendManager.self) private var backendManager
    @State private var selectedScreen: Screen = .transactions

    var body: some View {
        if !backendManager.isReady {
            LoadingView()
        } else {
            NavigationSplitView {
                Sidebar(selection: $selectedScreen)
            } detail: {
                Text("Select a screen") // Placeholder, replaced in Task 10
            }
        }
    }
}
```

- [ ] **Step 4: Create entitlements file**

Create `SlaveOfCapitalism/SlaveOfCapitalism/SlaveOfCapitalism.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

Note: Sandbox is disabled because the app needs to launch a subprocess and access user-selected database paths. `disable-library-validation` is required for PyInstaller's extracted dylibs.

- [ ] **Step 5: Create the Xcode project file**

Use `xcodegen` or create manually. The project needs:
- macOS 14.0 deployment target
- Swift 5.9+ language version
- Team signing with Developer ID
- "Copy Bundle Resources" phase for the backend binary
- Test target linked to main target

If xcodegen is available:
```bash
cd SlaveOfCapitalism && cat > project.yml << 'EOF'
name: SlaveOfCapitalism
options:
  bundleIdPrefix: com.slaveofcapitalism
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "16.0"
settings:
  SWIFT_VERSION: "5.9"
  MACOSX_DEPLOYMENT_TARGET: "14.0"
targets:
  SlaveOfCapitalism:
    type: application
    platform: macOS
    sources: [SlaveOfCapitalism]
    settings:
      CODE_SIGN_ENTITLEMENTS: SlaveOfCapitalism/SlaveOfCapitalism.entitlements
      PRODUCT_BUNDLE_IDENTIFIER: com.slaveofcapitalism.app
  SlaveOfCapitalismTests:
    type: bundle.unit-test
    platform: macOS
    sources: [SlaveOfCapitalismTests]
    dependencies:
      - target: SlaveOfCapitalism
EOF
xcodegen generate
```

Otherwise, create the project in Xcode: File > New > Project > macOS App, SwiftUI, Swift, name "SlaveOfCapitalism", target macOS 14.0.

- [ ] **Step 6: Create directory structure**

```bash
cd SlaveOfCapitalism/SlaveOfCapitalism
mkdir -p Backend Models Stores ViewModels Utilities Resources
mkdir -p Views/{Sidebar,Transactions,Wallets,Summary,Pending,Categories,Data/PayPayImport,Audit,Settings,Shared/Sheets,Shared/Components}
```

- [ ] **Step 7: Verify project compiles**

```bash
cd SlaveOfCapitalism && xcodebuild -scheme SlaveOfCapitalism -destination 'platform=macOS' build 2>&1 | tail -5
```
Expected: Build will fail due to missing types (BackendManager, Sidebar, LoadingView). That's fine — we're establishing the skeleton.

- [x] **Step 8: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "chore: create Xcode project skeleton for SwiftUI frontend"
```

---

## Task 4: Data Models — Enums and Codable Structs

All Swift types mirroring the backend Pydantic schemas. These compile independently and are needed by everything else.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Models/Enums.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Models/Wallet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Models/Transaction.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Models/Category.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Models/LinkedEntry.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Models/Budget.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Models/BalanceAudit.swift`

**Reference:**
- Backend schemas: `backend/app/schemas/` — all Pydantic models define the exact field names and types
- The backend uses `snake_case` JSON keys. Swift models should use `CodingKeys` or a `keyDecodingStrategy = .convertFromSnakeCase` on the decoder.

- [ ] **Step 1: Create Enums.swift**

```swift
import Foundation

enum TransactionDirection: String, Codable, CaseIterable {
    case inflow, outflow, reserved
}

enum TransactionClassification: String, Codable, CaseIterable {
    case expense, income, lend, borrow
    case debtCollection = "debt_collection"
    case loanRepayment = "loan_repayment"
    case splitPayment = "split_payment"
    case transfer
    case installment
    case installmtChrge = "installmt_chrge"
}

enum WalletType: String, Codable, CaseIterable {
    case normal, credit
}

enum LinkType: String, Codable, CaseIterable {
    case splitPayment = "split_payment"
    case loan, debt, installment
}

enum LinkStatus: String, Codable, CaseIterable {
    case pending, partial, settled
}
```

- [ ] **Step 2: Create Wallet.swift**

```swift
import Foundation

struct WalletResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let walletType: WalletType
    let creditLimit: Decimal
    let emoji: String?
    let createdAt: String
    let updatedAt: String
}

struct WalletWithBalance: Codable, Identifiable {
    let id: Int
    let name: String
    let walletType: WalletType
    let creditLimit: Decimal
    let emoji: String?
    let createdAt: String
    let updatedAt: String
    let currentBalance: Decimal
    let availableCredit: Decimal?
}

struct WalletCreate: Codable {
    let name: String
    var walletType: WalletType = .normal
    var creditLimit: Decimal = 0
    var emoji: String?
    var initialBalance: Decimal = 0
}

struct WalletUpdate: Codable {
    var name: String?
    var walletType: WalletType?
    var creditLimit: Decimal?
    var emoji: String?
}

struct WalletTransferRequest: Codable {
    let fromWalletId: Int
    let toWalletId: Int
    let amount: Decimal
    let description: String
    let date: String
    var time: String?
}

struct WalletTransferResponse: Codable {
    let outflowTransaction: TransactionResponse
    let inflowTransaction: TransactionResponse
}
```

- [ ] **Step 3: Create Transaction.swift**

```swift
import Foundation

struct TransactionResponse: Codable, Identifiable {
    let id: Int
    let date: String
    let time: String?
    let walletId: Int
    let direction: TransactionDirection
    let amount: Decimal
    let classification: TransactionClassification
    let description: String?
    let categoryId: Int?
    let subcategoryId: Int?
    let pairedTransactionId: Int?
    let isIgnored: Bool
    let isCalibration: Bool
    let createdAt: String
    let updatedAt: String
}

struct TransactionWithDetails: Codable, Identifiable {
    let id: Int
    let date: String
    let time: String?
    let walletId: Int
    let direction: TransactionDirection
    let amount: Decimal
    let classification: TransactionClassification
    let description: String?
    let categoryId: Int?
    let subcategoryId: Int?
    let pairedTransactionId: Int?
    let isIgnored: Bool
    let isCalibration: Bool
    let createdAt: String
    let updatedAt: String
    let walletName: String?
    let walletType: String?
    let categoryName: String?
    let subcategoryName: String?
    let hasLinkedEntry: Bool
    let isLinkedToEntry: Bool
    let linkedEntry: LinkedEntryResponse?
}

struct TransactionCreate: Codable {
    let date: String
    var time: String?
    let walletId: Int
    let direction: TransactionDirection
    let amount: Decimal
    let classification: TransactionClassification
    var description: String?
    var categoryId: Int?
    var subcategoryId: Int?
    var isIgnored: Bool = false
    var isCalibration: Bool = false
    var allowLargeCacheRebuild: Bool = false
}

struct TransactionUpdate: Codable {
    var date: String?
    var time: String?
    var walletId: Int?
    var direction: TransactionDirection?
    var amount: Decimal?
    var classification: TransactionClassification?
    var description: String?
    var categoryId: Int?
    var subcategoryId: Int?
    var isIgnored: Bool?
    var isCalibration: Bool?
    var allowLargeCacheRebuild: Bool?
}

struct ReclassifyRequest: Codable {
    let classification: TransactionClassification
}

struct BulkActionRequest: Codable {
    let transactionIds: [Int]
}

struct BulkLinkRequest: Codable {
    let transactionIds: [Int]
    let linkedEntryId: Int
}

struct TransactionMergeRequest: Codable {
    let transactionIds: [Int]
    let date: String
    let description: String
    var categoryId: Int?
    var subcategoryId: Int?
}

struct BulkImportRequest: Codable {
    let items: [BulkImportItem]
}

// BulkImportItem is a union type — transactions or transfers
// Use an enum with associated values and custom encoding
enum BulkImportItem: Codable {
    case transaction(TransactionCreate)
    case transfer(WalletTransferRequest)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .transaction(let tx): try container.encode(tx)
        case .transfer(let tr): try container.encode(tr)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let tx = try? container.decode(TransactionCreate.self) {
            self = .transaction(tx)
        } else {
            self = .transfer(try container.decode(WalletTransferRequest.self))
        }
    }
}

struct MonthlySummaryDict: Codable {
    let month: String
    let totalExpense: Decimal
    let categoryBreakdown: [String: Decimal]
}

struct ResolveCalibrationRequest: Codable {
    let date: String
    var time: String?
    let walletId: Int
    let direction: TransactionDirection
    let amount: Decimal
    let classification: TransactionClassification
    var description: String?
    var categoryId: Int?
    var subcategoryId: Int?
}

struct ResolveCalibrationResponse: Codable {
    let newTransaction: TransactionResponse
    let calibrationDeleted: Bool
    let updatedCalibration: TransactionResponse?
}

struct CalibrateWalletRequest: Codable {
    let correctBalance: Decimal
    let miscCategoryId: Int
}

struct BulkImportResponse: Codable {
    let importedCount: Int
    let message: String
}
```

- [ ] **Step 4: Create Category.swift**

```swift
import Foundation

struct CategoryResponse: Codable, Identifiable {
    let id: Int
    let name: String
    let emoji: String?
    let color: String?
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
}

struct CategoryWithSubcategories: Codable, Identifiable {
    let id: Int
    let name: String
    let emoji: String?
    let color: String?
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
    let subcategories: [SubcategoryResponse]
}

struct SubcategoryResponse: Codable, Identifiable {
    let id: Int
    let categoryId: Int
    let name: String
    let isSystem: Bool
    let createdAt: String
    let updatedAt: String
}

struct CategoryCreate: Codable {
    let name: String
    var emoji: String?
    var color: String?
}

struct CategoryUpdate: Codable {
    var name: String?
    var emoji: String?
    var color: String?
}

struct SubcategoryCreate: Codable {
    let name: String
}

struct SubcategoryUpdate: Codable {
    var name: String?
}
```

- [ ] **Step 5: Create LinkedEntry.swift**

```swift
import Foundation

struct LinkedEntryResponse: Codable, Identifiable {
    let id: Int
    let linkType: LinkType
    let primaryTransactionId: Int
    let counterpartyName: String
    let totalAmount: Decimal
    let userAmount: Decimal?
    let pendingAmount: Decimal
    let status: LinkStatus
    let notes: String?
    let createdAt: String
    let updatedAt: String
    let linkedTransactions: [LinkedTransactionResponse]
}

struct LinkedEntryWithDetails: Codable, Identifiable {
    let id: Int
    let linkType: LinkType
    let primaryTransactionId: Int
    let counterpartyName: String
    let totalAmount: Decimal
    let userAmount: Decimal?
    let pendingAmount: Decimal
    let status: LinkStatus
    let notes: String?
    let createdAt: String
    let updatedAt: String
    let linkedTransactions: [LinkedTransactionResponse]
    let primaryTransactionDescription: String?
    let primaryTransactionDate: String?
    let settledAmount: Decimal
}

struct LinkedTransactionResponse: Codable, Identifiable {
    let id: Int
    let linkedEntryId: Int
    let transactionId: Int
    let amount: Decimal
    let createdAt: String
    let date: String?
    let description: String?
}

struct LinkedEntryCreate: Codable {
    let primaryTransactionId: Int
    let linkType: LinkType
    let counterpartyName: String
    var userAmount: Decimal?
    var notes: String?
}

struct LinkedEntryUpdate: Codable {
    var counterpartyName: String?
    var userAmount: Decimal?
    var notes: String?
}

struct LinkTransactionRequest: Codable {
    let transactionId: Int
}

struct MarkAsSplitRequest: Codable {
    let counterpartyName: String
    let userAmount: Decimal
    var notes: String?
}

struct MarkAsLoanRequest: Codable {
    let counterpartyName: String
    var notes: String?
}

struct MarkAsDebtRequest: Codable {
    let counterpartyName: String
    var notes: String?
}

struct OwedSummary: Codable {
    let totalOwed: Decimal
    let pendingCount: Int
}

struct DebtSummary: Codable {
    let totalDebt: Decimal
    let pendingCount: Int
}
```

- [ ] **Step 6: Create Budget.swift**

```swift
import Foundation

struct BudgetResponse: Codable, Identifiable {
    let id: Int
    let categoryId: Int
    let year: Int
    let month: Int
    let amount: Decimal
    let createdAt: String
    let updatedAt: String
}

struct BudgetWithCategory: Codable, Identifiable {
    let id: Int
    let categoryId: Int
    let year: Int
    let month: Int
    let amount: Decimal
    let createdAt: String
    let updatedAt: String
    let categoryName: String?
    let categoryEmoji: String?
}

struct BudgetCreate: Codable {
    let categoryId: Int
    let year: Int
    let month: Int
    let amount: Decimal
}

struct BudgetUpdate: Codable {
    var amount: Decimal?
}

struct CategorySummary: Codable, Identifiable {
    let categoryId: Int
    let categoryName: String
    let emoji: String?
    let color: String?
    let budget: Double
    let actual: Double
    let percentage: Double
    let periods: [Double]
    let subcategories: [SubcategorySummary]

    var id: Int { categoryId }
}

struct SubcategorySummary: Codable, Identifiable {
    let subcategoryId: Int
    let subcategoryName: String
    let actual: Double
    let periods: [Double]

    var id: Int { subcategoryId }
}

struct MonthlySummaryResponse: Codable {
    let year: Int
    let month: Int
    let categories: [CategorySummary]
    let totalBudget: Decimal
    let totalActual: Decimal
    let periodBoundaries: [Int]
}

struct DailyCategoryData: Codable, Identifiable {
    let categoryId: Int
    let categoryName: String
    let emoji: String?
    let color: String?
    let budget: Double
    let dailyAmounts: [Double]
    let subcategories: [DailySubcategoryData]

    var id: Int { categoryId }
}

struct DailySubcategoryData: Codable, Identifiable {
    let subcategoryId: Int
    let subcategoryName: String
    let dailyAmounts: [Double]

    var id: Int { subcategoryId }
}

struct DailySummaryResponse: Codable {
    let year: Int
    let month: Int
    let daysInMonth: Int
    let categories: [DailyCategoryData]
}
```

- [ ] **Step 7: Create BalanceAudit.swift**

```swift
import Foundation

struct BalanceAuditResponse: Codable, Identifiable {
    let id: Int
    let date: String
    let balances: [String: Double?]
    let debts: Decimal
    let owed: Decimal
    let netPosition: Decimal
    let createdAt: String
    let updatedAt: String
}

struct BalanceAuditCreate: Codable {
    let date: String
    var balances: [String: Double?]?
    var debts: Decimal?
    var owed: Decimal?
    var netPosition: Decimal?
}
```

- [ ] **Step 8: Verify compilation**

```bash
cd SlaveOfCapitalism && xcodebuild -scheme SlaveOfCapitalism -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 9: Commit**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalism/Models/
git commit -m "feat: add all Codable data models matching backend schemas"
```

---

## Task 5: APIClient Protocol and Implementation

The HTTP client that talks to the backend. Protocol-based for testability.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift`

**Reference:**
- Spec section: "API Client" — lists all 54 methods grouped by endpoint
- Backend routers: exact paths and HTTP methods

- [ ] **Step 1: Create APIClient.swift with protocol and implementation**

Create `SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift`:

```swift
import Foundation
import Observation

// MARK: - Error Types

enum APIError: LocalizedError {
    case notFound
    case validationError(String)
    case serverError(String)
    case networkError(Error)
    case backendNotReady
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Resource not found"
        case .validationError(let msg): return msg
        case .serverError(let msg): return msg
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .backendNotReady: return "Backend is not ready"
        case .decodingError(let err): return "Failed to decode response: \(err.localizedDescription)"
        }
    }
}

// MARK: - Protocol

protocol APIClientProtocol {
    // Wallets
    func listWallets() async throws -> [WalletWithBalance]
    func getWallet(id: Int) async throws -> WalletWithBalance
    func createWallet(_ wallet: WalletCreate) async throws -> WalletResponse
    func updateWallet(id: Int, _ wallet: WalletUpdate) async throws -> WalletResponse
    func deleteWallet(id: Int) async throws
    func transfer(_ request: WalletTransferRequest) async throws -> WalletTransferResponse
    func calibrateWallet(id: Int, _ request: CalibrateWalletRequest) async throws -> TransactionResponse
    func getAudits() async throws -> [BalanceAuditResponse]
    func createAudit(_ audit: BalanceAuditCreate) async throws -> BalanceAuditResponse

    // Transactions
    func listTransactions(walletId: Int?, categoryId: Int?, month: String?, direction: String?, classification: String?) async throws -> [TransactionWithDetails]
    func getTransaction(id: Int) async throws -> TransactionWithDetails
    func createTransaction(_ tx: TransactionCreate) async throws -> TransactionResponse
    func updateTransaction(id: Int, _ tx: TransactionUpdate) async throws -> TransactionResponse
    func deleteTransaction(id: Int) async throws
    func deleteTransactions(ids: [Int]) async throws
    func ignoreTransactions(ids: [Int]) async throws
    func unignoreTransactions(ids: [Int]) async throws
    func reclassifyTransaction(id: Int, _ request: ReclassifyRequest) async throws -> TransactionResponse
    func markAsSplit(id: Int, _ request: MarkAsSplitRequest) async throws -> LinkedEntryResponse
    func markAsLoan(id: Int, _ request: MarkAsLoanRequest) async throws -> LinkedEntryResponse
    func markAsDebt(id: Int, _ request: MarkAsDebtRequest) async throws -> LinkedEntryResponse
    func markAsInstallment(id: Int, _ request: MarkAsLoanRequest) async throws -> LinkedEntryResponse
    func unclassifyTransaction(id: Int) async throws
    func unlinkTransaction(id: Int) async throws
    func linkToEntry(_ request: BulkLinkRequest) async throws -> LinkedEntryResponse
    func mergeTransactions(_ request: TransactionMergeRequest) async throws -> TransactionResponse
    func resolveCalibration(id: Int, _ request: ResolveCalibrationRequest) async throws -> ResolveCalibrationResponse
    func bulkImport(_ request: BulkImportRequest) async throws -> BulkImportResponse
    func monthlySummary(month: String) async throws -> MonthlySummaryDict

    // Categories
    func listCategories() async throws -> [CategoryWithSubcategories]
    func createCategory(_ category: CategoryCreate) async throws -> CategoryResponse
    func updateCategory(id: Int, _ category: CategoryUpdate) async throws -> CategoryResponse
    func deleteCategory(id: Int, replacementCategoryId: Int, replacementSubcategoryId: Int?) async throws
    func createSubcategory(categoryId: Int, _ sub: SubcategoryCreate) async throws -> SubcategoryResponse
    func updateSubcategory(id: Int, _ sub: SubcategoryUpdate) async throws -> SubcategoryResponse
    func deleteSubcategory(id: Int, replacementCategoryId: Int, replacementSubcategoryId: Int?) async throws

    // Linked Entries
    func listLinkedEntries(linkType: String?, status: String?) async throws -> [LinkedEntryWithDetails]
    func pendingEntries() async throws -> [LinkedEntryWithDetails]
    func getLinkedEntry(id: Int) async throws -> LinkedEntryWithDetails
    func getLinkedEntryByTransaction(transactionId: Int) async throws -> LinkedEntryWithDetails
    func createLinkedEntry(_ entry: LinkedEntryCreate) async throws -> LinkedEntryResponse
    func updateLinkedEntry(id: Int, _ entry: LinkedEntryUpdate) async throws -> LinkedEntryResponse
    func deleteLinkedEntry(id: Int) async throws
    func linkTransaction(entryId: Int, _ request: LinkTransactionRequest) async throws -> LinkedEntryResponse
    func unlinkTransactionFromEntry(entryId: Int, linkId: Int) async throws -> LinkedEntryResponse
    func summaryOwed() async throws -> OwedSummary
    func summaryDebt() async throws -> DebtSummary

    // Budgets
    func listBudgets(year: Int?, month: Int?, categoryId: Int?) async throws -> [BudgetWithCategory]
    func createBudget(_ budget: BudgetCreate) async throws -> BudgetResponse
    func updateBudget(id: Int, _ budget: BudgetUpdate) async throws -> BudgetResponse
    func deleteBudget(id: Int) async throws
    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String) async throws -> MonthlySummaryResponse
    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse
}

// MARK: - Implementation

@Observable
final class APIClient: APIClientProtocol {
    var baseURL: URL

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!) {
        self.baseURL = baseURL
        self.session = URLSession.shared

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = enc
    }

    // MARK: - Generic Helpers

    private func request<T: Decodable>(_ method: String, path: String, query: [(String, String)] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        return try await perform(req)
    }

    private func request<T: Decodable, B: Encodable>(_ method: String, path: String, body: B, query: [(String, String)] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        return try await perform(req)
    }

    private func requestVoid(_ method: String, path: String, query: [(String, String)] = []) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        let (_, response) = try await session.data(for: req)
        try checkResponse(response, data: nil)
    }

    private func requestVoid<B: Encodable>(_ method: String, path: String, body: B) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: req)
        try checkResponse(response, data: nil)
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        try checkResponse(response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func checkResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...204: return
        case 404: throw APIError.notFound
        case 400, 422:
            let msg = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["detail"] as? String } ?? "Validation error"
            throw APIError.validationError(msg)
        default:
            let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Server error"
            throw APIError.serverError(msg)
        }
    }

    // MARK: - Health

    func healthCheck() async throws -> Bool {
        let _: [String: String] = try await request("GET", path: "/api/health")
        return true
    }

    // MARK: - Wallets

    func listWallets() async throws -> [WalletWithBalance] {
        try await request("GET", path: "/api/wallets/")
    }

    func getWallet(id: Int) async throws -> WalletWithBalance {
        try await request("GET", path: "/api/wallets/\(id)")
    }

    func createWallet(_ wallet: WalletCreate) async throws -> WalletResponse {
        try await request("POST", path: "/api/wallets/", body: wallet)
    }

    func updateWallet(id: Int, _ wallet: WalletUpdate) async throws -> WalletResponse {
        try await request("PUT", path: "/api/wallets/\(id)", body: wallet)
    }

    func deleteWallet(id: Int) async throws {
        try await requestVoid("DELETE", path: "/api/wallets/\(id)")
    }

    func transfer(_ request: WalletTransferRequest) async throws -> WalletTransferResponse {
        try await self.request("POST", path: "/api/wallets/transfer", body: request)
    }

    func calibrateWallet(id: Int, _ request: CalibrateWalletRequest) async throws -> TransactionResponse {
        try await self.request("POST", path: "/api/wallets/\(id)/calibrate", body: request)
    }

    func getAudits() async throws -> [BalanceAuditResponse] {
        try await request("GET", path: "/api/wallets/audits")
    }

    func createAudit(_ audit: BalanceAuditCreate) async throws -> BalanceAuditResponse {
        try await request("POST", path: "/api/wallets/audits", body: audit)
    }

    // MARK: - Transactions

    func listTransactions(walletId: Int? = nil, categoryId: Int? = nil, month: String? = nil, direction: String? = nil, classification: String? = nil) async throws -> [TransactionWithDetails] {
        var query: [(String, String)] = []
        if let w = walletId { query.append(("wallet_id", "\(w)")) }
        if let c = categoryId { query.append(("category_id", "\(c)")) }
        if let m = month { query.append(("month", m)) }
        if let d = direction { query.append(("direction", d)) }
        if let cl = classification { query.append(("classification", cl)) }
        return try await request("GET", path: "/api/transactions/", query: query)
    }

    func getTransaction(id: Int) async throws -> TransactionWithDetails {
        try await request("GET", path: "/api/transactions/\(id)")
    }

    func createTransaction(_ tx: TransactionCreate) async throws -> TransactionResponse {
        try await request("POST", path: "/api/transactions/", body: tx)
    }

    func updateTransaction(id: Int, _ tx: TransactionUpdate) async throws -> TransactionResponse {
        try await request("PUT", path: "/api/transactions/\(id)", body: tx)
    }

    func deleteTransaction(id: Int) async throws {
        try await requestVoid("DELETE", path: "/api/transactions/\(id)")
    }

    func deleteTransactions(ids: [Int]) async throws {
        try await requestVoid("DELETE", path: "/api/transactions/", body: BulkActionRequest(transactionIds: ids))
    }

    func ignoreTransactions(ids: [Int]) async throws {
        try await requestVoid("POST", path: "/api/transactions/ignore", body: BulkActionRequest(transactionIds: ids))
    }

    func unignoreTransactions(ids: [Int]) async throws {
        try await requestVoid("POST", path: "/api/transactions/unignore", body: BulkActionRequest(transactionIds: ids))
    }

    func reclassifyTransaction(id: Int, _ request: ReclassifyRequest) async throws -> TransactionResponse {
        try await self.request("POST", path: "/api/transactions/\(id)/reclassify", body: request)
    }

    func markAsSplit(id: Int, _ request: MarkAsSplitRequest) async throws -> LinkedEntryResponse {
        try await self.request("POST", path: "/api/transactions/\(id)/mark-split", body: request)
    }

    func markAsLoan(id: Int, _ request: MarkAsLoanRequest) async throws -> LinkedEntryResponse {
        try await self.request("POST", path: "/api/transactions/\(id)/mark-loan", body: request)
    }

    func markAsDebt(id: Int, _ request: MarkAsDebtRequest) async throws -> LinkedEntryResponse {
        try await self.request("POST", path: "/api/transactions/\(id)/mark-debt", body: request)
    }

    func markAsInstallment(id: Int, _ request: MarkAsLoanRequest) async throws -> LinkedEntryResponse {
        try await self.request("POST", path: "/api/transactions/\(id)/mark-installment", body: request)
    }

    func unclassifyTransaction(id: Int) async throws {
        try await requestVoid("POST", path: "/api/transactions/\(id)/unclassify")
    }

    func unlinkTransaction(id: Int) async throws {
        try await requestVoid("POST", path: "/api/transactions/\(id)/unlink")
    }

    func linkToEntry(_ request: BulkLinkRequest) async throws -> LinkedEntryResponse {
        try await self.request("POST", path: "/api/transactions/link", body: request)
    }

    func mergeTransactions(_ request: TransactionMergeRequest) async throws -> TransactionResponse {
        try await self.request("POST", path: "/api/transactions/merge", body: request)
    }

    func resolveCalibration(id: Int, _ request: ResolveCalibrationRequest) async throws -> ResolveCalibrationResponse {
        try await self.request("POST", path: "/api/transactions/\(id)/resolve", body: request)
    }

    func bulkImport(_ request: BulkImportRequest) async throws -> BulkImportResponse {
        try await self.request("POST", path: "/api/transactions/bulk-import", body: request)
    }

    func monthlySummary(month: String) async throws -> MonthlySummaryDict {
        try await request("GET", path: "/api/transactions/monthly-summary/", query: [("month", month)])
    }

    // MARK: - Categories

    func listCategories() async throws -> [CategoryWithSubcategories] {
        try await request("GET", path: "/api/categories/")
    }

    func createCategory(_ category: CategoryCreate) async throws -> CategoryResponse {
        try await request("POST", path: "/api/categories/", body: category)
    }

    func updateCategory(id: Int, _ category: CategoryUpdate) async throws -> CategoryResponse {
        try await request("PUT", path: "/api/categories/\(id)", body: category)
    }

    func deleteCategory(id: Int, replacementCategoryId: Int, replacementSubcategoryId: Int?) async throws {
        var query: [(String, String)] = [("replacement_category_id", "\(replacementCategoryId)")]
        if let subId = replacementSubcategoryId {
            query.append(("replacement_subcategory_id", "\(subId)"))
        }
        try await requestVoid("DELETE", path: "/api/categories/\(id)", query: query)
    }

    func createSubcategory(categoryId: Int, _ sub: SubcategoryCreate) async throws -> SubcategoryResponse {
        try await request("POST", path: "/api/categories/\(categoryId)/subcategories", body: sub)
    }

    func updateSubcategory(id: Int, _ sub: SubcategoryUpdate) async throws -> SubcategoryResponse {
        try await request("PUT", path: "/api/categories/subcategories/\(id)", body: sub)
    }

    func deleteSubcategory(id: Int, replacementCategoryId: Int, replacementSubcategoryId: Int?) async throws {
        var query: [(String, String)] = [("replacement_category_id", "\(replacementCategoryId)")]
        if let subId = replacementSubcategoryId {
            query.append(("replacement_subcategory_id", "\(subId)"))
        }
        try await requestVoid("DELETE", path: "/api/categories/subcategories/\(id)", query: query)
    }

    // MARK: - Linked Entries

    func listLinkedEntries(linkType: String? = nil, status: String? = nil) async throws -> [LinkedEntryWithDetails] {
        var query: [(String, String)] = []
        if let lt = linkType { query.append(("link_type", lt)) }
        if let s = status { query.append(("status", s)) }
        return try await request("GET", path: "/api/linked-entries/", query: query)
    }

    func pendingEntries() async throws -> [LinkedEntryWithDetails] {
        try await request("GET", path: "/api/linked-entries/pending")
    }

    func getLinkedEntry(id: Int) async throws -> LinkedEntryWithDetails {
        try await request("GET", path: "/api/linked-entries/\(id)")
    }

    func getLinkedEntryByTransaction(transactionId: Int) async throws -> LinkedEntryWithDetails {
        try await request("GET", path: "/api/linked-entries/transaction/\(transactionId)")
    }

    func createLinkedEntry(_ entry: LinkedEntryCreate) async throws -> LinkedEntryResponse {
        try await request("POST", path: "/api/linked-entries/", body: entry)
    }

    func updateLinkedEntry(id: Int, _ entry: LinkedEntryUpdate) async throws -> LinkedEntryResponse {
        try await request("PUT", path: "/api/linked-entries/\(id)", body: entry)
    }

    func deleteLinkedEntry(id: Int) async throws {
        try await requestVoid("DELETE", path: "/api/linked-entries/\(id)")
    }

    func linkTransaction(entryId: Int, _ request: LinkTransactionRequest) async throws -> LinkedEntryResponse {
        try await self.request("POST", path: "/api/linked-entries/\(entryId)/link", body: request)
    }

    func unlinkTransactionFromEntry(entryId: Int, linkId: Int) async throws -> LinkedEntryResponse {
        try await request("DELETE", path: "/api/linked-entries/\(entryId)/unlink/\(linkId)")
    }

    func summaryOwed() async throws -> OwedSummary {
        try await request("GET", path: "/api/linked-entries/summary/owed")
    }

    func summaryDebt() async throws -> DebtSummary {
        try await request("GET", path: "/api/linked-entries/summary/debt")
    }

    // MARK: - Budgets

    func listBudgets(year: Int? = nil, month: Int? = nil, categoryId: Int? = nil) async throws -> [BudgetWithCategory] {
        var query: [(String, String)] = []
        if let y = year { query.append(("year", "\(y)")) }
        if let m = month { query.append(("month", "\(m)")) }
        if let c = categoryId { query.append(("category_id", "\(c)")) }
        return try await request("GET", path: "/api/budgets/", query: query)
    }

    func createBudget(_ budget: BudgetCreate) async throws -> BudgetResponse {
        try await request("POST", path: "/api/budgets/", body: budget)
    }

    func updateBudget(id: Int, _ budget: BudgetUpdate) async throws -> BudgetResponse {
        try await request("PUT", path: "/api/budgets/\(id)", body: budget)
    }

    func deleteBudget(id: Int) async throws {
        try await requestVoid("DELETE", path: "/api/budgets/\(id)")
    }

    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String = "7,14,21,31") async throws -> MonthlySummaryResponse {
        try await request("GET", path: "/api/budgets/summary/\(year)/\(month)", query: [("period_boundaries", periodBoundaries)])
    }

    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse {
        try await request("GET", path: "/api/budgets/daily-summary/\(year)/\(month)")
    }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd SlaveOfCapitalism && xcodebuild -scheme SlaveOfCapitalism -destination 'platform=macOS' build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift
git commit -m "feat: add APIClient protocol and URLSession implementation (54 methods)"
```

---

## Task 6: BackendManager — Subprocess Lifecycle

Manages launching, health polling, crash recovery, and shutdown of the backend process.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Backend/BackendManager.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/LoadingView.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/ErrorView.swift`

**Reference:**
- Spec section: "Backend Process Management"
- Current Tauri pattern: `frontend/src/lib/api/client.ts` — `waitForBackend()` function

- [ ] **Step 1: Create BackendManager.swift**

```swift
import Foundation
import Observation

@Observable
final class BackendManager {
    enum State {
        case starting
        case ready
        case error(String)
        case crashed(String)
    }

    private(set) var state: State = .starting
    private(set) var port: UInt16 = 0
    let apiClient = APIClient()

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    private var process: Process?
    private var healthTask: Task<Void, Never>?

    private var databasePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("SlaveOfCapitalism")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("expense.db").path
    }

    func start(dbPath: String? = nil) {
        state = .starting
        let resolvedPath = dbPath ?? databasePath
        port = findAvailablePort()

        guard let binaryURL = Bundle.main.url(forResource: "expense-manager-backend", withExtension: nil) else {
            state = .error("Backend binary not found in app bundle")
            return
        }

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = ["--port", "\(port)", "--db-path", resolvedPath]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            if case .ready = self.state {
                DispatchQueue.main.async {
                    self.state = .crashed("Backend process exited with code \(p.terminationStatus)")
                }
            }
        }

        do {
            try proc.run()
            process = proc
            apiClient.baseURL = URL(string: "http://127.0.0.1:\(port)")!
            pollHealth()
        } catch {
            state = .error("Failed to launch backend: \(error.localizedDescription)")
        }
    }

    func stop() {
        healthTask?.cancel()
        healthTask = nil
        process?.terminate()
        process = nil
    }

    func restart(dbPath: String? = nil) {
        stop()
        start(dbPath: dbPath)
    }

    private func pollHealth() {
        healthTask?.cancel()
        healthTask = Task { @MainActor in
            for attempt in 0..<30 {
                if Task.isCancelled { return }
                do {
                    _ = try await apiClient.healthCheck()
                    state = .ready
                    return
                } catch {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            state = .error("Backend failed to respond after 15 seconds")
        }
    }

    private func findAvailablePort() -> UInt16 {
        // Bind to port 0 to get a random available port from the OS
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(socketFD, sockPtr, &addrLen)
            }
        }

        return UInt16(bigEndian: boundAddr.sin_port)
    }

    deinit {
        stop()
    }
}
```

- [ ] **Step 2: Create LoadingView.swift**

```swift
import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Starting backend...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 3: Create ErrorView.swift**

```swift
import SwiftUI

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Backend Error")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            HStack(spacing: 12) {
                Button("Retry") { onRetry() }
                    .buttonStyle(.borderedProminent)
                if let onSettings {
                    Button("Open Settings") { onSettings() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalism/Backend/BackendManager.swift SlaveOfCapitalism/SlaveOfCapitalism/Views/LoadingView.swift SlaveOfCapitalism/SlaveOfCapitalism/Views/ErrorView.swift
git commit -m "feat: add BackendManager with subprocess lifecycle and error views"
```

---

## Task 7: Shared Stores, Utilities, and App Settings

Shared state objects injected via SwiftUI environment, plus formatters and settings.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Stores/CategoryStore.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Stores/WalletStore.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Stores/AppSettings.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Utilities/Formatters.swift`

- [ ] **Step 1: Create AppSettings.swift**

```swift
import Foundation
import Observation

@Observable
final class AppSettings {
    var currency: String {
        didSet { UserDefaults.standard.set(currency, forKey: "currency") }
    }
    var decimals: Int {
        didSet { UserDefaults.standard.set(decimals, forKey: "decimals") }
    }
    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    var databasePath: String {
        didSet { UserDefaults.standard.set(databasePath, forKey: "databasePath") }
    }

    init() {
        self.currency = UserDefaults.standard.string(forKey: "currency") ?? "¥"
        self.decimals = UserDefaults.standard.object(forKey: "decimals") as? Int ?? 0
        self.language = UserDefaults.standard.string(forKey: "language") ?? "en"
        self.databasePath = UserDefaults.standard.string(forKey: "databasePath") ?? ""
    }
}
```

- [ ] **Step 2: Create CategoryStore.swift**

```swift
import Foundation
import Observation

@Observable
final class CategoryStore {
    private(set) var categories: [CategoryWithSubcategories] = []
    private(set) var isLoading = false
    private var apiClient: APIClient?

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func refresh() async {
        guard let apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            categories = try await apiClient.listCategories()
        } catch {
            print("Failed to refresh categories: \(error)")
        }
    }

    func category(for id: Int) -> CategoryWithSubcategories? {
        categories.first { $0.id == id }
    }

    func subcategory(for id: Int) -> SubcategoryResponse? {
        categories.flatMap(\.subcategories).first { $0.id == id }
    }
}
```

- [ ] **Step 3: Create WalletStore.swift**

```swift
import Foundation
import Observation

@Observable
final class WalletStore {
    private(set) var wallets: [WalletWithBalance] = []
    private(set) var isLoading = false
    private var apiClient: APIClient?

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func refresh() async {
        guard let apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            wallets = try await apiClient.listWallets()
        } catch {
            print("Failed to refresh wallets: \(error)")
        }
    }

    func wallet(for id: Int) -> WalletWithBalance? {
        wallets.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Create Formatters.swift**

```swift
import Foundation

enum Formatters {
    static func currency(_ amount: Decimal, symbol: String = "¥", decimals: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let number = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "\(symbol)\(number)"
    }

    static func date(_ isoString: String) -> String {
        // Backend returns "YYYY-MM-DD" format
        isoString
    }

    static func percentage(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func monthYear(year: Int, month: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return "" }
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 5: Update SlaveOfCapitalismApp.swift to inject stores**

```swift
import SwiftUI

@main
struct SlaveOfCapitalismApp: App {
    @State private var backendManager = BackendManager()
    @State private var categoryStore = CategoryStore()
    @State private var walletStore = WalletStore()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(backendManager)
                .environment(backendManager.apiClient)
                .environment(categoryStore)
                .environment(walletStore)
                .environment(appSettings)
                .task {
                    backendManager.start(dbPath: appSettings.databasePath.isEmpty ? nil : appSettings.databasePath)
                }
                .onChange(of: backendManager.isReady) { _, isReady in
                    if isReady {
                        categoryStore.configure(apiClient: backendManager.apiClient)
                        walletStore.configure(apiClient: backendManager.apiClient)
                        Task {
                            await categoryStore.refresh()
                            await walletStore.refresh()
                        }
                    }
                }
        }
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalism/Stores/ SlaveOfCapitalism/SlaveOfCapitalism/Utilities/Formatters.swift SlaveOfCapitalism/SlaveOfCapitalism/SlaveOfCapitalismApp.swift
git commit -m "feat: add shared stores (categories, wallets, settings) and formatters"
```

---

## Task 8: MockAPIClient and Test Infrastructure

Protocol-based mock for unit testing ViewModels without a running backend.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalismTests/MockAPIClient.swift`

- [ ] **Step 1: Create MockAPIClient.swift**

```swift
import Foundation
@testable import SlaveOfCapitalism

final class MockAPIClient: APIClientProtocol {
    // Configurable return values
    var walletsToReturn: [WalletWithBalance] = []
    var transactionsToReturn: [TransactionWithDetails] = []
    var categoriesToReturn: [CategoryWithSubcategories] = []
    var pendingEntriesToReturn: [LinkedEntryWithDetails] = []
    var budgetsToReturn: [BudgetWithCategory] = []
    var auditsToReturn: [BalanceAuditResponse] = []
    var monthlySummaryToReturn: MonthlySummaryResponse?
    var dailySummaryToReturn: DailySummaryResponse?
    var owedSummaryToReturn = OwedSummary(totalOwed: 0, pendingCount: 0)
    var debtSummaryToReturn = DebtSummary(totalDebt: 0, pendingCount: 0)

    // Error simulation
    var errorToThrow: APIError?

    // Call tracking
    var lastCalledMethod: String?
    var callCount: [String: Int] = [:]

    private func track(_ method: String) throws {
        lastCalledMethod = method
        callCount[method, default: 0] += 1
        if let error = errorToThrow { throw error }
    }

    // Wallets
    func listWallets() async throws -> [WalletWithBalance] { try track("listWallets"); return walletsToReturn }
    func getWallet(id: Int) async throws -> WalletWithBalance { try track("getWallet"); return walletsToReturn.first! }
    func createWallet(_ w: WalletCreate) async throws -> WalletResponse { try track("createWallet"); fatalError("Mock not configured") }
    func updateWallet(id: Int, _ w: WalletUpdate) async throws -> WalletResponse { try track("updateWallet"); fatalError("Mock not configured") }
    func deleteWallet(id: Int) async throws { try track("deleteWallet") }
    func transfer(_ r: WalletTransferRequest) async throws -> WalletTransferResponse { try track("transfer"); fatalError("Mock not configured") }
    func calibrateWallet(id: Int, _ r: CalibrateWalletRequest) async throws -> TransactionResponse { try track("calibrateWallet"); fatalError("Mock not configured") }
    func getAudits() async throws -> [BalanceAuditResponse] { try track("getAudits"); return auditsToReturn }
    func createAudit(_ a: BalanceAuditCreate) async throws -> BalanceAuditResponse { try track("createAudit"); fatalError("Mock not configured") }

    // Transactions
    func listTransactions(walletId: Int?, categoryId: Int?, month: String?, direction: String?, classification: String?) async throws -> [TransactionWithDetails] { try track("listTransactions"); return transactionsToReturn }
    func getTransaction(id: Int) async throws -> TransactionWithDetails { try track("getTransaction"); return transactionsToReturn.first! }
    func createTransaction(_ tx: TransactionCreate) async throws -> TransactionResponse { try track("createTransaction"); fatalError("Mock not configured") }
    func updateTransaction(id: Int, _ tx: TransactionUpdate) async throws -> TransactionResponse { try track("updateTransaction"); fatalError("Mock not configured") }
    func deleteTransaction(id: Int) async throws { try track("deleteTransaction") }
    func deleteTransactions(ids: [Int]) async throws { try track("deleteTransactions") }
    func ignoreTransactions(ids: [Int]) async throws { try track("ignoreTransactions") }
    func unignoreTransactions(ids: [Int]) async throws { try track("unignoreTransactions") }
    func reclassifyTransaction(id: Int, _ r: ReclassifyRequest) async throws -> TransactionResponse { try track("reclassifyTransaction"); fatalError("Mock not configured") }
    func markAsSplit(id: Int, _ r: MarkAsSplitRequest) async throws -> LinkedEntryResponse { try track("markAsSplit"); fatalError("Mock not configured") }
    func markAsLoan(id: Int, _ r: MarkAsLoanRequest) async throws -> LinkedEntryResponse { try track("markAsLoan"); fatalError("Mock not configured") }
    func markAsDebt(id: Int, _ r: MarkAsDebtRequest) async throws -> LinkedEntryResponse { try track("markAsDebt"); fatalError("Mock not configured") }
    func markAsInstallment(id: Int, _ r: MarkAsLoanRequest) async throws -> LinkedEntryResponse { try track("markAsInstallment"); fatalError("Mock not configured") }
    func unclassifyTransaction(id: Int) async throws { try track("unclassifyTransaction") }
    func unlinkTransaction(id: Int) async throws { try track("unlinkTransaction") }
    func linkToEntry(_ r: BulkLinkRequest) async throws -> LinkedEntryResponse { try track("linkToEntry"); fatalError("Mock not configured") }
    func mergeTransactions(_ r: TransactionMergeRequest) async throws -> TransactionResponse { try track("mergeTransactions"); fatalError("Mock not configured") }
    func resolveCalibration(id: Int, _ r: ResolveCalibrationRequest) async throws -> ResolveCalibrationResponse { try track("resolveCalibration"); fatalError("Mock not configured") }
    func bulkImport(_ r: BulkImportRequest) async throws -> BulkImportResponse { try track("bulkImport"); return BulkImportResponse(importedCount: 0, message: "ok") }
    func monthlySummary(month: String) async throws -> MonthlySummaryDict { try track("monthlySummary"); fatalError("Mock not configured") }

    // Categories
    func listCategories() async throws -> [CategoryWithSubcategories] { try track("listCategories"); return categoriesToReturn }
    func createCategory(_ c: CategoryCreate) async throws -> CategoryResponse { try track("createCategory"); fatalError("Mock not configured") }
    func updateCategory(id: Int, _ c: CategoryUpdate) async throws -> CategoryResponse { try track("updateCategory"); fatalError("Mock not configured") }
    func deleteCategory(id: Int, replacementCategoryId: Int, replacementSubcategoryId: Int?) async throws { try track("deleteCategory") }
    func createSubcategory(categoryId: Int, _ s: SubcategoryCreate) async throws -> SubcategoryResponse { try track("createSubcategory"); fatalError("Mock not configured") }
    func updateSubcategory(id: Int, _ s: SubcategoryUpdate) async throws -> SubcategoryResponse { try track("updateSubcategory"); fatalError("Mock not configured") }
    func deleteSubcategory(id: Int, replacementCategoryId: Int, replacementSubcategoryId: Int?) async throws { try track("deleteSubcategory") }

    // Linked Entries
    func listLinkedEntries(linkType: String?, status: String?) async throws -> [LinkedEntryWithDetails] { try track("listLinkedEntries"); return pendingEntriesToReturn }
    func pendingEntries() async throws -> [LinkedEntryWithDetails] { try track("pendingEntries"); return pendingEntriesToReturn }
    func getLinkedEntry(id: Int) async throws -> LinkedEntryWithDetails { try track("getLinkedEntry"); return pendingEntriesToReturn.first! }
    func getLinkedEntryByTransaction(transactionId: Int) async throws -> LinkedEntryWithDetails { try track("getLinkedEntryByTransaction"); return pendingEntriesToReturn.first! }
    func createLinkedEntry(_ e: LinkedEntryCreate) async throws -> LinkedEntryResponse { try track("createLinkedEntry"); fatalError("Mock not configured") }
    func updateLinkedEntry(id: Int, _ e: LinkedEntryUpdate) async throws -> LinkedEntryResponse { try track("updateLinkedEntry"); fatalError("Mock not configured") }
    func deleteLinkedEntry(id: Int) async throws { try track("deleteLinkedEntry") }
    func linkTransaction(entryId: Int, _ r: LinkTransactionRequest) async throws -> LinkedEntryResponse { try track("linkTransaction"); fatalError("Mock not configured") }
    func unlinkTransactionFromEntry(entryId: Int, linkId: Int) async throws -> LinkedEntryResponse { try track("unlinkTransactionFromEntry"); fatalError("Mock not configured") }
    func summaryOwed() async throws -> OwedSummary { try track("summaryOwed"); return owedSummaryToReturn }
    func summaryDebt() async throws -> DebtSummary { try track("summaryDebt"); return debtSummaryToReturn }

    // Budgets
    func listBudgets(year: Int?, month: Int?, categoryId: Int?) async throws -> [BudgetWithCategory] { try track("listBudgets"); return budgetsToReturn }
    func createBudget(_ b: BudgetCreate) async throws -> BudgetResponse { try track("createBudget"); fatalError("Mock not configured") }
    func updateBudget(id: Int, _ b: BudgetUpdate) async throws -> BudgetResponse { try track("updateBudget"); fatalError("Mock not configured") }
    func deleteBudget(id: Int) async throws { try track("deleteBudget") }
    func budgetMonthlySummary(year: Int, month: Int, periodBoundaries: String) async throws -> MonthlySummaryResponse { try track("budgetMonthlySummary"); return monthlySummaryToReturn! }
    func budgetDailySummary(year: Int, month: Int) async throws -> DailySummaryResponse { try track("budgetDailySummary"); return dailySummaryToReturn! }
}
```

- [ ] **Step 2: Commit**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalismTests/MockAPIClient.swift
git commit -m "feat: add MockAPIClient for ViewModel unit testing"
```

---

## Task 9: Navigation Shell and Sidebar

Wire up the NavigationSplitView with all 8 screens and the sidebar.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Sidebar.swift`
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/ContentView.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Shared/Components/MonthYearPicker.swift`

- [ ] **Step 1: Create Sidebar.swift**

```swift
import SwiftUI

struct Sidebar: View {
    @Binding var selection: Screen

    var body: some View {
        List(selection: $selection) {
            Section("Main") {
                Label("Transactions", systemImage: "list.bullet.rectangle")
                    .tag(Screen.transactions)
                Label("Summary", systemImage: "chart.bar")
                    .tag(Screen.summary)
                Label("Wallets", systemImage: "wallet.pass")
                    .tag(Screen.wallets)
                Label("Pending", systemImage: "clock")
                    .tag(Screen.pending)
                Label("Categories", systemImage: "folder")
                    .tag(Screen.categories)
            }
            Section {
                Label("Data", systemImage: "square.and.arrow.down")
                    .tag(Screen.data)
                Label("Audit", systemImage: "checkmark.shield")
                    .tag(Screen.audit)
                Label("Settings", systemImage: "gear")
                    .tag(Screen.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Slave of Capitalism")
    }
}
```

- [ ] **Step 2: Update ContentView.swift with screen routing**

```swift
import SwiftUI

enum Screen: String, Hashable, CaseIterable {
    case transactions, summary, wallets, pending
    case categories, data, audit, settings
}

struct ContentView: View {
    @Environment(BackendManager.self) private var backendManager
    @State private var selectedScreen: Screen = .transactions

    var body: some View {
        Group {
            switch backendManager.state {
            case .starting:
                LoadingView()
            case .error(let msg), .crashed(let msg):
                ErrorView(message: msg, onRetry: { backendManager.restart() }, onSettings: { selectedScreen = .settings })
            case .ready:
                NavigationSplitView {
                    Sidebar(selection: $selectedScreen)
                } detail: {
                    detailView
                }
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedScreen {
        case .transactions: Text("Transactions — Task 11")
        case .summary: Text("Summary — Task 14")
        case .wallets: Text("Wallets — Task 10")
        case .pending: Text("Pending — Task 13")
        case .categories: Text("Categories — Task 12")
        case .data: Text("Data — Task 17")
        case .audit: Text("Audit — Task 15")
        case .settings: Text("Settings — Task 16")
        }
    }
}
```

- [ ] **Step 3: Create MonthYearPicker.swift**

This shared component is used by Transactions, Summary, and Budgets screens.

```swift
import SwiftUI

struct MonthYearPicker: View {
    @Binding var year: Int
    @Binding var month: Int

    var body: some View {
        HStack(spacing: 8) {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Text(Formatters.monthYear(year: year, month: month))
                .font(.headline)
                .frame(minWidth: 140)

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
        }
    }

    private func previousMonth() {
        if month == 1 {
            month = 12; year -= 1
        } else {
            month -= 1
        }
    }

    private func nextMonth() {
        if month == 12 {
            month = 1; year += 1
        } else {
            month += 1
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalism/Views/Sidebar.swift SlaveOfCapitalism/SlaveOfCapitalism/ContentView.swift SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Components/MonthYearPicker.swift
git commit -m "feat: add navigation shell with sidebar and MonthYearPicker"
```

---

## Task 10: Wallets Screen

The simplest full screen — good first target to validate the full data flow.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/WalletViewModel.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Wallets/WalletListView.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Wallets/WalletCard.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Wallets/WalletFormSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/TransferSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/CalibrateSheet.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/WalletViewModelTests.swift`

**Reference:**
- Spec: "Wallets" screen section
- Frontend: `frontend/src/routes/(app)/wallets/+page.svelte`

- [ ] **Step 1: Write WalletViewModel tests**

Create test file that verifies: loads wallets on appear, handles empty state, handles errors, tracks summary calculations (available credit, net position).

- [ ] **Step 2: Create WalletViewModel.swift**

```swift
import Foundation
import Observation

@Observable
final class WalletViewModel {
    private let apiClient: any APIClientProtocol
    private(set) var wallets: [WalletWithBalance] = []
    private(set) var isLoading = false
    var error: APIError?

    // Summary calculations
    var totalAssets: Decimal { wallets.filter { $0.walletType == .normal }.reduce(0) { $0 + $1.currentBalance } }
    var totalCreditUsed: Decimal { wallets.filter { $0.walletType == .credit }.reduce(0) { $0 + $1.currentBalance } }
    var totalAvailableCredit: Decimal {
        wallets.filter { $0.walletType == .normal }.reduce(0) { $0 + $1.currentBalance }
        + wallets.filter { $0.walletType == .credit }.reduce(0) { $0 + ($1.availableCredit ?? 0) }
    }

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            wallets = try await apiClient.listWallets()
            error = nil
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .networkError(error)
        }
    }

    func deleteWallet(id: Int) async {
        do {
            try await apiClient.deleteWallet(id: id)
            await load()
        } catch let err as APIError {
            error = err
        } catch {
            self.error = .networkError(error)
        }
    }
}
```

- [ ] **Step 3: Create WalletListView.swift, WalletCard.swift, WalletFormSheet.swift**

WalletListView: Summary cards at top (Available Credit, Credit Used, Net Position) + LazyVGrid of WalletCards. Context menu on each card for Edit/Delete/Calibrate/Transfer. "Add Wallet" button in toolbar.

WalletCard: Emoji, name, type badge, balance. For credit wallets: shows remaining balance and limit.

WalletFormSheet: Form with name, type picker, emoji text field, credit limit (if credit), initial balance (if creating).

- [ ] **Step 4: Create TransferSheet.swift and CalibrateSheet.swift**

TransferSheet: From wallet picker, To wallet picker, amount, description, date. Calls `apiClient.transfer()`.

CalibrateSheet: Shows current balance, correct balance input, category picker for calibration transaction. Calls `apiClient.calibrateWallet()`.

- [ ] **Step 5: Wire WalletListView into ContentView**

Replace the placeholder `case .wallets:` with `WalletListView()`.

- [ ] **Step 6: Run tests**

```bash
cd SlaveOfCapitalism && xcodebuild test -scheme SlaveOfCapitalism -destination 'platform=macOS' 2>&1 | tail -20
```

- [ ] **Step 7: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add Wallets screen with wallet cards, transfer, and calibrate"
```

---

## Task 11: Transactions Screen — The Main Ledger

The most complex screen. macOS Table with multi-select, context menu, quick-add row, month navigation.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/TransactionViewModel.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/TransactionListView.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/TransactionRow.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/TransactionInputRow.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/AddTransactionSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/TransactionDetailSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Components/CurrencyField.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/TransactionViewModelTests.swift`

**Reference:**
- Spec: "Transactions (main screen)" section — all interactions listed
- Frontend: `frontend/src/routes/(app)/+page.svelte`, `TransactionTable.svelte`, `TransactionRow.svelte`

- [ ] **Step 1: Write TransactionViewModel tests**

Test: loads transactions for month, handles month changes, manages selection set, error handling.

- [ ] **Step 2: Create TransactionViewModel.swift**

Key state: `transactions: [TransactionWithDetails]`, `selectedMonth/Year`, `selectedIds: Set<Int>`, `isLoading`, `error`. Methods: `load()`, `deleteSelected()`, `ignoreSelected()`, `unignoreSelected()`.

- [ ] **Step 3: Create CurrencyField.swift**

A decimal input field that supports `Cmd+K` to append "000". Uses `onKeyPress` modifier (macOS 14+).

- [ ] **Step 4: Create TransactionListView.swift**

Layout: MonthYearPicker in toolbar + "Add Transaction" button. macOS `Table` with columns: Date, Description, Wallet, Category, Amount (colored by direction). Multi-row selection. Context menu per row (see spec). Bulk action toolbar when multiple selected.

- [ ] **Step 5: Create TransactionInputRow.swift and wire quick-add row**

Add explicit quick-add row at the bottom of the ledger (as required by spec):
- Inputs: date (default current date), wallet, direction, amount (`CurrencyField`), classification, category/subcategory, description.
- Keyboard behavior: Enter submits, Escape clears.
- `Cmd+K` support for amount field via `CurrencyField`.
- On submit: call `apiClient.createTransaction()`, then reload list and keep focus in quick-add row.

- [ ] **Step 6: Create AddTransactionSheet.swift**

Form: Date picker, time picker (optional), wallet picker, direction picker, amount (CurrencyField), classification picker, category/subcategory pickers, description text field. Calls `apiClient.createTransaction()`.

- [ ] **Step 7: Create TransactionDetailSheet.swift**

View/edit mode. Shows all transaction fields. Edit enables modifications. Shows linked entry info if present.

- [ ] **Step 8: Wire into ContentView**

Replace `case .transactions:` placeholder.

- [ ] **Step 9: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add Transactions screen with table, context menu, add/detail sheets"
```

---

## Task 12: Transaction Action Sheets (Mark, Reclassify, Merge, etc.)

All the sheets triggered by the transaction context menu.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/MarkAsSplitSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/MarkAsLoanSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/MarkAsDebtSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/MarkAsInstallmentSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/ReclassifySheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/LinkToEntrySheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/ResolveCalibrationSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/MergeTransactionsSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Sheets/ReimbursementsSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/Components/ConfirmationDialog.swift`

**Reference:**
- Spec: Context menu conditional logic in Transactions section
- Frontend: `frontend/src/lib/components/modals/` — all modal components

- [x] **Step 1: Create MarkAsSplitSheet.swift**

Form: Counterparty name, user amount (CurrencyField), notes. Shows total amount from transaction. Calls `apiClient.markAsSplit()`.

- [x] **Step 2: Create MarkAsLoanSheet.swift, MarkAsDebtSheet.swift, MarkAsInstallmentSheet.swift**

Similar pattern: counterparty name, optional notes. Each calls its respective API method.

- [x] **Step 3: Create ReclassifySheet.swift**

Picker for new classification. Calls `apiClient.reclassifyTransaction()`.

- [x] **Step 4: Create LinkToEntrySheet.swift**

Lists pending entries, user picks one. Calls `apiClient.linkToEntry()` with selected entry ID.

- [x] **Step 5: Create ResolveCalibrationSheet.swift**

Form for the "real" transaction that explains the calibration discrepancy. Calls `apiClient.resolveCalibration()`.

- [x] **Step 6: Create MergeTransactionsSheet.swift**

Shows selected transactions. Form for merged date, description, category. Calls `apiClient.mergeTransactions()`.

- [x] **Step 7: Create ReimbursementsSheet.swift**

Displays the linked entry and all its linked transactions. Read-only view.

- [x] **Step 8: Create ConfirmationDialog.swift**

Reusable confirmation with title, message, destructive action button.

- [x] **Step 9: Commit**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalism/Views/Shared/
git commit -m "feat: add all transaction action sheets and confirmation dialog"
```

---

## Task 13: Pending Entries Screen

Three collapsible sections: People Owe Me, I Owe, Installments.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/PendingViewModel.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Pending/PendingEntriesView.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/PendingViewModelTests.swift`

**Reference:**
- Spec: "Pending" screen section
- Frontend: `frontend/src/routes/(app)/pending/+page.svelte`

- [x] **Step 1: Write PendingViewModel tests**

Test: loads pending entries, groups by type, calculates totals, handles link transaction action.

- [x] **Step 2: Create PendingViewModel.swift**

State: `entries: [LinkedEntryWithDetails]`, computed `owedEntries`, `debtEntries`, `installmentEntries` (filtered by link type), `totalOwed`, `totalDebt`. Fetches from `apiClient.pendingEntries()`.

- [x] **Step 3: Create PendingEntriesView.swift**

Three `DisclosureGroup` sections. Each entry row shows: counterparty, emoji badge, amounts, status badge, expandable linked transactions list. "Link Transaction" button per entry.

- [x] **Step 4: Wire into ContentView**

- [ ] **Step 5: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add Pending entries screen with grouped sections"
```

---

## Task 14: Summary Screen with Budget Chart

Budget overview table + daily usage area chart.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/SummaryViewModel.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/BudgetViewModel.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Summary/SummaryView.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Summary/DailyUsageChart.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/SummaryViewModelTests.swift`

**Reference:**
- Spec: "Summary" screen section
- Frontend: `frontend/src/routes/(app)/summary/+page.svelte`, `DailyUsageChart.svelte`
- Requires: Task 1 (budget monthly summary endpoint)

- [x] **Step 1: Write SummaryViewModel tests**

Test: loads monthly summary, loads daily summary, handles month changes, calculates color thresholds.

- [x] **Step 2: Create SummaryViewModel.swift**

State: `monthlySummary: MonthlySummaryResponse?`, `dailySummary: DailySummaryResponse?`, `year`, `month`. Loads both on month change.

- [x] **Step 3: Create BudgetViewModel.swift**

CRUD operations for budgets: `budgets: [BudgetWithCategory]`, `create()`, `update()`, `delete()`.

- [x] **Step 4: Create SummaryView.swift**

MonthYearPicker at top. Budget table with expandable category rows: emoji, name, budget amount, actual amount, progress bar (colored: green <90%, yellow 90-110%, red >110%), percentage. Period columns if period boundaries configured. "Create Budget" button for categories without budgets. Inline budget editing (click amount to edit).

Below the table: DailyUsageChart.

- [x] **Step 5: Create DailyUsageChart.swift**

Swift Charts `AreaMark` chart. X-axis: day of month. Y-axis: cumulative spending. Stacked by category with category colors. Budget line as `RuleMark`. Only shows up to today if current month.

- [x] **Step 6: Wire into ContentView**

- [ ] **Step 7: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add Summary screen with budget table and daily usage chart"
```

---

## Task 15: Audit Screen

Balance snapshots with "Take Snapshot" action.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/AuditViewModel.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Audit/AuditView.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/AuditViewModelTests.swift`

- [x] **Step 1: Write AuditViewModel tests**

- [x] **Step 2: Create AuditViewModel.swift**

State: `audits: [BalanceAuditResponse]`. Methods: `load()`, `takeSnapshot()` (calls `apiClient.createAudit()`).

- [x] **Step 3: Create AuditView.swift**

"Take Snapshot" button in toolbar. List of audit records: date, wallet balances (JSON display), debts, owed, net position.

- [x] **Step 4: Wire into ContentView**

- [ ] **Step 5: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add Audit screen with snapshot list"
```

---

## Frontend Stabilization Gate (Blocking Before Task 16+)

The current priority is frontend correctness. Before implementing more feature screens (Tasks 16-22), complete this stabilization gate.

**Why this gate exists:**
- Runtime decoding errors are currently surfacing in the UI (`Decoding error: The data couldn't be read because it isn't in the correct format`).
- Backend responses frequently encode numeric values (including decimals) as JSON strings (example: `"5000.00"`), while Swift models expect `Decimal`.
- Without a compatibility layer + contract tests, additional UI work will keep regressing.

**Execution rule:**
- Do **not** start Task 16+ until Tasks 15A-15D are complete and verified.

### Task 15A: Lock Current API Contract with Failing Decode Tests

Capture real backend payload shapes and add red tests that prove current decoding is insufficient.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API/wallets-list.json`
- Create: `SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API/transactions-list.json`
- Create: `SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API/budgets-summary.json`
- Create: `SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API/budgets-daily-summary.json`
- Create: `SlaveOfCapitalism/SlaveOfCapitalismTests/APIContractDecodingTests.swift`

**Reference:**
- Backend schemas: `backend/app/schemas/*.py`
- API models: `SlaveOfCapitalism/SlaveOfCapitalism/Models/*.swift`
- API client decoder setup: `SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift`

- [x] **Step 1: Capture fixture payloads from local backend**

Run:
```bash
cd backend
python -m app.main --port 8765 --database /tmp/soc-fixture.db
```

In a second terminal:
```bash
curl -sS http://127.0.0.1:8765/api/wallets/ > ../SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API/wallets-list.json
curl -sS 'http://127.0.0.1:8765/api/transactions/?month=2026-03-01' > ../SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API/transactions-list.json
curl -sS http://127.0.0.1:8765/api/budgets/summary/2026/3 > ../SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API/budgets-summary.json
curl -sS http://127.0.0.1:8765/api/budgets/daily-summary/2026/3 > ../SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API/budgets-daily-summary.json
```

- [x] **Step 2: Write failing decode tests using current decoder behavior**

Create `SlaveOfCapitalism/SlaveOfCapitalismTests/APIContractDecodingTests.swift`:
```swift
import XCTest
@testable import SlaveOfCapitalism

final class APIContractDecodingTests: XCTestCase {
    func testWalletsFixtureDecodesToWalletWithBalanceArray() throws {
        let data = try fixture("wallets-list")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertNoThrow(try decoder.decode([WalletWithBalance].self, from: data))
    }
}
```

- [x] **Step 3: Run tests to verify RED state**

Run:
```bash
cd SlaveOfCapitalism
xcodegen generate
xcodebuild -project SlaveOfCapitalism.xcodeproj -scheme SlaveOfCapitalism -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SlaveOfCapitalismTests/APIContractDecodingTests test
```

Expected: FAIL with `DecodingError.typeMismatch`/`dataCorrupted` on `Decimal` fields represented as JSON strings.

- [x] **Step 4: Commit red fixtures + tests**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalismTests/Fixtures/API SlaveOfCapitalism/SlaveOfCapitalismTests/APIContractDecodingTests.swift
git commit -m "test: add API contract fixtures and failing decode tests"
```

### Task 15B: Implement Lossless Number-String Decoding in API Pipeline

Add a single decoding compatibility layer so existing `Decimal` model fields decode from either JSON numbers or numeric strings.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Utilities/APIModelDecoder.swift`
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/APIContractDecodingTests.swift`

- [x] **Step 1: Add shared decoder utility with normalization fallback**

Create `SlaveOfCapitalism/SlaveOfCapitalism/Utilities/APIModelDecoder.swift`:
```swift
import Foundation

enum APIModelDecoder {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data, endpoint: String) throws -> T {
        do {
            return try configured().decode(T.self, from: data)
        } catch {
            let normalizedData = try normalizeNumberStrings(in: data)
            return try configured().decode(T.self, from: normalizedData)
        }
    }
}
```

Implementation details:
- `configured()` uses `.convertFromSnakeCase`.
- `normalizeNumberStrings(in:)` recursively converts string tokens matching `^-?\\d+(\\.\\d+)?$` into `NSDecimalNumber`.
- Keep non-numeric strings unchanged (`date`, `description`, etc.).

- [x] **Step 2: Route APIClient decoding through APIModelDecoder**

Modify `SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift` in `perform<T>`:
```swift
return try APIModelDecoder.decode(T.self, from: data, endpoint: req.url?.path ?? "unknown")
```

- [x] **Step 3: Run contract tests to verify GREEN state**

Run:
```bash
cd SlaveOfCapitalism
xcodebuild -project SlaveOfCapitalism.xcodeproj -scheme SlaveOfCapitalism -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:SlaveOfCapitalismTests/APIContractDecodingTests test
```

Expected: PASS for fixture decode tests.

- [x] **Step 4: Commit decoding compatibility layer**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalism/Utilities/APIModelDecoder.swift SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift SlaveOfCapitalism/SlaveOfCapitalismTests/APIContractDecodingTests.swift
git commit -m "fix: decode decimal fields from numeric JSON strings"
```

### Task 15C: Improve Decode Error Diagnostics in UI/Logs

When decoding fails, surface enough context to identify the endpoint and payload shape quickly.

**Files:**
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/APIContractDecodingTests.swift`

- [x] **Step 1: Extend decoding error payload in APIError**

Update `APIError.decodingError` to include endpoint + payload preview:
```swift
case decodingError(endpoint: String, preview: String, underlying: Error)
```

- [x] **Step 2: Add payload preview in decode failure path**

In `perform<T>`:
- Build preview from response bytes (first 500 chars, UTF-8 fallback).
- Throw `APIError.decodingError(endpoint: path, preview: preview, underlying: error)`.

- [x] **Step 3: Add/extend tests for diagnostic content**

Add assertions that decode failures include endpoint path and preview in `localizedDescription`.

- [x] **Step 4: Commit diagnostic improvement**

```bash
git add SlaveOfCapitalism/SlaveOfCapitalism/Backend/APIClient.swift SlaveOfCapitalism/SlaveOfCapitalismTests/APIContractDecodingTests.swift
git commit -m "fix: include endpoint and payload preview in decode errors"
```

### Task 15D: Add Frontend Correctness Verification Gate

Define a repeatable verification command set that must pass before resuming feature development.

**Files:**
- Modify: `Makefile`
- Modify: `docs/superpowers/plans/2026-03-22-swiftui-port.md`

- [ ] **Step 1: Add `make swiftui-verify` target**

Target should run, in order:
```bash
cd SlaveOfCapitalism && xcodegen generate
cd SlaveOfCapitalism && xcodebuild -project SlaveOfCapitalism.xcodeproj -scheme SlaveOfCapitalism -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
cd SlaveOfCapitalism && xcodebuild -project SlaveOfCapitalism.xcodeproj -scheme SlaveOfCapitalism -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

- [ ] **Step 2: Run verification gate**

Run:
```bash
make swiftui-verify
```

Expected: all tests pass + build succeeds.

- [ ] **Step 3: Commit verification gate tooling**

```bash
git add Makefile docs/superpowers/plans/2026-03-22-swiftui-port.md
git commit -m "chore: add swiftui frontend verification gate"
```

### Frontend Stabilization Exit Criteria

- [ ] `APIContractDecodingTests` pass against captured backend fixtures.
- [ ] Full SwiftUI test suite passes (`xcodebuild ... test`).
- [ ] SwiftUI build passes (`xcodebuild ... build`).
- [ ] Runtime UI no longer shows generic decoding-format errors for supported endpoints.
- [ ] Only after all criteria pass: resume Task 16.

---

## Task 16: Settings Screen

UserDefaults-backed preferences with backend restart on DB path change.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/SettingsViewModel.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Settings/SettingsView.swift`
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/Stores/AppSettings.swift`
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/Backend/BackendManager.swift`
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/SlaveOfCapitalismApp.swift`
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/ContentView.swift`

- [ ] **Step 1: Create SettingsViewModel.swift**

Wraps AppSettings and backend runtime configuration.
State/methods must include:
- `saveDatabasePath()` (triggers BackendManager restart)
- `setBackendPortMode(.auto | .custom)`
- `setCustomBackendPort(_:)` (valid range 1024...65535)
- `applyBackendRuntimeChanges()` (restarts backend when DB path or port settings change)
- `resetToDefaults()`

- [ ] **Step 2: Extend AppSettings + BackendManager for port mode**

`AppSettings.swift`:
- Add persisted settings:
  - `backendPortMode: String` (`"auto"` or `"custom"`)
  - `customBackendPort: Int` (ignored in auto mode)

`BackendManager.swift`:
- Update start/restart APIs to accept a preferred port:
  - `start(dbPath: String?, preferredPort: UInt16?)`
  - `restart(dbPath: String?, preferredPort: UInt16?)`
- If `preferredPort` is nil => current random-port behavior.
- If provided => bind and launch backend on that exact port.
- Keep exposing the actual bound `port`.

- [ ] **Step 3: Create SettingsView.swift**

macOS `Form` with sections:
- Currency: Text field + preset buttons (¥, $, €, £, ₫)
- Decimal places: Stepper (0-4)
- Language: Picker (English/Vietnamese)
- Database: Text field + folder picker button (NSOpenPanel). Shows "Restart required" notice when path changes.
- Backend:
  - Port mode segmented picker: `Auto` / `Custom`
  - If `Custom`: numeric port text field + validation message
  - Show current runtime port from BackendManager
  - Show "Restart required" when mode/port differs from active backend
  - Apply button triggers `applyBackendRuntimeChanges()`

- [ ] **Step 4: Wire into app startup + ContentView restart flow**

`SlaveOfCapitalismApp.swift`:
- Pass settings-derived preferred port on initial backend start.

`ContentView.swift`:
- When retry/restart is triggered, pass both DB path and preferred port.

- [ ] **Step 5: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add Settings screen with preferences form"
```

---

## Task 17: Categories Screen

Category and subcategory management with color picker.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/CategoryViewModel.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Categories/CategoryManagementView.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/CategoryViewModelTests.swift`

- [ ] **Step 1: Write CategoryViewModel tests**

- [ ] **Step 2: Create CategoryViewModel.swift**

State: `categories: [CategoryWithSubcategories]`, `selectedCategoryId: Int?`. Methods: CRUD for categories and subcategories.

- [ ] **Step 3: Create CategoryManagementView.swift**

Three-pane layout:
- Left: Category list with emoji + name. "Add Category" button.
- Middle: Edit selected category — name field, emoji field, color picker (10 Apple system colors). System categories shown as read-only.
- Right: Subcategories list for selected category. Inline add/edit/delete. Swipe-to-delete with replacement picker.

- [ ] **Step 4: Wire into ContentView and refresh CategoryStore on mutations**

- [ ] **Step 5: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add Categories screen with subcategory management"
```

---

## Task 18: Data Management and PayPay Import Wizard

Import wizard with CSV parsing, wallet mapping, preview, and bulk import.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/DataManagementView.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/PayPayImport/PayPayWizardSheet.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/PayPayImport/PayPayFileStep.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/PayPayImport/PayPayMappingStep.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/PayPayImport/PayPayPreviewStep.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/PayPayImport/PayPayConfirmStep.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/PayPayImport/PayPayParser.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/PayPayImport/PayPayRuleEngine.swift`
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Data/PayPayImport/PayPayTransformer.swift`
- Test: `SlaveOfCapitalism/SlaveOfCapitalismTests/PayPayParserTests.swift`

**Reference:**
- Frontend: `frontend/src/lib/paypay-importer/` — parser.ts, rule-compiler.ts, rule-executor.ts, transformer.ts, translator.ts, wallet-mapper.ts (~500 lines total)

- [ ] **Step 1: Write PayPayParser tests**

Test CSV parsing with sample PayPay data. Verify column extraction, date parsing, amount parsing.

- [ ] **Step 2: Port PayPay parsing logic to Swift**

PayPayParser.swift: Parse CSV rows into structured `PayPayTransaction` structs.
PayPayRuleEngine.swift: Compile JSON rules into matchers, execute against transactions for auto-categorization.
PayPayTransformer.swift: Map PayPay payment methods to app wallets, transform rows into `TransactionCreate` or `WalletTransferRequest`.

- [ ] **Step 3: Create the 4-step wizard views**

PayPayWizardSheet: Tab-based container with step navigation (Back/Next/Import).
Step 1 (File): `fileImporter()` for CSV + optional rules JSON. Validates CSV format.
Step 2 (Mapping): Maps PayPay payment methods to app wallets. Persists in UserDefaults.
Step 3 (Preview): Table of parsed transactions with rule-applied categories.
Step 4 (Confirm): Summary + Import button. Calls `apiClient.bulkImport()`. Shows result.

- [ ] **Step 4: Create DataManagementView.swift**

List of import options. "Import from PayPay CSV" card opens wizard sheet.

- [ ] **Step 5: Wire into ContentView**

- [ ] **Step 6: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add Data Management screen with PayPay import wizard"
```

---

## Task 19: Error States, Empty States, and Keyboard Shortcuts

Polish pass for user experience.

**Files:**
- Modify: All screen views to add empty states
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/ContentView.swift` — add keyboard shortcuts
- Modify: All ViewModels — ensure error handling surfaces alerts

**Reference:**
- Spec: "Error & Empty States" and "Keyboard Shortcuts" sections

- [ ] **Step 1: Add empty states to all screens**

Each screen needs a centered placeholder when data is empty:
- Transactions: "No transactions in [Month Year]" + "Add Transaction" button
- Wallets: "No wallets yet" + "Create Wallet" button
- Budgets: "No budgets set for this month" + "Create Budget" button
- Pending: "All settled" per section
- Categories: (unlikely to be empty due to system categories)
- Audit: "No snapshots taken"

- [ ] **Step 2: Add keyboard shortcuts**

In ContentView or TransactionListView:
```swift
.keyboardShortcut("n", modifiers: .command)     // New transaction
.keyboardShortcut(.delete, modifiers: .command)  // Delete selected
```

CurrencyField already handles Cmd+K from Task 11.

- [ ] **Step 3: Add error alert handling**

Each screen view adds:
```swift
.alert("Error", isPresented: showingError) {
    Button("OK") { }
} message: {
    Text(viewModel.error?.localizedDescription ?? "")
}
```

- [ ] **Step 4: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add empty states, keyboard shortcuts, and error alerts"
```

---

## Task 20: Localization (English + Vietnamese)

~695 strings from the Tauri frontend's `translations.ts`.

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Utilities/Localizable.xcstrings`
- Modify: All view files — wrap user-visible strings in `String(localized:)`

**Reference:**
- Frontend: `frontend/src/lib/i18n/translations.ts` — contains all EN/VI string pairs

- [ ] **Step 1: Create string catalog**

Create `Localizable.xcstrings` via Xcode (Edit > Export Localizations, or create .xcstrings file directly). Add English as source and Vietnamese as target.

- [ ] **Step 2: Extract strings from translations.ts**

Port all ~695 string pairs from the TypeScript translations file to the xcstrings catalog.

- [ ] **Step 3: Update views to use localized strings**

Replace hardcoded strings like `"Transactions"` with `String(localized: "transactions.title")` or use SwiftUI's automatic `LocalizedStringKey`.

- [ ] **Step 4: Commit**

```bash
git add SlaveOfCapitalism/
git commit -m "feat: add English and Vietnamese localization"
```

---

## Task 21: Build Configuration and Deployment

Set up the build pipeline for bundling the backend binary and signing.

**Files:**
- Modify: Xcode project build settings
- Create: `Makefile` or build script at project root

**Reference:**
- Spec: "Deployment & Build" section

- [ ] **Step 1: Add "Copy Bundle Resources" build phase**

In Xcode, add a "Copy Files" build phase to copy `expense-manager-backend` into the Resources directory. Configure it to copy the binary from `backend/dist/` after running PyInstaller.

- [ ] **Step 2: Create build script**

```bash
#!/bin/bash
# build.sh - Build the complete app
set -e

echo "Building backend binary..."
cd backend && pyinstaller backend_binary.spec --noconfirm
cd ..

echo "Copying backend to Xcode resources..."
cp backend/dist/expense-manager-backend SlaveOfCapitalism/SlaveOfCapitalism/Resources/

echo "Signing backend binary..."
codesign --force --sign "Developer ID Application: YOUR_TEAM_ID" \
    SlaveOfCapitalism/SlaveOfCapitalism/Resources/expense-manager-backend

echo "Building SwiftUI app..."
cd SlaveOfCapitalism && xcodebuild -scheme SlaveOfCapitalism -configuration Release -derivedDataPath build/

echo "Done!"
```

- [ ] **Step 3: Add entitlements for PyInstaller compatibility**

Verify the `.entitlements` file (created in Task 3) includes:
- `com.apple.security.cs.disable-library-validation` = YES
- `com.apple.security.network.client` = YES

- [ ] **Step 4: Test the full build**

```bash
./build.sh
```

- [ ] **Step 5: Commit**

```bash
git add build.sh SlaveOfCapitalism/
git commit -m "chore: add build script for backend binary + SwiftUI app"
```

---

## Task 22: Integration Testing and Final Verification

End-to-end testing against the real backend.

- [ ] **Step 1: Run all unit tests**

```bash
cd SlaveOfCapitalism && xcodebuild test -scheme SlaveOfCapitalism -destination 'platform=macOS' 2>&1 | grep -E "(Test Suite|Tests|PASS|FAIL)"
```

- [ ] **Step 2: Run backend tests**

```bash
cd backend && python -m pytest -x -q
```

- [ ] **Step 3: Manual integration test**

Launch the app with a fresh database. Walk through each screen:
1. Create a wallet
2. Add transactions (expense, income)
3. Transfer between wallets
4. Mark a transaction as split payment
5. Link a reimbursement
6. Set up budgets, check summary
7. Check pending entries
8. Take an audit snapshot
9. Import PayPay CSV (if test data available)
10. Verify categories and settings

- [ ] **Step 4: Fix any issues discovered**

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete SwiftUI native frontend port"
```
