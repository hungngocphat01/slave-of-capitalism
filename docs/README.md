# Expense Manager - Application Documentation

> **Single Source of Truth** for all application logic, database models, and API endpoints.

## Table of Contents

1. [Overview](#overview)
2. [Database Schema](./DATABASE_SCHEMA.md)
3. [Financial Logic](./FINANCIAL_LOGIC.md)
4. [User Stories & API Endpoints](./USER_STORIES.md)
5. [Balance Calculation Deep Dive](./BALANCE_CALCULATION.md)

---

## Overview

The Expense Manager is a local-only expense tracking application with support for:
- **Multiple Wallets**: Normal (cash/bank) and Credit card wallets
- **Transactions**: Income, expenses, transfers between wallets
- **Split Payments**: Track money owed when you pay for others
- **Loans & Debts**: Track money you lent or borrowed
- **Installment Payments**: Credit card installment plans with proper reservation logic
- **Categories & Budgets**: Organize and track spending

### Architecture

```
┌─────────────────┐
│   Frontend      │  SvelteKit + Tauri (Desktop App)
│   (Svelte)      │
└────────┬────────┘
         │ HTTP/REST
┌────────▼────────┐
│   Backend       │  FastAPI + SQLAlchemy
│   (Python)      │
└────────┬────────┘
         │
┌────────▼────────┐
│   Database      │  SQLite (Local)
│   (SQLite)      │
└─────────────────┘
```

### Key Principles

1. **Separation of Concerns**: Direction (INFLOW/OUTFLOW) is separate from Classification (EXPENSE/INCOME/LEND/etc)
2. **Linked Entries**: Special transactions (splits, loans, debts, installments) are tracked via LinkedEntry relationships
3. **Balance Accuracy**: Installment plans reserve credit without affecting current balance
4. **Atomic Operations**: All multi-transaction operations are atomic (transfers, bulk imports, etc.)

---

## Quick Reference

### Transaction Direction
- `INFLOW`: Money enters wallet
- `OUTFLOW`: Money leaves wallet  
- `RESERVED`: Future commitment (installment plans)

### Transaction Classification
- `EXPENSE`: Regular spending
- `INCOME`: Regular income
- `LEND`: Money lent to someone
- `BORROW`: Money borrowed from someone
- `DEBT_COLLECTION`: Receiving money back (repayment/reimbursement)
- `LOAN_REPAYMENT`: Paying back borrowed money
- `SPLIT_PAYMENT`: Paid for others, expect reimbursement
- `TRANSFER`: Between own wallets
- `INSTALLMENT`: Installment plan (placeholder)
- `INSTALLMT_CHRGE`: Actual installment charge

### Link Types
- `SPLIT_PAYMENT`: Track reimbursements when you paid for others
- `LOAN`: Track money you lent
- `DEBT`: Track money you borrowed
- `INSTALLMENT`: Track credit card installment plans

---

## Documentation Files

| File | Description |
|------|-------------|
| [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) | Complete database schema with all tables, columns, and relationships |
| [FINANCIAL_LOGIC.md](./FINANCIAL_LOGIC.md) | Core financial calculations and formulas |
| [USER_STORIES.md](./USER_STORIES.md) | User stories mapped to API endpoints with expected behavior |
| [BALANCE_CALCULATION.md](./BALANCE_CALCULATION.md) | Deep dive into balance calculation logic |

---

## Development

See [../backend/README.md](../backend/README.md) for development setup.

## Testing

See [../backend/tests/](../backend/tests/) for comprehensive test suite.
