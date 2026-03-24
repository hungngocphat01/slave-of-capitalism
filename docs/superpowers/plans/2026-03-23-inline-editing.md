# Task 18A: Inline Editing in Transactions Table — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the click-to-open-detail editing flow with direct inline editing in the Transactions table — click a cell to edit it in place, commit on Enter/focus-out, cancel on Escape.

**Architecture:** Each table cell conditionally renders a read-only `Text` or an editable control (`TextField`/`Picker`) based on an `editingCell` state. A single `@FocusState` per `EditableTextCell` manages focus. On commit, a partial `TransactionUpdate` is sent via the API (backend uses `model_dump(exclude_unset=True)` so omitted fields are "no change"). Direction remains read-only.

**Tech Stack:** SwiftUI Table (macOS 14+), @FocusState, @Observable, TransactionUpdate API

**Parent plan:** `docs/superpowers/plans/2026-03-22-swiftui-port.md` (Task 18A)

---

## Design Decisions

### Cell-Level Editing
Each cell is independently editable. Clicking a cell activates edit mode for that specific cell only (not the whole row). This gives spreadsheet-like precision.

### Editable Fields
| Column | Control | Notes |
|--------|---------|-------|
| Date | `TextField` (ISO format `yyyy-MM-dd`) | Validated with DateFormatter before commit |
| Description | `TextField` | Free text |
| Wallet | `Picker` (menu style) with OK/Cancel buttons | Populated from `walletStore.wallets` |
| Category | `Picker` (menu style) with OK/Cancel buttons | Two-level: category → subcategory, from `categoryStore.categories` |
| Amount | `TextField` (numeric) | Decimal string, validated before commit |
| Direction | **Read-only** | No editing per user requirement |

### Commit Behavior
- **Enter**: Commits the edit, exits edit mode
- **Escape**: Cancels the edit, restores original value
- **Click outside** (focus loss): Commits the edit (for TextField-based cells)
- For picker-based cells (Wallet, Category): explicit OK/Cancel buttons since pickers don't have a natural focus-loss commit

### Focus-Commit Deduplication
`EditableTextCell` uses focus loss as the single commit path. `onSubmit` (Enter) simply sets `isFocused = false`, which triggers the `onChange(of: isFocused)` handler to commit. This prevents double-commit when Enter also causes focus loss.

### Known Limitation: Clearing Categories
The backend uses `model_dump(exclude_unset=True)` for partial updates. Swift's `JSONEncoder` omits `nil` optionals from JSON, so sending `TransactionUpdate(categoryId: nil)` is equivalent to not sending `category_id` at all — the backend treats it as "no change." This means selecting "Uncategorized" in the inline picker is a no-op. This is a pre-existing limitation (also affects TransactionDetailSheet). Clearing a category requires the detail sheet flow or a future dedicated endpoint.

### Error Handling
If the API call fails, show the error in the existing error banner and revert the cell to its original value (by reloading).

### State Model
```swift
enum EditableField: Hashable {
    case date, description, wallet, category, amount
}

// Tracked in TransactionListView
@State private var editingTransactionId: Int?
@State private var editingField: EditableField?
@State private var editText: String = ""          // buffer for date/description/amount
@State private var editWalletId: Int = 0          // buffer for wallet picker
@State private var editCategoryId: Int = 0        // buffer for category picker
@State private var editSubcategoryId: Int = 0     // buffer for subcategory picker
```

## File Structure

```
SlaveOfCapitalism/SlaveOfCapitalism/
├── Views/Transactions/
│   ├── TransactionListView.swift          # MODIFY — replace interactiveCell with editable cells
│   ├── EditableTextCell.swift             # CREATE — reusable inline text editor component
│   └── EditableCategoryPicker.swift       # CREATE — inline two-level category picker
├── ViewModels/
│   └── TransactionViewModel.swift         # MODIFY — add updateTransaction() method
└── SlaveOfCapitalismTests/
    └── TransactionViewModelTests.swift    # MODIFY — add update test
```

---

### Task 1: Add `updateTransaction` to TransactionViewModel

**Files:**
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/TransactionViewModel.swift`
- Modify: `SlaveOfCapitalism/SlaveOfCapitalismTests/TransactionViewModelTests.swift`

- [x] **Step 1: Extend TransactionAPIStub with update tracking**

In `TransactionViewModelTests.swift`, the existing `TransactionAPIStub` class (starts after the test cases, search for `private final class TransactionAPIStub: APIClientProtocol`) has `updateTransaction` at line ~200 that calls `fatalError("Unused")`. Add tracking fields and replace the fatalError:

```swift
// Add these properties to TransactionAPIStub (alongside existing deletedTransactionIds etc.)
var updateCalledWithId: Int?
var updateCalledWithBody: TransactionUpdate?
```

Replace the existing `updateTransaction` stub:
```swift
// BEFORE:
func updateTransaction(id: Int, _ body: TransactionUpdate) async throws -> TransactionResponse { fatalError("Unused") }

// AFTER:
func updateTransaction(id: Int, _ body: TransactionUpdate) async throws -> TransactionResponse {
    updateCalledWithId = id
    updateCalledWithBody = body
    return TransactionResponse(
        id: id, date: "2026-01-15", time: nil, walletId: 1,
        direction: .outflow, amount: 100, classification: .expense,
        description: "Updated", categoryId: nil, subcategoryId: nil,
        pairedTransactionId: nil, isIgnored: false, isCalibration: false,
        createdAt: "2026-01-01T00:00:00", updatedAt: "2026-01-01T00:00:00"
    )
}
```

- [x] **Step 2: Write the failing test**

Add this test to the `TransactionViewModelTests` class:

```swift
func testUpdateTransactionReloadsData() async {
    let stub = TransactionAPIStub()
    stub.listTransactionsHandler = { _ in [Self.sampleTransaction()] }
    let viewModel = TransactionViewModel(apiClient: stub)

    await viewModel.load()
    XCTAssertEqual(viewModel.transactions.count, 1)

    let update = TransactionUpdate(description: "Updated")
    await viewModel.updateTransaction(id: 1, update)

    XCTAssertNil(viewModel.error)
    XCTAssertEqual(stub.updateCalledWithId, 1)
    // load() was called again after update (listTransactionsMonths has 2 entries: initial + reload)
    XCTAssertEqual(stub.listTransactionsMonths.count, 2)
}
```

- [x] **Step 3: Run test to verify it fails**

Run: `cd /Volumes/Documents/sources/slave-of-capitalism/SlaveOfCapitalism && xcodebuild test -scheme SlaveOfCapitalismTests -destination 'platform=macOS' -only-testing:SlaveOfCapitalismTests/TransactionViewModelTests/testUpdateTransactionReloadsData 2>&1 | tail -20`

Expected: Compile error — `updateTransaction` does not exist on `TransactionViewModel`.

- [x] **Step 4: Implement `updateTransaction` on the view model**

Add to `TransactionViewModel.swift` (after the existing `unignoreSelected()` method):

```swift
func updateTransaction(id: Int, _ body: TransactionUpdate) async {
    do {
        _ = try await apiClient.updateTransaction(id: id, body)
        await load()
    } catch let apiError as APIError {
        error = apiError
    } catch is CancellationError {
        // Ignore
    } catch {
        self.error = .networkError(error)
    }
}
```

- [x] **Step 5: Run test to verify it passes**

Run: `cd /Volumes/Documents/sources/slave-of-capitalism/SlaveOfCapitalism && xcodebuild test -scheme SlaveOfCapitalismTests -destination 'platform=macOS' -only-testing:SlaveOfCapitalismTests/TransactionViewModelTests/testUpdateTransactionReloadsData 2>&1 | tail -20`

Expected: PASS

- [x] **Step 6: Commit**

```bash
cd /Volumes/Documents/sources/slave-of-capitalism && git add SlaveOfCapitalism/SlaveOfCapitalism/ViewModels/TransactionViewModel.swift SlaveOfCapitalism/SlaveOfCapitalismTests/TransactionViewModelTests.swift && git commit -m "feat: add updateTransaction to TransactionViewModel"
```

---

### Task 2: Create `EditableTextCell` component

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/EditableTextCell.swift`

A reusable component that shows `Text` in read mode and `TextField` in edit mode. Uses focus loss as the single commit path (Enter key sets `isFocused = false` which triggers the commit via `onChange`). This prevents double-commits.

- [x] **Step 1: Create `EditableTextCell.swift`**

```swift
import SwiftUI

struct EditableTextCell: View {
    let value: String
    let isEditing: Bool
    @Binding var editText: String
    var alignment: Alignment = .leading
    var foregroundStyle: AnyShapeStyle = AnyShapeStyle(.primary)
    var font: Font = .body
    let onBeginEdit: () -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(font)
                    .focused($isFocused)
                    .onSubmit {
                        // Don't call onCommit directly — just remove focus.
                        // The onChange(of: isFocused) handler below is the single commit path.
                        isFocused = false
                    }
                    .onExitCommand {
                        onCancel()
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            onCommit(editText)
                        }
                    }
                    .onAppear {
                        isFocused = true
                    }
            } else {
                Text(value)
                    .font(font)
                    .foregroundStyle(foregroundStyle)
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onBeginEdit()
                    }
            }
        }
    }
}
```

- [x] **Step 2: Regenerate Xcode project and verify it compiles**

Run: `cd /Volumes/Documents/sources/slave-of-capitalism/SlaveOfCapitalism && xcodegen generate && cd .. && make swiftui-verify 2>&1 | tail -10`

Expected: Build succeeds.

- [x] **Step 3: Commit**

```bash
cd /Volumes/Documents/sources/slave-of-capitalism && git add SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/EditableTextCell.swift && git commit -m "feat: add EditableTextCell component for inline table editing"
```

---

### Task 3: Create `EditableCategoryPicker` component

**Files:**
- Create: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/EditableCategoryPicker.swift`

A component that shows category text in read mode and a two-level category/subcategory picker with OK/Cancel buttons in edit mode. Uses `.menu` picker style for compact inline display.

- [x] **Step 1: Create `EditableCategoryPicker.swift`**

```swift
import SwiftUI

struct EditableCategoryPicker: View {
    let displayText: String
    let isEditing: Bool
    let isUncategorized: Bool
    let categories: [CategoryWithSubcategories]
    @Binding var selectedCategoryId: Int
    @Binding var selectedSubcategoryId: Int
    let onBeginEdit: () -> Void
    let onCommit: (Int?, Int?) -> Void
    let onCancel: () -> Void

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 4) {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("Uncategorized").tag(0)
                        ForEach(categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: selectedCategoryId) { _, _ in
                        selectedSubcategoryId = 0
                    }

                    if let category = categories.first(where: { $0.id == selectedCategoryId }),
                       !category.subcategories.isEmpty {
                        Picker("Sub", selection: $selectedSubcategoryId) {
                            Text("None").tag(0)
                            ForEach(category.subcategories) { sub in
                                Text(sub.name).tag(sub.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Button("OK") {
                        let catId = selectedCategoryId == 0 ? nil : selectedCategoryId
                        let subId = selectedSubcategoryId == 0 ? nil : selectedSubcategoryId
                        onCommit(catId, subId)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .onExitCommand {
                    onCancel()
                }
            } else {
                Text(displayText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(isUncategorized ? .secondary : .primary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onBeginEdit()
                    }
            }
        }
    }
}
```

Note: The `isUncategorized` flag is passed from the parent using the transaction's actual `categoryId`, not from the shared editing state. This avoids stale styling from previous edits.

- [x] **Step 2: Regenerate Xcode project and verify it compiles**

Run: `cd /Volumes/Documents/sources/slave-of-capitalism/SlaveOfCapitalism && xcodegen generate && cd .. && make swiftui-verify 2>&1 | tail -10`

Expected: Build succeeds.

- [x] **Step 3: Commit**

```bash
cd /Volumes/Documents/sources/slave-of-capitalism && git add SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/EditableCategoryPicker.swift && git commit -m "feat: add EditableCategoryPicker for inline category selection"
```

---

### Task 4: Wire inline editing into TransactionListView

**Files:**
- Modify: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/TransactionListView.swift`

This is the main integration task. Replace the read-only `interactiveCell` pattern with editable cells. **Important:** Line numbers below are approximate — find code by the content patterns described (e.g., `TableColumn("Date")`, `TableColumn("Description")`, etc.).

- [x] **Step 1: Add editing state properties**

Add these `@State` properties to `TransactionListView` (alongside the existing `@State` properties near the top of the struct):

```swift
@State private var editingTransactionId: Int?
@State private var editingField: EditableField?
@State private var editText: String = ""
@State private var editWalletId: Int = 0
@State private var editCategoryId: Int = 0
@State private var editSubcategoryId: Int = 0

private enum EditableField: Hashable {
    case date, description, wallet, category, amount
}
```

- [x] **Step 2: Replace the Date column with an editable cell**

Find the `TableColumn("Date")` closure. It currently shows a VStack with `transaction.date` and optional `transaction.time`. Replace it with:

```swift
TableColumn("Date") { transaction in
    VStack(alignment: .leading, spacing: 2) {
        EditableTextCell(
            value: transaction.date,
            isEditing: isEditing(transaction, field: .date),
            editText: $editText,
            font: .body,
            onBeginEdit: { beginEdit(transaction, field: .date, text: transaction.date) },
            onCommit: { newValue in commitDateEdit(transaction, newValue: newValue, viewModel: viewModel) },
            onCancel: { cancelEdit() }
        )
        if let time = transaction.time, !isEditing(transaction, field: .date) {
            Text(time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
}
```

Note: The time sub-line is preserved in read mode and hidden during date editing.

- [x] **Step 3: Replace the Description column with an editable cell**

Find the `TableColumn("Description")` closure. It currently wraps `TransactionRow(transaction:)` in `interactiveCell`. Replace it with:

```swift
TableColumn("Description") { transaction in
    VStack(alignment: .leading, spacing: 4) {
        EditableTextCell(
            value: transaction.description?.isEmpty == false ? transaction.description! : "Untitled Transaction",
            isEditing: isEditing(transaction, field: .description),
            editText: $editText,
            onBeginEdit: { beginEdit(transaction, field: .description, text: transaction.description ?? "") },
            onCommit: { newValue in commitDescriptionEdit(transaction, newValue: newValue, viewModel: viewModel) },
            onCancel: { cancelEdit() }
        )

        if !isEditing(transaction, field: .description) {
            HStack(spacing: 6) {
                Text(transaction.classification.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if transaction.isIgnored {
                    badge("Ignored", tint: .orange)
                }
                if transaction.hasLinkedEntry {
                    badge("Linked", tint: .blue)
                }
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
}
```

- [x] **Step 4: Replace the Wallet column with an editable picker**

Find the `TableColumn("Wallet")` closure. Replace it with a picker that has OK/Cancel buttons (consistent with the Category picker):

```swift
TableColumn("Wallet") { transaction in
    Group {
        if isEditing(transaction, field: .wallet) {
            HStack(spacing: 4) {
                Picker("Wallet", selection: $editWalletId) {
                    ForEach(walletStore.wallets) { wallet in
                        Text(wallet.name).tag(wallet.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Button("OK") {
                    commitWalletEdit(transaction, newWalletId: editWalletId, viewModel: viewModel)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    cancelEdit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .onExitCommand { cancelEdit() }
        } else {
            Text(transaction.walletName ?? walletStore.wallet(for: transaction.walletId)?.name ?? "Unknown")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    editWalletId = transaction.walletId
                    editingTransactionId = transaction.id
                    editingField = .wallet
                }
        }
    }
    .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
}
```

- [x] **Step 5: Replace the Category column with the editable picker**

Find the `TableColumn("Category")` closure. Replace it with:

```swift
TableColumn("Category") { transaction in
    EditableCategoryPicker(
        displayText: categoryTitle(for: transaction),
        isEditing: isEditing(transaction, field: .category),
        isUncategorized: transaction.categoryId == nil && transaction.subcategoryId == nil,
        categories: categoryStore.categories,
        selectedCategoryId: $editCategoryId,
        selectedSubcategoryId: $editSubcategoryId,
        onBeginEdit: {
            editCategoryId = transaction.categoryId ?? 0
            editSubcategoryId = transaction.subcategoryId ?? 0
            editingTransactionId = transaction.id
            editingField = .category
        },
        onCommit: { catId, subId in commitCategoryEdit(transaction, categoryId: catId, subcategoryId: subId, viewModel: viewModel) },
        onCancel: { cancelEdit() }
    )
    .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
}
```

- [x] **Step 6: Replace the Amount column with an editable cell**

Find the `TableColumn("Amount")` closure. Replace it with:

```swift
TableColumn("Amount") { transaction in
    EditableTextCell(
        value: amountTitle(for: transaction),
        isEditing: isEditing(transaction, field: .amount),
        editText: $editText,
        alignment: .trailing,
        foregroundStyle: AnyShapeStyle(amountColor(for: transaction)),
        onBeginEdit: { beginEdit(transaction, field: .amount, text: transaction.amount.description) },
        onCommit: { newValue in commitAmountEdit(transaction, newValue: newValue, viewModel: viewModel) },
        onCancel: { cancelEdit() }
    )
    .contextMenu { rowContextMenu(for: transaction, viewModel: viewModel) }
}
```

- [x] **Step 7: Add helper methods for edit state management**

Add these private methods to `TransactionListView` (after the existing helper methods, before the closing `}`):

```swift
private func isEditing(_ transaction: TransactionWithDetails, field: EditableField) -> Bool {
    editingTransactionId == transaction.id && editingField == field
}

private func beginEdit(_ transaction: TransactionWithDetails, field: EditableField, text: String) {
    editText = text
    editingTransactionId = transaction.id
    editingField = field
}

private func cancelEdit() {
    editingTransactionId = nil
    editingField = nil
    editText = ""
}
```

- [x] **Step 8: Add commit methods for each field**

Add these private methods:

```swift
private func commitDateEdit(_ transaction: TransactionWithDetails, newValue: String, viewModel: TransactionViewModel) {
    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
    // Validate date format (yyyy-MM-dd)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    guard !trimmed.isEmpty, trimmed != transaction.date, formatter.date(from: trimmed) != nil else {
        cancelEdit()
        return
    }
    cancelEdit()
    Task {
        await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(date: trimmed))
        await walletStore.refresh()
    }
}

private func commitDescriptionEdit(_ transaction: TransactionWithDetails, newValue: String, viewModel: TransactionViewModel) {
    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed != (transaction.description ?? "") else {
        cancelEdit()
        return
    }
    cancelEdit()
    Task {
        await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(description: trimmed))
    }
}

private func commitWalletEdit(_ transaction: TransactionWithDetails, newWalletId: Int, viewModel: TransactionViewModel) {
    guard newWalletId != transaction.walletId else {
        cancelEdit()
        return
    }
    cancelEdit()
    Task {
        await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(walletId: newWalletId))
        await walletStore.refresh()
    }
}

private func commitCategoryEdit(_ transaction: TransactionWithDetails, categoryId: Int?, subcategoryId: Int?, viewModel: TransactionViewModel) {
    guard categoryId != transaction.categoryId || subcategoryId != transaction.subcategoryId else {
        cancelEdit()
        return
    }
    cancelEdit()
    Task {
        await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(categoryId: categoryId, subcategoryId: subcategoryId))
    }
}

private func commitAmountEdit(_ transaction: TransactionWithDetails, newValue: String, viewModel: TransactionViewModel) {
    guard let amount = Decimal(string: newValue), amount > 0, amount != transaction.amount else {
        cancelEdit()
        return
    }
    cancelEdit()
    Task {
        await viewModel.updateTransaction(id: transaction.id, TransactionUpdate(amount: amount))
        await walletStore.refresh()
    }
}
```

- [x] **Step 9: Remove the old `interactiveCell` helper and add badge helper**

Delete the `interactiveCell` method (search for `private func interactiveCell<Content: View>` — it wraps content in contextMenu + onTapGesture that opens `selectedTransaction` detail sheet).

The old onTapGesture that opened the detail sheet is replaced by per-cell onTapGesture that begins editing. Keep the `selectedTransaction` sheet for the "Open Details" context menu action only.

Add the badge helper (previously in `TransactionRow`):

```swift
private func badge(_ title: String, tint: Color) -> some View {
    Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
}
```

- [x] **Step 10: Regenerate Xcode project and verify it compiles**

Run: `cd /Volumes/Documents/sources/slave-of-capitalism/SlaveOfCapitalism && xcodegen generate && cd .. && make swiftui-verify 2>&1 | tail -10`

Expected: Build succeeds. Fix any compile errors before proceeding.

- [x] **Step 11: Commit**

```bash
cd /Volumes/Documents/sources/slave-of-capitalism && git add SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/TransactionListView.swift && git commit -m "feat: wire inline editing into transactions table"
```

---

### Task 5: Final build verification and cleanup

**Files:**
- Possibly delete: `SlaveOfCapitalism/SlaveOfCapitalism/Views/Transactions/TransactionRow.swift`

- [x] **Step 1: Run all tests**

Run: `cd /Volumes/Documents/sources/slave-of-capitalism/SlaveOfCapitalism && xcodebuild test -scheme SlaveOfCapitalismTests -destination 'platform=macOS' 2>&1 | tail -30`

Expected: All tests pass.

- [x] **Step 2: Check if TransactionRow is still used elsewhere**

Search for `TransactionRow` in all Swift files under `SlaveOfCapitalism/SlaveOfCapitalism/`. If it's no longer referenced anywhere (we replaced its usage in the Description column), delete `TransactionRow.swift`.

- [x] **Step 3: Commit any cleanup**

```bash
cd /Volumes/Documents/sources/slave-of-capitalism && git add -A SlaveOfCapitalism/ && git commit -m "chore: cleanup after inline editing integration"
```

- [x] **Step 4: Update the parent plan**

Mark Task 18A as complete in `docs/superpowers/plans/2026-03-22-swiftui-port.md`.
