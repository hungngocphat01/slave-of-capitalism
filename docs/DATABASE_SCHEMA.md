# Database Schema

Complete database schema documentation for the Expense Manager application.

## Entity Relationship Diagram

```mermaid
erDiagram
    WALLETS ||--o{ TRANSACTIONS : contains
    WALLETS ||--o{ WALLET_SNAPSHOTS : has
    CATEGORIES ||--o{ TRANSACTIONS : categorizes
    CATEGORIES ||--o{ SUBCATEGORIES : contains
    SUBCATEGORIES ||--o{ TRANSACTIONS : categorizes
    TRANSACTIONS ||--o| TRANSACTIONS : paired_with
    TRANSACTIONS ||--o| LINKED_ENTRIES : primary_for
    TRANSACTIONS ||--o{ LINKED_TRANSACTIONS : linked_in
    LINKED_ENTRIES ||--o{ LINKED_TRANSACTIONS : has
    CATEGORIES ||--o{ BUDGETS : has
    
    WALLETS {
        int id PK
        string name UK
        enum wallet_type "normal|credit"
        decimal credit_limit
        string emoji
        datetime created_at
        datetime updated_at
    }
    
    TRANSACTIONS {
        int id PK
        date date
        time time
        int wallet_id FK
        enum direction "inflow|outflow|reserved"
        decimal amount
        enum classification
        string description
        int category_id FK
        int subcategory_id FK
        int paired_transaction_id FK
        boolean is_ignored
        boolean is_calibration
        datetime created_at
        datetime updated_at
    }
    
    LINKED_ENTRIES {
        int id PK
        enum link_type "split_payment|loan|debt|installment"
        int primary_transaction_id FK_UK
        string counterparty_name
        decimal total_amount
        decimal user_amount
        decimal pending_amount
        enum status "pending|partial|settled"
        string notes
        datetime created_at
        datetime updated_at
    }
    
    LINKED_TRANSACTIONS {
        int id PK
        int linked_entry_id FK
        int transaction_id FK_UK
        datetime created_at
    }
    
    CATEGORIES {
        int id PK
        string name UK
        string emoji
        string color
        boolean is_system
        datetime created_at
        datetime updated_at
    }
    
    SUBCATEGORIES {
        int id PK
        int category_id FK
        string name
        datetime created_at
        datetime updated_at
    }
    
    BUDGETS {
        int id PK
        int category_id FK
        int subcategory_id FK
        decimal amount
        int month
        int year
        datetime created_at
        datetime updated_at
    }
    
    WALLET_SNAPSHOTS {
        int id PK
        int wallet_id FK_UK
        date snapshot_date UK
        decimal balance
        datetime created_at
    }
```

---

## Tables

### `wallets`

Represents sources of funds (cash, bank accounts, credit cards).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK, AUTO | Primary key |
| `name` | VARCHAR(100) | UNIQUE, NOT NULL | Unique wallet name |
| `wallet_type` | ENUM | NOT NULL, DEFAULT 'normal' | `normal` or `credit` |
| `credit_limit` | DECIMAL(12,2) | NOT NULL, DEFAULT 0 | Credit limit for credit wallets |
| `emoji` | VARCHAR(10) | NULL | Optional emoji icon |
| `created_at` | DATETIME | NOT NULL | Creation timestamp |
| `updated_at` | DATETIME | NOT NULL | Last update timestamp |

**Indexes**: `id` (PK), `name` (UNIQUE), `wallet_type`

---

### `transactions`

Core transaction table tracking all money movements.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK, AUTO | Primary key |
| `date` | DATE | NOT NULL | Transaction date |
| `time` | TIME | NULL | Optional transaction time |
| `wallet_id` | INTEGER | FK → wallets.id, NOT NULL | Which wallet |
| `direction` | ENUM | NOT NULL | `inflow`, `outflow`, or `reserved` |
| `amount` | DECIMAL(12,2) | NOT NULL | Always positive |
| `classification` | ENUM | NOT NULL | See [Transaction Classifications](#transaction-classifications) |
| `description` | VARCHAR(500) | NULL | Transaction description |
| `category_id` | INTEGER | FK → categories.id, NULL | Optional category |
| `subcategory_id` | INTEGER | FK → subcategories.id, NULL | Optional subcategory |
| `paired_transaction_id` | INTEGER | FK → transactions.id, NULL | For wallet transfers |
| `is_ignored` | BOOLEAN | NOT NULL, DEFAULT FALSE | Exclude from calculations |
| `is_calibration` | BOOLEAN | NOT NULL, DEFAULT FALSE | Balance calibration transaction |
| `created_at` | DATETIME | NOT NULL | Creation timestamp |
| `updated_at` | DATETIME | NOT NULL | Last update timestamp |

**Indexes**: `id` (PK), `date`, `wallet_id`, `direction`, `classification`, `is_ignored`, `is_calibration`

**Foreign Keys**:
- `wallet_id` → `wallets.id` (CASCADE DELETE)
- `category_id` → `categories.id` (SET NULL)
- `subcategory_id` → `subcategories.id` (SET NULL)
- `paired_transaction_id` → `transactions.id` (SET NULL)

---

### `linked_entries`

Tracks split payments, loans, debts, and installments.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK, AUTO | Primary key |
| `link_type` | ENUM | NOT NULL | `split_payment`, `loan`, `debt`, `installment` |
| `primary_transaction_id` | INTEGER | FK → transactions.id, UNIQUE, NOT NULL | The original transaction |
| `counterparty_name` | VARCHAR(200) | NOT NULL | Who owes/is owed |
| `total_amount` | DECIMAL(12,2) | NOT NULL | Total amount |
| `user_amount` | DECIMAL(12,2) | NULL | User's share (split payments only) |
| `pending_amount` | DECIMAL(12,2) | NOT NULL | Amount still pending |
| `status` | ENUM | NOT NULL, DEFAULT 'pending' | `pending`, `partial`, `settled` |
| `notes` | VARCHAR(1000) | NULL | Optional notes |
| `created_at` | DATETIME | NOT NULL | Creation timestamp |
| `updated_at` | DATETIME | NOT NULL | Last update timestamp |

**Indexes**: `id` (PK), `link_type`, `primary_transaction_id` (UNIQUE), `counterparty_name`, `status`

**Foreign Keys**:
- `primary_transaction_id` → `transactions.id` (CASCADE DELETE)

---

### `linked_transactions`

Junction table linking transactions to linked entries (for payments/reimbursements).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK, AUTO | Primary key |
| `linked_entry_id` | INTEGER | FK → linked_entries.id, NOT NULL | Which entry |
| `transaction_id` | INTEGER | FK → transactions.id, UNIQUE, NOT NULL | Which transaction |
| `created_at` | DATETIME | NOT NULL | Creation timestamp |

**Indexes**: `id` (PK), `linked_entry_id`, `transaction_id` (UNIQUE)

**Foreign Keys**:
- `linked_entry_id` → `linked_entries.id` (CASCADE DELETE)
- `transaction_id` → `transactions.id` (CASCADE DELETE)

**Virtual Column**:
- `amount`: Derived from `transactions.amount`

---

### `categories`

Top-level spending categories.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK, AUTO | Primary key |
| `name` | VARCHAR(100) | UNIQUE, NOT NULL | Category name |
| `emoji` | VARCHAR(10) | NULL | Optional emoji |
| `color` | VARCHAR(7) | NULL | Hex color code |
| `is_system` | BOOLEAN | NOT NULL, DEFAULT FALSE | System category (cannot delete) |
| `created_at` | DATETIME | NOT NULL | Creation timestamp |
| `updated_at` | DATETIME | NOT NULL | Last update timestamp |

**Indexes**: `id` (PK), `name` (UNIQUE)

---

### `subcategories`

Sub-categories under categories.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK, AUTO | Primary key |
| `category_id` | INTEGER | FK → categories.id, NOT NULL | Parent category |
| `name` | VARCHAR(100) | NOT NULL | Subcategory name |
| `created_at` | DATETIME | NOT NULL | Creation timestamp |
| `updated_at` | DATETIME | NOT NULL | Last update timestamp |

**Indexes**: `id` (PK), `category_id`

**Unique Constraint**: (`category_id`, `name`)

---

### `budgets`

Monthly budget targets for categories/subcategories.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK, AUTO | Primary key |
| `category_id` | INTEGER | FK → categories.id, NOT NULL | Category to budget |
| `subcategory_id` | INTEGER | FK → subcategories.id, NULL | Optional subcategory |
| `amount` | DECIMAL(12,2) | NOT NULL | Budget amount |
| `month` | INTEGER | NOT NULL | Month (1-12) |
| `year` | INTEGER | NOT NULL | Year |
| `created_at` | DATETIME | NOT NULL | Creation timestamp |
| `updated_at` | DATETIME | NOT NULL | Last update timestamp |

**Indexes**: `id` (PK), `category_id`, `subcategory_id`

**Unique Constraint**: (`category_id`, `subcategory_id`, `month`, `year`)

---

### `wallet_snapshots`

Cached wallet balances for performance optimization.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | INTEGER | PK, AUTO | Primary key |
| `wallet_id` | INTEGER | FK → wallets.id, NOT NULL | Which wallet |
| `snapshot_date` | DATE | NOT NULL | Date of snapshot |
| `balance` | DECIMAL(12,2) | NOT NULL | Calculated balance |
| `created_at` | DATETIME | NOT NULL | Creation timestamp |

**Indexes**: `id` (PK), `wallet_id`, `snapshot_date`

**Unique Constraint**: (`wallet_id`, `snapshot_date`)

---

## Enumerations

### Transaction Direction

```python
class TransactionDirection(Enum):
    INFLOW = "inflow"      # Money enters wallet
    OUTFLOW = "outflow"    # Money leaves wallet
    RESERVED = "reserved"  # Future liability (installment plans)
```

### Transaction Classifications

```python
class TransactionClassification(Enum):
    EXPENSE = "expense"                    # Regular spending
    INCOME = "income"                      # Regular income
    LEND = "lend"                         # Lent money to someone
    BORROW = "borrow"                     # Borrowed money from someone
    DEBT_COLLECTION = "debt_collection"    # Receiving money back
    LOAN_REPAYMENT = "loan_repayment"      # Paying back borrowed money
    SPLIT_PAYMENT = "split_payment"        # Paid for others
    TRANSFER = "transfer"                  # Between own wallets
    INSTALLMENT = "installment"            # Installment plan placeholder
    INSTALLMT_CHRGE = "installmt_chrge"    # Actual installment charge
```

### Wallet Type

```python
class WalletType(Enum):
    NORMAL = "normal"  # Cash, bank account, e-wallet
    CREDIT = "credit"  # Credit card with limit
```

### Link Type

```python
class LinkType(Enum):
    SPLIT_PAYMENT = "split_payment"  # Pay on behalf, expect reimbursement
    LOAN = "loan"                    # Lent money, expect payback
    DEBT = "debt"                    # Borrowed money, must repay
    INSTALLMENT = "installment"      # Credit card installment plan
```

### Link Status

```python
class LinkStatus(Enum):
    PENDING = "pending"    # Waiting for linked transaction(s)
    PARTIAL = "partial"    # Partially settled
    SETTLED = "settled"    # Fully settled
```

---

## Key Relationships

### One-to-One
- `transactions.paired_transaction_id` → `transactions.id` (wallet transfers)
- `linked_entries.primary_transaction_id` → `transactions.id` (unique)
- `linked_transactions.transaction_id` → `transactions.id` (unique)

### One-to-Many
- `wallets` → `transactions`
- `categories` → `transactions`
- `categories` → `subcategories`
- `subcategories` → `transactions`
- `linked_entries` → `linked_transactions`

### Cascade Rules
- Delete wallet → Delete all transactions, snapshots
- Delete category → Set category_id to NULL in transactions
- Delete linked_entry → Delete all linked_transactions
- Delete transaction (primary) → Delete linked_entry → Delete linked_transactions
