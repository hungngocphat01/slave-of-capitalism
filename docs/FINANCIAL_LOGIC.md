
# Financial Logic - Quick Reference

> **Note**: This document provides a quick reference for financial calculations. For comprehensive details, see:
> - [BALANCE_CALCULATION.md](./BALANCE_CALCULATION.md) - Complete balance calculation logic
> - [USER_STORIES.md](./USER_STORIES.md) - All user stories and API endpoints
> - [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) - Database schema and relationships

This document explains the core financial calculations used in the Expense Manager, specifically focusing on Wallet Balances and the Installment/Credit logic.

## 1. Terminology

*   **Wallet Balance**: The amount of money currently in the wallet (or owed, for credit cards).
*   **Credit Limit**: The maximum allowed debt for a credit wallet.
*   **Available Credit**: The remaining purchasable amount (`Limit - Debt - Reservations`).
*   **Installment Plan (`INSTALLMENT`)**: A "virtual" transaction representing the total commitment of an installment purchase (e.g., 24M for a laptop). This reserves credit but does not count as "current debt" in the balance.
*   **Installment Charge (`INSTALLMT_CHRGE`)**: The actual monthly transaction (e.g., 2M) that appears on the statement. This counts as "current debt".

## 2. Wallet Balance Calculation

**File:** `backend/app/services/wallet_service.py` → `calculate_wallet_balance`

 The wallet balance is calculated by summing all `INFLOW` and `OUTFLOW` transactions, with specific filtering.

### Formula
For **Normal Wallets**:
$$ \text{Balance} = \text{Start Balance} + (\sum \text{Inflows} - \sum \text{Outflows}) $$

For **Credit Wallets**:
$$ \text{Balance} = \text{Start Balance} + (\sum \text{Outflows} - \sum \text{Inflows}) $$
*(Positive balance on a Credit Wallet means you owe money)*

### Transaction Filtering
*   **Ignored Transactions**: `is_ignored=True` transactions are usually excluded from *reports* but **INCLUDED** in balance calculations (e.g., transfers).
*   **Installment Plans**: `TransactionClassification.INSTALLMENT` transactions are **EXCLUDED** from the balance calculation.
    *   *Reason*: The plan is a future commitment. Including it would immediately max out the "Owed" balance, whereas in reality, you only owe the monthly payments as they come due.
*   **Installment Charges**: `TransactionClassification.INSTALLMT_CHRGE` transactions mean "realized debt" and are **INCLUDED**.

## 3. Available Credit Calculation

**File:** `backend/app/services/wallet_service.py` → `calculate_available_credit`

This metric determines how much you can spend on your credit card. It must account for both the money you *currently* owe and the money you have *promised* to pay (reserved).

### Formula
$$ \text{Available} = \text{Credit Limit} - \text{Actual Balance} - \text{Pending Installments} $$

### Components
1.  **Credit Limit**: The fixed limit of the card (e.g., 50M).
2.  **Actual Balance**: The result of `calculate_wallet_balance`.
    *   Includes normal expenses.
    *   Includes realized `INSTALLMT_CHRGE` (e.g., the 2M charged this month).
    *   *Excludes* the total `INSTALLMENT` plan.
3.  **Pending Installments**:
    *   Calculated by summing the `pending_amount` of all Linked Entries of type `INSTALLMENT` that are `PENDING` or `PARTIAL`.
    *   Represents the "Reserved" portion of the limit that hasn't been charged yet.

## 4. Complete Installment Flow Example

**Scenario**: Buy a 24M laptop on installment. Limit 50M.

### Step 0: Initial State
- Balance: ¥0
- Available: ¥50M

### Step 1: Day 0 (Purchase/Plan Creation)
*   Transaction created: 24M `INSTALLMENT` with direction `RESERVED`.
*   Linked Entry created: Pending Amount = 24M.
*   **Balance**: 0 (Excludes plan).
*   **Available**: $50M - 0 - 24M = 26M$.
*   *Result*: Limit is correctly reserved.

### Step 2: Month 1 (First Charge)
*   Transaction created: 2M `EXPENSE` (outflow).
*   **User Action**: Link this 2M transaction to the Installment Plan.
*   **System Action**:
    *   Transaction becomes `INSTALLMT_CHRGE`.
    *   Linked Entry `pending_amount` reduces: $24M - 2M = 22M$.
*   **Balance**: 2M (Now includes the 2M charge).
*   **Available**: $50M - 2M (\text{Balance}) - 22M (\text{Pending}) = 26M$.
*   *Result*: Available credit remains constant (as expected). The debt just moved from "Reserved" to "Actual".

### Step 3: Month 1 (Payment)
*   User pays 2M to the card (Transfer Inflow).
*   **Balance**: $2M (\text{Out}) - 2M (\text{In}) = 0$.
*   **Available**: $50M - 0 - 22M = 28M$.
*   *Result*: Paying off the current bill frees up that portion of the limit. The future 22M remains reserved.

**See [BALANCE_CALCULATION.md](./BALANCE_CALCULATION.md#installment-flow-complete-example) for more details.**

## 5. Net Position

**Net Position** is calculated as:
$$ \text{Net} = (\text{Assets} + \text{Pending Owed to User}) - (\text{Liabilities} + \text{Pending Debt}) $$

*   **Assets**: Sum of balances of Normal Wallets.
*   **Liabilities**: Sum of balances of Credit Wallets.
*   **Pending Owed**: Money people owe you (Split Payments, Loans).
*   **Pending Debt**: Money you owe others (Debts).

*Note: Installment Plans (the 22M reserved) do NOT count as "Pending Debt" in this specific calculation, as they are internal reservations against a credit limit, not a debt to a 3rd party person. However, the Realized Balance (2M) *does* count as Liability.*
