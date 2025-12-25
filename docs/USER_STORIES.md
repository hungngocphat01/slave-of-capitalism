# User Stories & API Endpoints

This document organizes all application functionality by user stories. Each user story is mapped to one or more API endpoints with expected behavior.

---

## Table of Contents

1. [Wallet Management](#wallet-management)
2. [Basic Transactions](#basic-transactions)
3. [Wallet Transfers](#wallet-transfers)
4. [Split Payments](#split-payments)
5. [Loans & Lending](#loans--lending)
6. [Debts & Borrowing](#debts--borrowing)
7. [Installment Payments](#installment-payments)
8. [Categories & Budgets](#categories--budgets)
9. [Reports & Summaries](#reports--summaries)

---

## Wallet Management

### US-W1: Create a Wallet

**As a user**, I want to create a new wallet to track my money.

#### API Endpoint
```http
POST /api/wallets
Content-Type: application/json

{
  "name": "Cash",
  "wallet_type": "normal",
  "currency": "VND",
  "initial_balance": 10000.00,
  "emoji": "💵"
}
```

#### Expected Behavior
1. Create wallet in database
2. Create initial balance transaction:
   - Direction: `INFLOW`
   - Amount: `initial_balance`
   - Classification: `INCOME`
   - Description: "INITIAL BALANCE"
   - `is_ignored`: `true`
3. Return created wallet

#### Business Rules
- Wallet name must be unique
- `wallet_type`: `normal` or `credit`
- For `credit` wallets, provide `credit_limit` instead of `initial_balance`

---

### US-W2: View Wallet Balance

**As a user**, I want to see my current wallet balance.

#### API Endpoint
```http
GET /api/wallets/{wallet_id}/balance
```

#### Response
```json
{
  "wallet_id": 1,
  "wallet_name": "Cash",
  "wallet_type": "normal",
  "balance": 12000.00,
  "available_credit": null
}
```

#### Calculation Logic

**Normal Wallet**:
```
Balance = Σ(INFLOW) - Σ(OUTFLOW)
```

**Credit Wallet**:
```
Balance = Σ(OUTFLOW) - Σ(INFLOW)  // Positive = debt
Available = Credit Limit - Balance - Pending Installments
```

**See**: [BALANCE_CALCULATION.md](./BALANCE_CALCULATION.md) for detailed logic

---

## Basic Transactions

### US-T1: Record an Expense

**As a user**, I want to record money I spent.

#### API Endpoint
```http
POST /api/transactions
Content-Type: application/json

{
  "date": "2025-12-25",
  "time": "14:30:00",
  "wallet_id": 1,
  "direction": "outflow",
  "amount": 3000.00,
  "classification": "expense",
  "description": "Groceries",
  "category_id": 5
}
```

#### Expected Behavior
1. Create transaction in database
2. Invalidate wallet snapshots from this date forward
3. Update wallet balance (if queried)

#### Business Rules
- Amount must be positive
- `direction`: `outflow` for expenses
- `classification`: `expense` for regular spending

---

### US-T2: Record Income

**As a user**, I want to record money I received.

#### API Endpoint
```http
POST /api/transactions
Content-Type: application/json

{
  "date": "2025-12-25",
  "wallet_id": 1,
  "direction": "inflow",
  "amount": 5000.00,
  "classification": "income",
  "description": "Salary"
}
```

#### Expected Behavior
- Same as US-T1, but increases wallet balance

---

### US-T3: Delete a Transaction

**As a user**, I want to delete a transaction I recorded by mistake.

#### API Endpoint
```http
DELETE /api/transactions/{transaction_id}
```

#### Expected Behavior
1. Check if transaction has special relationships:
   - **Paired transfer**: Delete both transactions
   - **Primary of linked entry**: Delete linked entry (cascades to linked transactions)
   - **Linked to entry**: Unlink first, then delete
2. Delete transaction
3. Invalidate wallet snapshots

#### Business Rules
- Cascade deletes for paired transfers and linked entries
- Cannot delete if part of a settled linked entry (user must unlink first)

---

## Wallet Transfers

### US-WT1: Transfer Money Between Wallets

**As a user**, I want to move money from one wallet to another.

#### API Endpoint
```http
POST /api/transactions/wallet-transfer
Content-Type: application/json

{
  "from_wallet_id": 1,
  "to_wallet_id": 2,
  "amount": 5000.00,
  "date": "2025-12-25",
  "description": "Transfer to savings"
}
```

#### Expected Behavior
1. Create **two** transactions atomically:
   ```
   Transaction 1 (Outflow):
   - wallet_id: from_wallet_id
   - direction: OUTFLOW
   - amount: amount
   - classification: TRANSFER
   - paired_transaction_id: Transaction 2 ID
   
   Transaction 2 (Inflow):
   - wallet_id: to_wallet_id
   - direction: INFLOW
   - amount: amount
   - classification: TRANSFER
   - paired_transaction_id: Transaction 1 ID
   ```
2. Link them via `paired_transaction_id`
3. Invalidate snapshots for both wallets

#### Response
```json
{
  "outflow_transaction": {...},
  "inflow_transaction": {...}
}
```

#### Business Rules
- **Atomic operation**: Both transactions created or neither
- Amount must be identical
- Both wallets must exist

---

## Split Payments

### US-SP1: Pay for Others (Split a Bill)

**As a user**, I want to record that I paid for someone else and they owe me money.

#### API Endpoint
```http
POST /api/transactions/{transaction_id}/mark-split
Content-Type: application/json

{
  "counterparty_name": "Bob",
  "user_amount": 1500.00,
  "notes": "Dinner at restaurant"
}
```

#### Prerequisites
- Transaction must exist
- Transaction must be `OUTFLOW`
- Transaction `amount` must be >= `user_amount`

#### Expected Behavior
1. Update transaction:
   - `classification`: `EXPENSE` → `SPLIT_PAYMENT`
2. Create `LinkedEntry`:
   ```
   {
     "link_type": "SPLIT_PAYMENT",
     "primary_transaction_id": transaction_id,
     "counterparty_name": "Bob",
     "total_amount": 3000.00,
     "user_amount": 1500.00,
     "pending_amount": 1500.00,  // Others owe you
     "status": "PENDING"
   }
   ```

#### Response
```json
{
  "id": 1,
  "link_type": "split_payment",
  "counterparty_name": "Bob",
  "total_amount": 3000.00,
  "user_amount": 1500.00,
  "pending_amount": 1500.00,
  "status": "pending"
}
```

#### Financial Impact
- **Wallet Balance**: -¥3,000 (full amount paid)
- **Monthly Expense**: -¥1,500 (only your share)
- **Pending Owed**: +¥1,500 (Bob owes you)

---

### US-SP2: Receive Reimbursement for Split Payment

**As a user**, I want to record when someone pays me back for a split bill.

#### API Endpoint
```http
POST /api/linked-entries/{linked_entry_id}/link
Content-Type: application/json

{
  "transaction_ids": [123]
}
```

#### Prerequisites
1. Create transaction for money received:
   ```http
   POST /api/transactions
   {
     "wallet_id": 1,
     "direction": "inflow",
     "amount": 1500.00,
     "classification": "income",  // Will be changed to debt_collection
     "description": "Bob's share for dinner"
   }
   ```

2. Link it to the split payment

#### Expected Behavior
1. Validate transaction direction is `INFLOW`
2. Update transaction:
   - `classification`: `INCOME` → `DEBT_COLLECTION`
3. Create `LinkedTransaction` linking transaction to entry
4. Update `LinkedEntry`:
   - `pending_amount`: 1500 - 1500 = 0
   - `status`: `PENDING` → `SETTLED`

#### Business Rules
- Can link multiple partial payments
- Total linked amount cannot exceed `pending_amount`
- Status changes:
  - `PENDING` if `pending_amount == total_amount`
  - `PARTIAL` if `0 < pending_amount < total_amount`
  - `SETTLED` if `pending_amount == 0`

---

## Loans & Lending

### US-L1: Lend Money

**As a user**, I want to record that I lent money to someone.

#### API Endpoint
```http
POST /api/transactions/{transaction_id}/mark-loan
Content-Type: application/json

{
  "counterparty_name": "Alice",
  "notes": "Loan for emergency"
}
```

####Prerequisites
- Transaction must exist
- Transaction must be `OUTFLOW`

#### Expected Behavior
1. Update transaction:
   - `classification`: `EXPENSE` → `LEND`
2. Create `LinkedEntry`:
   ```
   {
     "link_type": "LOAN",
     "primary_transaction_id": transaction_id,
     "counterparty_name": "Alice",
     "total_amount": 5000.00,
     "user_amount": null,  // Not used for loans
     "pending_amount": 5000.00,
     "status": "PENDING"
   }
   ```

#### Financial Impact
- **Wallet Balance**: -¥5,000
- **Monthly Expense**: ¥0 (lending is not spending!)
- **Pending Owed**: +¥5,000 (Alice owes you)

---

### US-L2: Receive Loan Repayment

**As a user**, I want to record when someone pays back a loan.

#### API  Endpoint
```http
POST /api/linked-entries/{linked_entry_id}/link
Content-Type: application/json

{
  "transaction_ids": [124, 125]  // Supports partial payments
}
```

#### Prerequisites
Create repayment transaction(s) first, then link them.

#### Expected Behavior
1. Validate all transactions are `INFLOW`
2. Reclassify: `INCOME` → `DEBT_COLLECTION`
3. Update `pending_amount`
4. Update `status` based on remaining amount

#### Example: Partial Repayment
```
Original Loan: ¥5,000

Payment 1: ¥2,000
- pending_amount: 5,000 - 2,000 = 3,000
- status: PARTIAL

Payment 2: ¥3,000
- pending_amount: 3,000 - 3,000 = 0
- status: SETTLED
```

---

## Debts & Borrowing

### US-D1: Borrow Money

**As a user**, I want to record that I borrowed money from someone.

#### API Endpoint
```http
POST /api/transactions/{transaction_id}/mark-debt
Content-Type: application/json

{
  "counterparty_name": "Charlie",
  "notes": "Borrowed for rent"
}
```

#### Prerequisites
- Transaction must exist
- Transaction must be `INFLOW`

#### Expected Behavior
1. Update transaction:
   - `classification`: `INCOME` → `BORROW`
2. Create `LinkedEntry`:
   ```
   {
     "link_type": "DEBT",
     "total_amount": 10000.00,
     "pending_amount": 10000.00,
     "status": "PENDING"
   }
   ```

#### Financial Impact
- **Wallet Balance**: +¥10,000
- **Monthly Income**: ¥0 (borrowing is not earning!)
- **Pending Debt**: +¥10,000 (you owe Charlie)

---

### US-D2: Repay a Debt

**As a user**, I want to record when I pay back borrowed money.

#### API Endpoint
```http
POST /api/linked-entries/{linked_entry_id}/link
Content-Type: application/json

{
  "transaction_ids": [126]
}
```

#### Prerequisites
Create repayment transaction first (OUTFLOW).

#### Expected Behavior
1. Validate transaction is `OUTFLOW`
2. Reclassify: `EXPENSE` → `LOAN_REPAYMENT`
3. Update `pending_amount` and `status`

#### Financial Impact
- **Wallet Balance**: -¥10,000
- **Monthly Expense**: ¥0 (repayment is not spending!)
- **Pending Debt**: -¥10,000

---

## Installment Payments

### US-I1: Create Installment Plan

**As a user**, I want to record a credit card purchase that will be paid in monthly installments.

#### API Endpoint
```http
POST /api/transactions/{transaction_id}/mark-installment
Content-Type: application/json

{
  "counterparty_name": "Apple Store",
  "notes": "iPhone 24 months"
}
```

#### Prerequisites
- Transaction must exist
- Transaction must be `OUTFLOW`
- Wallet must be `CREDIT` type

#### Expected Behavior
1. Update transaction:
   - `direction`: `OUTFLOW` → `RESERVED`
   - `classification`: `EXPENSE` → `INSTALLMENT`
2. Create `LinkedEntry`:
   ```
   {
     "link_type": "INSTALLMENT",
     "total_amount": 24000.00,
     "pending_amount": 24000.00,
     "status": "PENDING"
   }
   ```

#### Financial Impact (¥50,000 credit limit)
- **Wallet Balance**: ¥0 (plan excluded from balance!)
- **Pending Installments**: +¥24,000
- **Available Credit**: 50,000 - 0 - 24,000 = **¥26,000**

**See**: [BALANCE_CALCULATION.md](./BALANCE_CALCULATION.md#installment-flow-complete-example) for complete flow

---

### US-I2: Record Monthly Installment Charge

**As a user**, I want to link the monthly installment charge to the plan.

#### API Endpoint

**Step 1**: Create transaction for monthly charge
```http
POST /api/transactions
{
  "wallet_id": 1,
  "direction": "outflow",
  "amount": 2000.00,
  "classification": "expense",
  "description": "iPhone Monthly Payment 1/24"
}
```

**Step 2**: Link to installment plan
```http
POST /api/linked-entries/{installment_entry_id}/link
{
  "transaction_ids": [transaction_id]
}
```

#### Expected Behavior
1. Validate transaction is `OUTFLOW`
2. Reclassify: `EXPENSE` → `INSTALLMT_CHRGE`
3. Update `LinkedEntry`:
   - `pending_amount`: 24,000 - 2,000 = 22,000
   - `status`: `PARTIAL`
4. Invalidate wallet snapshots

#### Financial Impact
- **Wallet Balance**: ¥0 → **¥2,000** (charge now included!)
- **Pending Installments**: 24,000 → **¥22,000**
- **Available Credit**: Still **¥26,000** (debt moved from reserved to actual)

---

### US-I3:Pay Credit Card Bill

**As a user**, I want to pay off my credit card balance.

#### API Endpoint
```http
POST /api/transactions
{
  "wallet_id": 1,  // Credit card wallet
  "direction": "inflow",
  "amount": 2000.00,
  "classification": "transfer",
  "description": "Pay credit card bill"
}
```

#### Expected Behavior
1. Create transaction
2. Reduce wallet balance

#### Financial Impact (after paying ¥2,000 charge from US-I2)
- **Wallet Balance**: 2,000 - 2,000 = **¥0**
- **Pending Installments**: Still ¥22,000
- **Available Credit**: 50,000 - 0 - 22,000 = **¥28,000** ✅ Credit freed up!

---

## Categories & Budgets

### US-C1: Create Category

**As a user**, I want to organize my expenses into categories.

#### API Endpoint
```http
POST /api/categories
{
  "name": "Food",
  "emoji": "🍔",
  "color": "#FF5733"
}
```

---

### US-C2: Set Monthly Budget

**As a user**, I want to set a spending limit for a category.

#### API Endpoint
```http
POST /api/budgets
{
  "category_id": 5,
  "amount": 10000.00,
  "month": 12,
  "year": 2025
}
```

#### Expected Behavior
- Store budget target
- Used in monthly summaries to show budget vs actual

---

## Reports & Summaries

### US-R1: View Monthly Expense

**As a user**, I want to see how much I spent this month.

#### API Endpoint
```http
GET /api/transactions/monthly-summary?month=2025-12-01
```

#### Response
```json
{
  "month": "2025-12",
  "total_expense": 15000.00,
  "category_breakdown": {
    "Food": 5000.00,
    "Transport": 3000.00,
    "Entertainment": 7000.00
  }
}
```

#### Calculation Logic
```
Monthly Expense = 
  Σ(EXPENSE transactions) + 
  Σ(user_amount for SPLIT_PAYMENT transactions)
```

**Excluded**:
- `LEND` (not spending)
- `LOAN_REPAYMENT` (not new spending)
- `TRANSFER` (moving own money)
- `INSTALLMENT` (placeholder)
- `is_ignored=true`

---

### US-R2: View Net Position

**As a user**, I want to see my overall financial position.

#### API Endpoint
```http
GET /api/wallets/net-position
```

#### Response
```json
{
  "total_assets": 50000.00,
  "total_liabilities": 12000.00,
  "pending_owed_to_user": 5000.00,
  "pending_debt_to_others": 2000.00,
  "net_position": 41000.00
}
```

#### Calculation
```
Net Position = 
  (Assets + Pending Owed) -
  (Liabilities + Pending Debt)

Where:
- Assets = Σ(balance of NORMAL wallets)
- Liabilities = Σ(balance of CREDIT wallets)
- Pending Owed = Σ(pending_amount for SPLIT_PAYMENT + LOAN)
- Pending Debt = Σ(pending_amount for DEBT)
```

**Note**: Installment pending amounts are NOT included (they're reservations against credit limit, not external debt)

---

## Advanced Operations

### US-A1: Merge Transactions

**As a user**, I want to combine multiple transactions into one.

#### API Endpoint
```http
POST /api/transactions/merge
{
  "transaction_ids": [101, 102, 103],
  "date": "2025-12-25",
  "description": "Grocery shopping",
  "category_id": 5
}
```

#### Expected Behavior
1. Validate all transactions:
   - Same wallet
   - Same direction
   - All are `EXPENSE` or `INCOME`
2. Sum amounts
3. Create new transaction with summed amount
4. Delete original transactions

#### Business Rules
- Cannot merge special transactions (`LEND`, `BORROW`, `TRANSFER`, etc.)
- Cannot merge calibration transactions

---

### US-A2: Bulk Import

**As a user**, I want to import multiple transactions at once.

#### API Endpoint
```http
POST /api/transactions/bulk-import
{
  "items": [
    {"date": "2025-12-01", "wallet_id": 1, ...},
    {"from_wallet_id": 1, "to_wallet_id": 2, ...}  // Transfer
  ]
}
```

#### Expected Behavior
- **Atomic**: All items imported or none
- Supports both transactions and transfers
- Returns count of imported items

---

## Error Handling

Common error responses:

### 400 Bad Request
- Invalid data (amount negative, missing required fields)
- Business rule violation (user_amount > total_amount)
- Transaction already linked

### 404 Not Found
- Transaction/wallet/linked entry doesn't exist

### 422 Unprocessable Entity
- Invalid date format
- Invalid enum values

Example error response:
```json
{
  "detail": "user_amount cannot exceed transaction amount"
}
```
