# Expense Manager - Business Requirements & User Stories

This document defines the **User Stories** (what the user wants to achieve) and the corresponding **Technical Specifications** (how the system supports it).

---

## 📖 part 1: User Stories

### 1. The "True Expense" Story
> "I want to track my *actual* spending, not just money leaving my wallet."

*   **Scenario A (Lending)**: I lend Bob ¥5,000 for lunch. Money leaves my wallet, but I haven't "spent" it because I'll get it back.
    *   *Requirement*: This transaction should **NOT** count towards my monthly expense report. The system must remember Bob owes me ¥5,000.
*   **Scenario B (Borrowing)**: I borrow ¥10,000 from Alice depending on cash flow. Money enters my wallet, but it is **NOT** income.
    *   *Requirement*: This transaction should **NOT** count as monthly income. The system must remember I owe Alice ¥10,000.
*   **Scenario C (Split Payment)**: I pay ¥3,000 for dinner for myself and Bob.
    *   *Requirement*: Only my share (¥1,500) counts as an expense. The other ¥1,500 is recorded as money Bob owes me.

### 2. The "Excel-Like Workflow" Story
> "I want to manage transactions as fast as I do in Excel, without navigating through endless menus."

*   **Viewing**: I want to see one month's data at a time, just like tabs in a spreadsheet.
*   **Editing**: If I made a mistake, I want to click the cell (Amount, Description, Category) and type the new value. No "Edit Button" -> "New Page" -> "Save" -> "Back" flow.
*   **Filtering**: I want to click a column header and filter by "Amount > ¥4000" or "Category = Food" to find specific records instantly.
*   **Correction**: If I mistakenly marked a transaction as a Split or Loan, I want to right-click and "Unclassify" it to revert it to a simple Expense or Income.

### 3. The "Financial Snapshot" Story
> "I want to know if I'm sticking to my budget right now."

*   **Budgeting**: I set a budget for "Food".
*   **Tracking**: I want to see a table comparing my Budget vs. Actual Spending.
*   **Pacing**: I want to see my spending broken down by weaks (Day 1-7, 8-12, etc.) to see if I'm spending too fast early in the month.

### 4. The "Wallet Management" Story
> "I have cash, bank accounts, and credit cards. I want to know where my money is."

*   **Transferring**: I withdraw ¥10,000 from the Bank to Cash. I want to record this as one action, not two separate entries.
*   **Credit Cards**: I want to know how much debt I've accumulated on my Visa card, not just the "balance".

### 5. The "Payback" Story
> "When someone pays me back, I want to easily record it."

*   **Receiving**: When Bob pays me back the ¥1,500 for dinner, I want to right-click the original transaction (or use a dedicated list) and say "Link Payment".
*   **Result**: The system should know Bob's debt is cleared, and this money coming in is **NOT** strictly "income" (it's just reimbursement).

---

### 6. The "Consolidate" Story
> "I made 5 small purchases at '7-Eleven' on the same day. I want to merge them into one '7-Eleven Run' entry."

*   **Merging**: I want to select multiple transactions, right-click, and "Merge".
*   **Result**: They become one transaction with the sum of amounts. The old ones are gone.

---

## 🛠️ Part 2: Technical Specifications


To support the stories above, the backend is implemented as follows:

### 1. Financial Concepts (Backend Models)
To solve "True Expense", we separate **Direction** (Physics) from **Classification** (Meaning).

*   **Direction**: `INFLOW` (In) vs `OUTFLOW` (Out).
*   **Classification** (The "Meaning"):
    *   `EXPENSE`: True spending.
    *   `INCOME`: True earning.
    *   `LEND`: I lent money (Asset).
    *   `BORROW`: I borrowed money (Liability).
    *   `SPLIT_PAYMENT`: Part expense, part loan.
    *   `DEBT_COLLECTION`: Getting money back (Not income).
    *   `LOAN_REPAYMENT`: Paying money back (Not expense).
    *   `TRANSFER`: Moving money (Neutral).

### 2. Implementation: Linked Entries
To solve the "Payback" story, we use a `LinkedEntry` system.

*   **LinkedEntry**: Created when you Lend or Split. Tracks `total_amount`, `user_amount` (your share), and `pending_amount` (what they owe).
*   **LinkedTransaction**: When a payback transaction occurs (e.g., Bob sends money), we **link** it to the `LinkedEntry`. This reduces the `pending_amount`.
*   **Unclassification**: When unclassifying a primary transaction (undoing a split/loan), the system:
    1.  Deletes the `LinkedEntry`.
    2.  Reverts the primary transaction to `EXPENSE` or `INCOME`.
    3.  **Crucially**: Finds any linked reimbursements (`LinkedTransaction`) and reverts them to `INCOME` (from `DEBT_COLLECTION`) or `EXPENSE` (from `LOAN_REPAYMENT`) to ensure data consistency.

### 3. Frontend Architecture (Tauri + Svelte)
To solve the "Excel-Like" story:

*   **State Management**: Load all transactions for the selected month into memory.
*   **Filtering**: Client-side filtering (like Excel)
*   **Inline Editing**: Frontend updates local state immediately for responsiveness and syncs with backend in background (debounced).
*   **Context Menus**: Right-clicking a row allows advanced logic (e.g., "Mark as Split" -> opens a modal to define shares).

### 4. Logic & Calculations
To solve "Financial Snapshot":

*   **Monthly Expense Formula**:
    ```python
    Sum(OUTFLOW transactions where classification == EXPENSE)
    + Sum(LinkedEntry.user_amount for SPLIT_PAYMENTS)
    # Note: Lends and Transfers are EXCLUDED.
    ```
*   **Period Columns**: The Summary screen aggregates these separate from the total to show pacing (Day 1-7, 8-12, etc.).

### 5. API Structure
*   `GET /transactions`: Supports filtering by month/wallet.
*   `DELETE /transactions`: Bulk delete.
*   `POST /transactions/ignore`: Bulk ignore.
*   `POST /transactions/unignore`: Bulk unignore.
*   `POST /transactions/link`: Bulk link transactions to a LinkedEntry.
*   `POST /transactions/{id}/mark-split`: Creates a split payment configuration (single).
*   `POST /transactions/{id}/mark-loan`: Marks as loan (single).
*   `POST /transactions/{id}/mark-debt`: Marks as debt (single).
*   `POST /transactions/{id}/unclassify`: Reverts classification and cleans up links (single).
*   `PUT /linked-entries/{entry_id}`: Updates linked entry details (amounts, names).

### 6. Bulk Operations
To solve "Manage effectively" and "Payback multiple items":

*   **Atomicity**: Bulk operations (Delete, Ignore, Link) must succeed for ALL selected items or fail for ALL.
    *   If one transaction in a bulk delete fails (e.g., locked), the database rolls back the entire operation.
*   **Bulk Linking**: Users can select multiple INFLOW transactions to settle a single Split Payment or Loan.
    *   Constraint: All selected transactions must match the direction required by the LinkedEntry (e.g. INFLOW for Split/Loan).
    *   Logic: The sum of all selected transactions decreases the `pending_amount` of the LinkedEntry. Each transaction is linked individually but processed in one atomic commit.

### 7. Calibration & Resolution (New)
To solve "Unknown discrepancies", we use `is_calibration`.

*   **Calibration Transaction**: Created when calibrating a wallet. Represents the difference between calculated and actual balance.
    *   Direction: OUTFLOW (if missing money) or INFLOW (if extra money).
    *   Classification: EXPENSE (unknown expense) or INCOME (unknown income).
*   **Resolution**: When a user identifies the real transaction behind a calibration:
    1.  User creates the **Real Transaction** T.
    2.  System adjusts the Calibration transaction C:
        *   **Constraint**: `T.wallet_id` MUST match `C.wallet_id`. The user cannot resolve a calibration in Wallet A using a transaction in Wallet B.
        *   If `T.direction == C.direction`: `C.amount = C.amount - T.amount` (Subtract magnitude).
        *   If `T.direction != C.direction`: `C.amount = C.amount + T.amount` (Add magnitude, because the "hole" just got bigger).
    3.  **Completion Logic**:
        *   If `C.amount == 0`: C is KEPT but marked `is_ignored=True`. This preserves the history that a calibration happened and was fully resolved.
        *   If `C.amount < 0`: C is KEPT, `is_ignored=False`. 
            *   **Direction Flip**: INFLOW <-> OUTFLOW.
            *   **Classification Flip**: EXPENSE <-> INCOME (to match new direction).
            *   **Amount**: Becomes positive (absolute value).
            
### 8. Merge Logic
To support "Consolidate" (Story 6):

*   **Validation**:
    *   Requires 2+ transactions.
    *   Must share **Wallet** and **Direction**.
*   **New Transaction**:
    *   `Amount`: Sum of selected amounts.
    *   `Date/Description/Category`: User input from modal.
    *   **Classification**:
        *   If all selected have the same classification (e.g. all `EXPENSE`), inherit it.
        *   Else, default to `EXPENSE` (for Outflow) or `INCOME` (for Inflow).
*   **Special Types**:
    *   Merging "special" transactions is **NOT allowed**. this includes:
        *   `SPLIT_PAYMENT`, `LEND`, `BORROW`, `DEBT_COLLECTION`, `LOAN_REPAYMENT`, `TRANSFER`.
        *   Calibration transactions (`is_calibration=True`).
    *   Only `EXPENSE` and `INCOME` transactions (the "Normal" types) can be merged.
    *   *Reason*: Special transactions have complex lifecycle rules (LinkedEntries, paired transactions) that are dangerous to silently destroy in a merge.
*   **Atomicity**: The creation of the new transaction and deletion of old ones happens in one database commit.

### 9. Monthly Summary & Subcategories
To solve "Where exactly did my money go?":

*   **Logic**: The `GET /budgets/summary` endpoint returns a hierarchical view.
*   **Subcategory Aggregation**: expenses are aggregated not just by Category, but also individually by Subcategory.
    *   `Category.actual` = Sum of all subcategory actuals + Uncategorized transactions in that category.
    *   `Subcategory.actual` = Sum of expenses tagged with that specific subcategory.
*   **Frontend**: The Summary table supports expanding Categories to reveal Subcategory rows.
    *   Subcategory rows show "Actual" and "Period" data.
    *   Budgeting is currently restricted to the Parent Category level.

### 10. Category & Subcategory Management
To solve "Organize my spending":

*   **Categories**: Users can create, update, and delete categories.
    *   **System Categories**: Pre-defined categories (e.g., "Miscellaneous", "Unexpected expenses") cannot be deleted or edited.
    *   **User Categories**: User-created categories can be freely managed.
*   **Subcategories**: Each category can have multiple subcategories for fine-grained tracking.
    *   **System Subcategories**: Pre-defined subcategories cannot be deleted or edited.
    *   **User Subcategories**: User-created subcategories can be freely managed.
*   **Deletion with Replacement**: When deleting a category or subcategory that has associated transactions:
    *   **Requirement**: A replacement category (and optionally subcategory) must be provided.
    *   **Logic**: All transactions using the deleted category/subcategory are automatically reassigned to the replacement.
    *   **Atomicity**: The reassignment and deletion happen in a single database transaction.
    *   **Validation**: 
        *   System categories/subcategories cannot be deleted (raises error).
        *   If transactions exist but no replacement is provided, deletion fails with a clear error message.
        *   Replacement category/subcategory must exist and be valid.
*   **API Endpoints**:
    *   `GET /api/categories`: List all categories with subcategories.
    *   `POST /api/categories`: Create a new category.
    *   `PUT /api/categories/{id}`: Update a category.
    *   `DELETE /api/categories/{id}?replacement_category_id={id}&replacement_subcategory_id={id}`: Delete a category with optional replacement.
    *   `POST /api/categories/{id}/subcategories`: Create a subcategory under a category.
    *   `PUT /api/categories/subcategories/{id}`: Update a subcategory.
    *   `DELETE /api/categories/subcategories/{id}?replacement_category_id={id}&replacement_subcategory_id={id}`: Delete a subcategory with optional replacement.

### 11. Architecture & Code Principles
To maintain a clean and maintainable codebase:

*   **Service Layer Pattern**: All business logic and database interactions must reside in `services/`.
    *   **Atomicity**: Database transactions (commit/rollback) are EXCLUSIVELY handled within Service functions.
    *   **Routers**: Routers are "thin" controllers. They only:
        1.  Validate input (mostly via Pydantic).
        2.  Call Service methods.
        3.  Return responses or raise HTTP exceptions.
    *   *Constraint*: Routers MUST NOT call `db.commit()` directly.

    
---

**Reading this document provides full context of the User's needs (Stories) and the System's design (Tech Specs).**

### 12. Wallet Balance Optimization (Snapshots)
To solve "Calculations are too slow with years of history":

*   **Problem**: Summing every transaction from $T=0$ to calculate a balance is $O(N)$. As history grows, performance degrades.
*   **Solution**: **Snapshot-Based Calculation**.

#### A. Snapshot Definitions
*   **Content**: A `WalletSnapshot` stores the wallet's total balance at the *end of day* of the `snapshot_date`.
*   **Inclusion Rule**: Snapshot Balance = Sum of ALL transactions where `transaction.date <= snapshot.date`.
    *   *Note*: This is an inclusive sum. A snapshot on "Nov 5" includes all transactions happened on Nov 5.

#### B. Live Balance Calculation
*   **Formula**: `Current Balance` = `Latest Snapshot Balance` + `Delta`
*   **Delta Calculation**: Sum of transactions where:
    1.  `transaction.date > latest_snapshot.date` (Strictly AFTER the checkpoint)
    2.  `transaction.date <= today` (Excluding future transactions)
*   **Ignored Transactions**: Transactions with `is_ignored=True` are **INCLUDED** in the balance calculation (they affect the wallet). They are only excluded from Income/Expense reports.

#### C. Lazy Snapshot Creation
*   **Strategy**: Snapshots are created on-the-fly during read operations (`get_balance`).
*   **Trigger**: If the latest snapshot is older than 7 days (from Today), the system:
    1.  Calculates the balance for "Yesterday" (`today - 1`).
    2.  Saves this as a new Snapshot.
    3.  Returns the calculated current balance.

#### D. Cache Invalidation (Safety)
*   **Rule**: Modifying, Creating, or Deleting a transaction on `Date X` invalidates ALL snapshots where `snapshot.date >= X`.
    *   *Reasoning*: Since a snapshot on Date X includes transactions from Date X, changing history on that date renders the snapshot (and all future ones) stale.
*   **Chain Reaction**: This creates a "domino effect". Inserting a transaction 1 year ago wipes out 1 year of snapshots, forcing a safe recalculation from scratch (or the next oldest valid snapshot).
*   **Large Cache Rebuild Protection**:
    *   If a modification affects > 5,000 historical transactions (and the transaction is > 90 days old), the operation is blocked.
    *   **Override**: User must verify via `allow_large_cache_rebuild=True`.
