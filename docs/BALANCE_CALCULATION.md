# Balance Calculation Deep Dive

This document explains in detail how wallet balances are calculated, with special emphasis on credit wallets, installments, and the distinction between actual balance and available credit.

---

## Normal Wallet Balance

### Formula

For normal wallets (cash, bank accounts, e-wallets):

```
Balance = INITIAL_BALANCE + Σ(INFLOW) - Σ(OUTFLOW)
```

Where:
- **INITIAL_BALANCE**: Stored as a special ignored INFLOW transaction with description "INITIAL BALANCE"
- **INFLOW**: All transactions with `direction=INFLOW` (excluding ignored and installment plans)
- **OUTFLOW**: All transactions with `direction=OUTFLOW` (excluding ignored and installment plans)

### Implementation

**File**: `backend/app/services/wallet_service.py` → `calculate_wallet_balance()`

```python
def calculate_wallet_balance(db: Session, wallet_id: int) -> Decimal:
    wallet = db.query(Wallet).filter(Wallet.id == wallet_id).first()
    
    if wallet.wallet_type == WalletType.NORMAL:
        # Sum all inflows
        inflows = db.query(func.sum(Transaction.amount)).filter(
            Transaction.wallet_id == wallet_id,
            Transaction.direction == TransactionDirection.INFLOW,
            # INSTALLMENT plans don't apply to normal wallets
        ).scalar() or Decimal("0.00")
        
        # Sum all outflows
        outflows = db.query(func.sum(Transaction.amount)).filter(
            Transaction.wallet_id == wallet_id,
            Transaction.direction == TransactionDirection.OUTFLOW,
            Transaction.classification != TransactionClassification.INSTALLMENT
        ).scalar() or Decimal("0.00")
        
        return inflows - outflows
```

### Examples

#### Example 1: Simple Cash Wallet

| Transaction | Direction | Amount | Classification | Balance |
|-------------|-----------|--------|----------------|---------|
| Initial Balance | INFLOW | ¥10,000 | INCOME | ¥10,000 |
| Salary | INFLOW | ¥5,000 | INCOME | ¥15,000 |
| Groceries | OUTFLOW | ¥3,000 | EXPENSE | ¥12,000 |

**Calculation**: `10,000 + 5,000 - 3,000 = ¥12,000`

---

## Credit Wallet Balance

### Formula

For credit wallets (credit cards):

```
Balance = Σ(OUTFLOW) - Σ(INFLOW)
```

**Note**: Positive balance = you owe money

Where:
- **OUTFLOW** (charges): Includes `EXPENSE` and `INSTALLMT_CHRGE`
- **OUTFLOW** (excluded): Excludes `INSTALLMENT` plans (they are reserved, not actual debt)
- **INFLOW** (payments): Transactions paying off the card

### Implementation

```python
if wallet.wallet_type == WalletType.CREDIT:
    # Outflows (charges) - but EXCLUDE installment plans
    outflows = db.query(func.sum(Transaction.amount)).filter(
        Transaction.wallet_id == wallet_id,
        Transaction.direction == TransactionDirection.OUTFLOW,
        Transaction.classification != TransactionClassification.INSTALLMENT
    ).scalar() or Decimal("0.00")
    
    # Inflows (payments)
    inflows = db.query(func.sum(Transaction.amount)).filter(
        Transaction.wallet_id == wallet_id,
        Transaction.direction == TransactionDirection.INFLOW
    ).scalar() or Decimal("0.00")
    
    return outflows - inflows  # Positive = debt
```

### Key Insight: Why Exclude INSTALLMENT?

**Problem**: If we include the full `INSTALLMENT` plan amount in the balance:
- User buys ¥24,000 laptop on 12-month installment
- Balance would immediately show **¥24,000** owed
- But in reality, user only owes the monthly payments as they occur

**Solution**: 
- `INSTALLMENT` transactions use `direction=RESERVED` and are **excluded** from balance
- Only `INSTALLMT_CHRGE` transactions (the actual monthly charges) affect the balance

---

## Available Credit Calculation

### Formula

For credit wallets:

```
Available Credit = Credit Limit - Actual Balance - Pending Installments
```

Where:
- **Credit Limit**: The card's maximum limit (e.g., ¥50,000)
- **Actual Balance**: Current debt calculated above (includes `INSTALLMT_CHRGE`, excludes `INSTALLMENT`)
- **Pending Installments**: Sum of `pending_amount` from all installment LinkedEntries

### Implementation

**File**: `backend/app/services/wallet_service.py` → `calculate_available_credit()`

```python
def calculate_available_credit(db: Session, wallet_id: int) -> Decimal:
    wallet = db.query(Wallet).filter(Wallet.id == wallet_id).first()
    
    if wallet.wallet_type != WalletType.CREDIT:
        return Decimal("0.00")
    
    # Get actual balance
    actual_balance = calculate_wallet_balance(db, wallet_id)
    
    # Get pending installments (reserved amount)
    pending_installments = linked_entry_service.calculate_pending_installments(
        db, wallet_id=wallet_id
    )
    
    return wallet.credit_limit - actual_balance - pending_installments
```

### Why This Matters

Available credit must account for **both**:
1. **Money you currently owe** (actual balance)
2. **Money you've committed to pay** (pending installments)

This prevents overspending beyond your credit limit.

---

## Installment Flow: Complete Example

**Scenario**: Buy a ¥24,000 laptop on 12-month installment. Credit card has ¥50,000 limit.

### Step 0: Initial State

| Metric | Value | Calculation |
|--------|-------|-------------|
| Balance | ¥0 | No transactions |
| Pending Installments | ¥0 | No installment plans |
| Available Credit | ¥50,000 | `50,000 - 0 - 0` |

---

### Step 1: Create Installment Plan (Day 0)

**Action**: User buys laptop, creates installment plan

**Transaction Created**:
```
{
  "date": "2025-01-01",
  "wallet_id": 1,
  "direction": "RESERVED",  // Not OUTFLOW!
  "amount": 24000,
  "classification": "INSTALLMENT",
  "description": "Laptop (12 months)"
}
```

**LinkedEntry Created**:
```
{
  "link_type": "INSTALLMENT",
  "primary_transaction_id": 1,
  "counterparty_name": "Apple Store",
  "total_amount": 24000,
  "pending_amount": 24000,
  "status": "PENDING"
}
```

**Result**:

| Metric | Value | Calculation |
|--------|-------|-------------|
| Balance | ¥0 | INSTALLMENT excluded |
| Pending Installments | ¥24,000 | From LinkedEntry |
| Available Credit | **¥26,000** | `50,000 - 0 - 24,000` |

✅ **Limit reserved**, but no actual debt yet.

---

### Step 2: First Monthly Charge (Month 1)

**Action**: Credit card company charges first installment

**Transaction Created**:
```
{
  "date": "2025-02-01",
  "wallet_id": 1,
  "direction": "OUTFLOW",  // Real charge!
  "amount": 2000,
  "classification": "EXPENSE",  // Initially EXPENSE
  "description": "Laptop Installment 1/12"
}
```

**Link Transaction to Plan**:
```
POST /api/linked-entries/1/link
{
  "transaction_ids": [2]
}
```

**System Actions**:
1. Transaction reclassified: `EXPENSE` → `INSTALLMT_CHRGE`
2. LinkedEntry updated: `pending_amount = 24,000 - 2,000 = 22,000`
3. Snapshots invalidated

**Result**:

| Metric | Value | Calculation |
|--------|-------|-------------|
| Balance | **¥2,000** | Now includes the ¥2,000 charge |
| Pending Installments | **¥22,000** | 24,000 - 2,000 |
| Available Credit | **¥26,000** | `50,000 - 2,000 - 22,000` |

✅ **Available credit unchanged** (debt moved from "reserved" to "actual")

---

### Step 3: Pay Card Bill (Month 1)

**Action**: User pays ¥2,000 to credit card

**Transaction Created**:
```
{
  "date": "2025-02-15",
  "wallet_id": 1,
  "direction": "INFLOW",  // Payment
  "amount": 2000,
  "classification": "TRANSFER",
  "description": "Pay credit card"
}
```

**Result**:

| Metric | Value | Calculation |
|--------|-------|-------------|
| Balance | **¥0** | 2,000 (charge) - 2,000 (payment) |
| Pending Installments | ¥22,000 | Unchanged |
| Available Credit | **¥28,000** | `50,000 - 0 - 22,000` |

✅ **Credit freed up** by paying current balance

---

## Split Payments & Balance

Split payments affect monthly expense calculations but have nuanced balance impact.

### Scenario: Split Dinner

**Transaction**:
```
{
  "direction": "OUTFLOW",
  "amount": 3000,
  "classification": "SPLIT_PAYMENT"
}
```

**LinkedEntry**:
```
{
  "link_type": "SPLIT_PAYMENT",
  "total_amount": 3000,
  "user_amount": 1500,  // Your share
  "pending_amount": 1500  // Bob owes you
}
```

### Balance Impact

**Wallet Balance**: Reduces by full ¥3,000 (you paid it)

**Monthly Expense**: Only ¥1,500 counts (your share)

**Net Position**: Improves by ¥1,500 when Bob pays you back
- Before reimbursement: Assets - 3,000, Owed to you + 1,500 = Net -1,500
- After reimbursement: Assets - 3,000 + 1,500 = Net -1,500 (same, as expected)

---

## Loans & Balance

### Scenario: Lend Money

**Transaction**:
```
{
  "direction": "OUTFLOW",
  "amount": 5000,
  "classification": "LEND"
}
```

### Balance Impact

**Wallet Balance**: Reduces by ¥5,000

**Monthly Expense**: **¥0** (lending is not spending!)

**Net Position**: Unchanged
- Assets: -5,000
- Owed to you: +5,000
- Net: 0

---

## Transaction Filtering Rules

### What's INCLUDED in Balance Calculation

✅ Regular `EXPENSE` and `INCOME`  
✅ `INSTALLMT_CHRGE` (realized installment charges)  
✅ `TRANSFER`, `LEND`, `BORROW`  
✅ `DEBT_COLLECTION`, `LOAN_REPAYMENT`  
✅ `SPLIT_PAYMENT`  
✅ `is_ignored=True` transactions (special handling for transfers)

### What's EXCLUDED from Balance Calculation

❌ `INSTALLMENT` plans (`direction=RESERVED`)  
❌ Deleted transactions (obviously)

### What's EXCLUDED from Monthly Expense

❌ `LEND` (not an expense)  
❌ `LOAN_REPAYMENT` (paying back debt, not new spending)  
❌ `TRANSFER` (moving your own money)  
❌ `INSTALLMENT` (placeholder, not actual spending)  
❌ `is_ignored=True` transactions

---

## Calibration Transactions

### Purpose

When wallet balance drifts from reality (e.g., forgot to record a transaction), create a calibration transaction to fix it.

### Characteristics

- `is_calibration=True`
- Direction/amount chosen to correct the balance
- Can be "resolved" later if you remember what caused the drift

### Balance Impact

**Included** in balance calculation (they exist to fix the balance)

---

## Performance Optimization: Snapshots

### Problem

Calculating balance for historical dates requires scanning all transactions from the beginning of time.

### Solution: `wallet_snapshots` Table

- Store pre-calculated balance for specific dates
- Query: `SELECT balance FROM wallet_snapshots WHERE wallet_id=? AND snapshot_date=?`
- Invalidation: Delete snapshots >= changed transaction date

### When Snapshots Are Invalidated

1. Transaction created/updated/deleted
2. Transaction classification changed
3. Linked entry linked/unlinked

**Automatic Rebuild**: Next query for that date recalculates and caches

---

## Summary

### Key Formulas

| Wallet Type | Balance Formula |
|-------------|-----------------|
| Normal | `INFLOW - OUTFLOW` |
| Credit | `OUTFLOW - INFLOW` (positive = debt) |

| Credit Wallet | Available Credit Formula |
|---------------|--------------------------|
| Available | `Limit - Balance - Pending Installments` |

### Critical Distinctions

1. **INSTALLMENT vs INSTALLMT_CHRGE**:
   - `INSTALLMENT`: Reserved commitment (excluded from balance)
   - `INSTALLMT_CHRGE`: Actual charge (included in balance)

2. **Balance vs Monthly Expense**:
   - Balance: ALL money movements
   - Monthly Expense: Only `EXPENSE` and user's share of `SPLIT_PAYMENT`

3. **LEND/BORROW vs EXPENSE/INCOME**:
   - `LEND`/`LOAN_REPAYMENT`: Not expenses (asset reallocation)
   - `BORROW`/`DEBT_COLLECTION`: Not income (liability management)
