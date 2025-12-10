# Expense Manager

A modern, automated finance tracking application designed to replace manual spreadsheet management. Built to solve the pain of manually classifying transactions and resolving balance discrepancies.

> **Note**: This entire project—frontend, backend, and logic—was "Vibecoded" 100% by Antigravity. Without such a powerful AI agent, building a tool of this complexity would not have been possible for me alone.

## 🚀 Motivation

Managing personal finances shouldn't be a chore. Previously, I tracked everything in Excel, which became tiresome and error-prone:
- **Manual input**: Opening PayPay (a major e-wallet app in Japan), classifying each transaction, and typing it into Excel was a daily burden.
- **The "mystery" gap**: Resolving differences between the actual wallet balance and the spreadsheet number was frustrating.
- **Lost data**: Sometimes the wallet balances doesn't match up, making me wondering, *"Where did this money actually go?"*

This application was built to automate the tedious parts, ensure (hopefully) 100% accuracy with wallet balances, and provide accurate insights into spending habits.

## ✨ Key Features

### 📥 1-Click PayPay Import
Forget manual entry. The app features a powerful import wizard for PayPay CSV exports:
- **Intelligent parsing**: Automatically extracts date, amount, and description.
- **Rule-based categorization**: Define simple grammar rules (e.g., `time < 9:00, amount > 100, description *= "Uber" -> Morning transport`) to automatically categorize transactions.

### 💸 Advanced tracking

#### Split payments
Easily handle shared expenses with friends or family:
- **Custom shares**: Specify exactly how much of a transaction was your personal expense.
- **Reimbursement tracking**: Link incoming repayments to the original expense to zero out the balance.
- **Debt/Loan management**: Clearly track who owes you money and who you owe.

#### Wallet calibration
Solving the "mystery balance" problem:
- **Auto-adjustment**: If your real-world wallet balance doesn't match the app, simply input the correct amount.
- **Resolution**: The app creates a calibration transaction to account for the difference. Later, if you remember the missing expense, you can "resolve" the calibration, and the app will automatically adjust the records.

## 🛠️ Tech Stack

This application is built with a modern, high-performance stack:

- **Frontend**: [SvelteKit](https://kit.svelte.dev/) (TypeScript) + [Tauri v2](https://tauri.app/) for a lightweight, native desktop experience.
- **Backend**: [FastAPI](https://fastapi.tiangolo.com/) (Python) for robust API handling and business logic.
- **Database**: [SQLite](https://www.sqlite.org/) for local, self-contained data storage.
- **Package manager**: `npm` (frontend) and `poetry` (backend).

## 📦 Installation & running

### Prerequisites
- Node.js & npm
- Python 3.11+ & Poetry
- Rust (for Tauri)

### Development

1. **Backend Setup**
   ```bash
   cd backend
   poetry install
   # Run the server individually (dev context)
   poetry run uvicorn app.main:app --reload --port 8000
   ```

2. **Frontend Setup**
   ```bash
   cd frontend
   npm install
   # Run the desktop app
   npm run tauri dev
   ```

### Production

Simply run:

```
make install
make build
```

On OSX, run `make open` to start the compiled app bundle.

---

*Expense Manager - Take control of your finances, effortlessly.*
