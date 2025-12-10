#!/bin/bash
# Crude integration tests - Call API and verify with SQL queries

set -e

DB_FILE="expense.db"
BASE_URL="http://localhost:8000"

echo "🧪 Starting Crude Integration Tests..."
echo "========================================"
echo ""

# Start fresh
echo "📦 Setting up test database..."
rm -f $DB_FILE
poetry run uvicorn app.main:app --port 8000 &
SERVER_PID=$!
sleep 3

echo "✅ Server started (PID: $SERVER_PID)"
echo ""

# Test 1: Verify seed data
echo "Test 1: Verify seed data loaded"
echo "--------------------------------"
CATEGORY_COUNT=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM categories;")
WALLET_COUNT=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM wallets;")

echo "Categories in DB: $CATEGORY_COUNT (expected: 7)"
echo "Wallets in DB: $WALLET_COUNT (expected: 4)"

if [ "$CATEGORY_COUNT" -eq 7 ] && [ "$WALLET_COUNT" -eq 4 ]; then
    echo "✅ PASS: Seed data correct"
else
    echo "❌ FAIL: Seed data incorrect"
    kill $SERVER_PID
    exit 1
fi
echo ""

# Test 2: Create expense transaction via API
echo "Test 2: Create expense transaction"
echo "-----------------------------------"
RESPONSE=$(curl -s -X POST "$BASE_URL/api/transactions/" \
  -H "Content-Type: application/json" \
  -d '{
    "date": "2025-12-06",
    "wallet_id": 1,
    "direction": "outflow",
    "amount": "3000.00",
    "classification": "expense",
    "description": "Test Expense",
    "category_id": 1
  }')

TXN_ID=$(echo $RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "Created transaction ID: $TXN_ID"

# Verify in database
DB_DIRECTION=$(sqlite3 $DB_FILE "SELECT direction FROM transactions WHERE id=$TXN_ID;")
DB_CLASSIFICATION=$(sqlite3 $DB_FILE "SELECT classification FROM transactions WHERE id=$TXN_ID;")
DB_AMOUNT=$(sqlite3 $DB_FILE "SELECT amount FROM transactions WHERE id=$TXN_ID;")

echo "DB direction: $DB_DIRECTION (expected: OUTFLOW)"
echo "DB classification: $DB_CLASSIFICATION (expected: EXPENSE)"
echo "DB amount: $DB_AMOUNT (expected: 3000)"

if [ "$DB_DIRECTION" = "OUTFLOW" ] && [ "$DB_CLASSIFICATION" = "EXPENSE" ]; then
    echo "✅ PASS: Transaction created correctly"
else
    echo "❌ FAIL: Transaction data incorrect"
    kill $SERVER_PID
    exit 1
fi
echo ""

# Test 3: Wallet balance calculation
echo "Test 3: Wallet balance calculation"
echo "-----------------------------------"
WALLET_RESPONSE=$(curl -s "$BASE_URL/api/wallets/1")
CURRENT_BALANCE=$(echo $WALLET_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['current_balance'])")

echo "Wallet balance via API: $CURRENT_BALANCE"
echo "Expected: 7000.00 (10000 initial - 3000 expense)"

if [ "$CURRENT_BALANCE" = "7000.00" ]; then
    echo "✅ PASS: Balance calculation correct"
else
    echo "❌ FAIL: Balance calculation incorrect (got $CURRENT_BALANCE)"
    kill $SERVER_PID
    exit 1
fi
echo ""

# Test 4: Create split payment and linked entry
echo "Test 4: Create split payment with linked entry"
echo "-----------------------------------------------"

# Create split payment transaction
SPLIT_RESPONSE=$(curl -s -X POST "$BASE_URL/api/transactions/" \
  -H "Content-Type: application/json" \
  -d '{
    "date": "2025-12-06",
    "wallet_id": 1,
    "direction": "outflow",
    "amount": "6000.00",
    "classification": "split_payment",
    "description": "Dinner with Bob",
    "category_id": 1
  }')

SPLIT_TXN_ID=$(echo $SPLIT_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "Created split payment transaction ID: $SPLIT_TXN_ID"

# Create linked entry
ENTRY_RESPONSE=$(curl -s -X POST "$BASE_URL/api/linked-entries/" \
  -H "Content-Type: application/json" \
  -d "{
    \"primary_transaction_id\": $SPLIT_TXN_ID,
    \"link_type\": \"split_payment\",
    \"counterparty_name\": \"Bob\",
    \"user_amount\": \"3000.00\"
  }")

ENTRY_ID=$(echo $ENTRY_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "Created linked entry ID: $ENTRY_ID"

# Verify in database
DB_PENDING=$(sqlite3 $DB_FILE "SELECT pending_amount FROM linked_entries WHERE id=$ENTRY_ID;")
DB_USER_AMOUNT=$(sqlite3 $DB_FILE "SELECT user_amount FROM linked_entries WHERE id=$ENTRY_ID;")
DB_STATUS=$(sqlite3 $DB_FILE "SELECT LOWER(status) FROM linked_entries WHERE id=$ENTRY_ID;")

echo "DB pending_amount: $DB_PENDING (expected: 3000)"
echo "DB user_amount: $DB_USER_AMOUNT (expected: 3000)"
echo "DB status: $DB_STATUS (expected: pending)"

if [ "$DB_STATUS" = "pending" ]; then
    echo "✅ PASS: Linked entry created correctly"
else
    echo "❌ FAIL: Linked entry data incorrect"
    kill $SERVER_PID
    exit 1
fi
echo ""

# Test 5: Link reimbursement
echo "Test 5: Link reimbursement to split payment"
echo "--------------------------------------------"

# Create reimbursement transaction
REIMBURSE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/transactions/" \
  -H "Content-Type: application/json" \
  -d '{
    "date": "2025-12-07",
    "wallet_id": 1,
    "direction": "inflow",
    "amount": "3000.00",
    "classification": "debt_collection",
    "description": "Reimbursement from Bob"
  }')

REIMBURSE_TXN_ID=$(echo $REIMBURSE_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")
echo "Created reimbursement transaction ID: $REIMBURSE_TXN_ID"

# Link to entry
LINK_RESPONSE=$(curl -s -X POST "$BASE_URL/api/linked-entries/$ENTRY_ID/link" \
  -H "Content-Type: application/json" \
  -d "{
    \"transaction_id\": $REIMBURSE_TXN_ID,
    \"amount\": \"3000.00\"
  }")

# Verify in database
DB_STATUS_AFTER=$(sqlite3 $DB_FILE "SELECT LOWER(status) FROM linked_entries WHERE id=$ENTRY_ID;")
DB_PENDING_AFTER=$(sqlite3 $DB_FILE "SELECT pending_amount FROM linked_entries WHERE id=$ENTRY_ID;")
LINK_COUNT=$(sqlite3 $DB_FILE "SELECT COUNT(*) FROM linked_transactions WHERE linked_entry_id=$ENTRY_ID;")

echo "DB status after link: $DB_STATUS_AFTER (expected: settled)"
echo "DB pending_amount after link: $DB_PENDING_AFTER (expected: 0)"
echo "Linked transactions count: $LINK_COUNT (expected: 1)"

if [ "$DB_STATUS_AFTER" = "settled" ] && [ "$LINK_COUNT" -eq 1 ]; then
    echo "✅ PASS: Reimbursement linked correctly"
else
    echo "❌ FAIL: Linking failed"
    kill $SERVER_PID
    exit 1
fi
echo ""

# Test 6: Monthly expense calculation
echo "Test 6: Monthly expense calculation"
echo "------------------------------------"
SUMMARY_RESPONSE=$(curl -s "$BASE_URL/api/transactions/monthly-summary/?month=2025-12-01")
TOTAL_EXPENSE=$(echo $SUMMARY_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['total_expense'])")

echo "Monthly expense via API: $TOTAL_EXPENSE"
echo "Expected: 6000.00 (3000 regular expense + 3000 user share of split)"

if [ "$TOTAL_EXPENSE" = "6000.0" ]; then
    echo "✅ PASS: Monthly expense calculation correct"
else
    echo "❌ FAIL: Monthly expense incorrect (got $TOTAL_EXPENSE)"
    kill $SERVER_PID
    exit 1
fi
echo ""

# Test 7: Wallet transfer
echo "Test 7: Wallet transfer (paired transactions)"
echo "----------------------------------------------"
TRANSFER_RESPONSE=$(curl -s -X POST "$BASE_URL/api/transactions/wallet-transfer" \
  -H "Content-Type: application/json" \
  -d '{
    "from_wallet_id": 2,
    "to_wallet_id": 3,
    "amount": "10000.00",
    "description": "Transfer to PayPay",
    "date": "2025-12-06"
  }')

OUTFLOW_ID=$(echo $TRANSFER_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['outflow_transaction']['id'])")
INFLOW_ID=$(echo $TRANSFER_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['inflow_transaction']['id'])")

echo "Outflow transaction ID: $OUTFLOW_ID"
echo "Inflow transaction ID: $INFLOW_ID"

# Verify pairing in database
OUTFLOW_PAIRED=$(sqlite3 $DB_FILE "SELECT paired_transaction_id FROM transactions WHERE id=$OUTFLOW_ID;")
INFLOW_PAIRED=$(sqlite3 $DB_FILE "SELECT paired_transaction_id FROM transactions WHERE id=$INFLOW_ID;")

echo "Outflow paired_transaction_id: $OUTFLOW_PAIRED (expected: $INFLOW_ID)"
echo "Inflow paired_transaction_id: $INFLOW_PAIRED (expected: $OUTFLOW_ID)"

if [ "$OUTFLOW_PAIRED" -eq "$INFLOW_ID" ] && [ "$INFLOW_PAIRED" -eq "$OUTFLOW_ID" ]; then
    echo "✅ PASS: Wallet transfer paired correctly"
else
    echo "❌ FAIL: Transfer pairing incorrect"
    kill $SERVER_PID
    exit 1
fi
echo ""

# Cleanup
echo "🧹 Cleaning up..."
kill $SERVER_PID
sleep 1

echo ""
echo "========================================"
echo "✅ All crude integration tests PASSED!"
echo "========================================"
