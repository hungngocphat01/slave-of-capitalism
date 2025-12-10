# Expense Manager Frontend - UI/UX Design Plan

## Screen Structure

### 1. **Entry Screen** (Main Screen - Transaction List)
Based on the uploaded transaction list image.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│ [Month Selector: ◀ December 2025 ▶]  [+ Add Transaction]       │
├─────────────────────────────────────────────────────────────────┤
│ Date  │ Description │ Category │ Amount │ Wallet │ Balance      │
├─────────────────────────────────────────────────────────────────┤
│ 12/06 │ Dinner      │ 🍔 Food  │ ¥3,000 │ Cash   │ ¥7,000      │
│ 12/07 │ Coffee      │ ☕ Food  │ ¥500   │ PayPay │ ¥4,500      │
│ ...                                                              │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- **Month selector** at top - only shows current month's transactions
- **Table columns:**
  - Date (sortable)
  - Time (optional, shown if exists)
  - Description (editable inline)
  - Category (dropdown with emoji)
  - Subcategory (if applicable)
  - Amount (editable inline)
  - Wallet (shows wallet name)
  - Running balance (calculated)
  - Visual indicators:
    - 🔴 OUTFLOW (red/orange)
    - 🟢 INFLOW (green)
    - 🔵 TRANSFER (blue)
    - 💰 SPLIT (yellow highlight)
    - 💸 LOAN (purple)
    - 🏦 DEBT (pink)

**Interactions:**
- **Left-click row**: Select (highlight)
- **Double-click cell**: Edit inline (description, amount, category)
- **Right-click row**: Context menu (see below)
- **Drag to reorder**: Change date/order
- **Keyboard shortcuts**:
  - `Cmd+N`: New transaction
  - `Cmd+D`: Delete selected
  - `Enter`: Edit selected
  - `Esc`: Cancel edit

**Context Menu** (Right-click on row):
```
┌─────────────────────────────────┐
│ ✏️  Edit                         │
│ 🗑️  Delete                       │
├─────────────────────────────────┤
│ 💰 Mark as Split Payment        │ (only for OUTFLOW EXPENSE)
│ 💸 Mark as Loan                 │ (only for OUTFLOW LEND)
│ 🏦 Mark as Debt                 │ (only for INFLOW BORROW)
├─────────────────────────────────┤
│ 🔗 Link to Pending Entry        │ (only for INFLOW DEBT_COLLECTION or OUTFLOW LOAN_REPAYMENT)
│ 👁️  See All Reimbursements      │ (only if has linked entry)
├─────────────────────────────────┤
│ 🔄 Reclassify                   │
│ 📋 Duplicate                    │
└─────────────────────────────────┘
```

**Context Menu Logic:**
- **Mark as Split Payment**: Shows modal to enter:
  - Counterparty name
  - Your share amount
  - Notes
- **Mark as Loan**: Shows modal to enter:
  - Counterparty name
  - Notes
- **Link to Pending Entry**: Shows modal with list of pending entries:
  ```
  ┌──────────────────────────────────────────┐
  │ Link to Pending Entry                    │
  ├──────────────────────────────────────────┤
  │ ○ Bob owes ¥1,500 (Dinner 12/06)        │
  │ ○ Alice owes ¥5,000 (Loan 12/01)        │
  │                                          │
  │ Amount to link: [¥______]               │
  │                                          │
  │         [Cancel]  [Link]                 │
  └──────────────────────────────────────────┘
  ```
- **See All Reimbursements**: Shows modal with linked transactions:
  ```
  ┌──────────────────────────────────────────┐
  │ Reimbursements for "Dinner with Bob"     │
  ├──────────────────────────────────────────┤
  │ Total: ¥3,000                            │
  │ Your share: ¥1,500                       │
  │ Bob owes: ¥1,500                         │
  │                                          │
  │ Payments received:                       │
  │ ✅ 12/07 - ¥1,500 (Settled)             │
  │                                          │
  │              [Close]                     │
  └──────────────────────────────────────────┘
  ```

---

### 2. **Summary Screen** (Budget vs Actual)
Based on the Excel sheet image.

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│ [Month Selector: ◀ August 2025 ▶]                              │
├─────────────────────────────────────────────────────────────────┤
│ Category        │Budget│Actual│  %  │  7  │ 12  │ 19  │ 26  │ 31│
├─────────────────────────────────────────────────────────────────┤
│ 🍔 Đồ ăn đi chợ │  15  │ 13.5 │ 90% │     │ 5.2 │ 2.2 │ 3.8 │2.2│
│ ☕ Cà phê       │   0  │  0.1 │  0% │ 0.1 │     │     │     │   │
│ 🍽️ Ăn ngoài     │  10  │ 26.9 │269% │ 7.9 │ 2.7 │ 4.9 │ 6.1 │5.3│
│ ...                                                             │
├─────────────────────────────────────────────────────────────────┤
│ SUM             │      │108.8 │     │27.2 │13.7 │15.9 │36.5 │15.6│
│ SUM TOTAL       │      │108.8 │     │     │     │     │     │   │
├─────────────────────────────────────────────────────────────────┤
│ Thực chi        │      │108.8 │     │83.9 │     │     │     │   │
│ Chưa quản lý    │      │      │     │     │     │     │     │   │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- **Period boundaries**: Configurable (default: 7, 14, 21, 31)
- **Color coding**:
  - Green: Under budget (<100%)
  - Yellow: Near budget (90-110%)
  - Red: Over budget (>110%)
- **Click cell**: Drill down to transactions in that period
- **Budget editing**: Click budget cell to edit
- **Auto-calculation**: All totals calculated from transactions

---

### 3. **Wallets Screen**

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│ Wallets                                    [+ Add Wallet]       │
├─────────────────────────────────────────────────────────────────┤
│ ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐ │
│ │ 💵 Cash          │  │ 🏦 Bank Account  │  │ 📱 PayPay      │ │
│ │ ¥7,000           │  │ ¥40,000          │  │ ¥4,500         │ │
│ │                  │  │                  │  │                │ │
│ │ [Transfer]       │  │ [Transfer]       │  │ [Transfer]     │ │
│ └──────────────────┘  └──────────────────┘  └────────────────┘ │
│                                                                 │
│ ┌──────────────────┐                                           │
│ │ 💳 Visa Card     │  Credit Card                              │
│ │ ¥30,000 owed     │  Available: ¥70,000 / ¥100,000           │
│ │                  │                                           │
│ │ [Pay]            │                                           │
│ └──────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘
```

**Features:**
- **Card-based layout** for each wallet
- **Transfer button**: Opens transfer modal
- **Visual distinction** for credit cards
- **Click card**: See wallet details and transactions

---

### 4. **Pending Screen** (Owed/Debt Overview)

**Layout:**
```
┌─────────────────────────────────────────────────────────────────┐
│ Pending Reimbursements                                          │
├─────────────────────────────────────────────────────────────────┤
│ People Owe You: ¥6,500                                         │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ Bob                                          ¥1,500 pending  ││
│ │ 💰 Dinner split (12/06)                                     ││
│ │ [Remind] [Mark Paid]                                        ││
│ └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ Alice                                        ¥5,000 pending  ││
│ │ 💸 Loan (12/01)                                             ││
│ │ Partial payments: ¥2,000 received                           ││
│ │ [Remind] [Record Payment]                                   ││
│ └─────────────────────────────────────────────────────────────┘│
├─────────────────────────────────────────────────────────────────┤
│ You Owe: ¥10,000                                               │
│                                                                 │
│ ┌─────────────────────────────────────────────────────────────┐│
│ │ Charlie                                     ¥10,000 pending  ││
│ │ 🏦 Borrowed (12/03)                                         ││
│ │ [Record Repayment]                                          ││
│ └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Design System (Apple-inspired)

### Colors
```css
--background: #ffffff
--surface: #f5f5f7
--surface-elevated: #ffffff
--border: #d2d2d7
--text-primary: #1d1d1f
--text-secondary: #86868b
--accent: #007aff
--success: #34c759
--warning: #ff9500
--error: #ff3b30
--inflow: #34c759
--outflow: #ff3b30
--transfer: #007aff
--split: #ff9500
--loan: #af52de
--debt: #ff2d55
```

### Typography
```css
--font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif
--font-size-xs: 11px
--font-size-sm: 13px
--font-size-base: 15px
--font-size-lg: 17px
--font-size-xl: 22px
--font-size-2xl: 28px
```

### Spacing
```css
--space-1: 4px
--space-2: 8px
--space-3: 12px
--space-4: 16px
--space-6: 24px
--space-8: 32px
```

### Shadows
```css
--shadow-sm: 0 1px 3px rgba(0,0,0,0.04)
--shadow-md: 0 4px 6px rgba(0,0,0,0.07)
--shadow-lg: 0 10px 15px rgba(0,0,0,0.1)
```

---

## Navigation

**Sidebar** (Left side, always visible):
```
┌─────────────┐
│ 📊 Entry    │ ← Main screen
│ 📈 Summary  │
│ 💰 Wallets  │
│ ⏳ Pending  │
│             │
│ ⚙️ Settings │
└─────────────┘
```

---

## Implementation Plan

### Phase 1: Setup & Core
1. ✅ Initialize Tauri + Svelte project
2. ✅ Setup design system (CSS variables)
3. ✅ Create layout with sidebar navigation
4. ✅ Setup API client for backend

### Phase 2: Entry Screen (Priority 1)
5. ✅ Transaction table component
6. ✅ Month selector
7. ✅ Add transaction modal
8. ✅ Inline editing
9. ✅ Context menu
10. ✅ Mark as split/loan/debt modals
11. ✅ Link to pending entry modal

### Phase 3: Summary Screen (Priority 2)
12. ✅ Budget table component
13. ✅ Period boundary configuration
14. ✅ Drill-down to transactions
15. ✅ Budget editing

### Phase 4: Wallets & Pending (Priority 3)
16. ✅ Wallet cards
17. ✅ Transfer modal
18. ✅ Pending entries list
19. ✅ Record payment modal

### Phase 5: Polish
20. ✅ Keyboard shortcuts
21. ✅ Loading states
22. ✅ Error handling
23. ✅ Animations & transitions

---

## Questions Before Implementation

1. **Entry screen sorting**: Default sort by date descending (newest first)?

2. **Inline editing**: Which fields should be editable inline?
   - Description ✓
   - Amount ✓
   - Category ✓
   - Date?

3. **Visual indicators**: Should transactions with linked entries show a badge/icon?

4. **Filters**: Should there be filters at top (by category, wallet, classification)?

5. **Search**: Should there be a search bar to find transactions?

6. **Keyboard navigation**: Arrow keys to navigate table, Enter to edit?

Let me know if this plan looks good, and I'll start implementing!
