"""Tests for wallet balance snapshots and optimization logic."""
import pytest
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy.orm import Session # type: ignore

from app.models.wallet import Wallet, WalletType
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.snapshot import WalletSnapshot
from app.services import wallet_service, snapshot_service, transaction_service
from app.schemas.transaction import TransactionCreate, TransactionUpdate


def test_create_snapshot(test_db: Session, sample_wallet: Wallet):
    """Test creating a snapshot."""
    snapshot_date = date.today() - timedelta(days=1)
    balance = Decimal("15000.00")
    
    snapshot = snapshot_service.create_snapshot(
        test_db, sample_wallet.id, snapshot_date, balance
    )
    
    assert snapshot.id is not None
    assert snapshot.wallet_id == sample_wallet.id
    assert snapshot.balance == balance
    assert snapshot.snapshot_date == snapshot_date


def test_get_latest_snapshot(test_db: Session, sample_wallet: Wallet):
    """Test retrieving the latest snapshot."""
    # Create two snapshots
    d1 = date.today() - timedelta(days=10)
    d2 = date.today() - timedelta(days=5)
    
    s1 = snapshot_service.create_snapshot(test_db, sample_wallet.id, d1, Decimal("100.00"))
    s2 = snapshot_service.create_snapshot(test_db, sample_wallet.id, d2, Decimal("200.00"))
    
    # Get latest
    latest = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    assert latest.id == s2.id
    assert latest.balance == Decimal("200.00")
    
    # Get latest before date
    before = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id, before_date=d1)
    assert before.id == s1.id


def test_balance_calculation_with_snapshot(test_db: Session, sample_wallet: Wallet):
    """Test balance calculation uses snapshot correctly."""
    # Initial Balance: 10,000
    
    # 1. Create a snapshot 10 days ago. Balance: 15,000
    snapshot_date = date.today() - timedelta(days=10)
    snapshot_service.create_snapshot(test_db, sample_wallet.id, snapshot_date, Decimal("15000.00"))
    
    # 2. Add transaction 5 days ago (should be counted)
    # INFLOW: +1000
    t1 = Transaction(
        date=date.today() - timedelta(days=5),
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("1000.00"),
        classification=TransactionClassification.INCOME
    )
    test_db.add(t1)
    
    # 3. Add transaction 15 days ago (should be IGNORED because it's before snapshot)
    # OUTFLOW: -5000
    t2 = Transaction(
        date=date.today() - timedelta(days=15),
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("5000.00"),
        classification=TransactionClassification.EXPENSE
    )
    test_db.add(t2)
    test_db.commit()
    
    # Expected: 15,000 (Snapshot) + 1,000 (New) = 16,000
    # The old transaction (-5000) is ignored because snapshot supersedes it.
    
    balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
    assert balance == Decimal("16000.00")


def test_snapshot_invalidation_on_insert(test_db: Session, sample_wallet: Wallet):
    """Test that inserting an old transaction invalidates future snapshots."""
    # 1. Create snapshot for Yesterday.
    snapshot_date = date.today() - timedelta(days=1)
    snapshot_service.create_snapshot(test_db, sample_wallet.id, snapshot_date, Decimal("20000.00"))
    
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id) is not None
    
    # 2. Insert transaction for 10 days ago (older than snapshot)
    req = TransactionCreate(
        date=date.today() - timedelta(days=10),
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100.00"),
        classification=TransactionClassification.EXPENSE,
        description="Old txn"
    )
    
    transaction_service.create_transaction(test_db, req)
    
    # 3. Verify snapshot is gone
    latest = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    assert latest is None # Should be deleted


def test_safety_mechanism_large_rebuild(test_db: Session, sample_wallet: Wallet):
    """Test that large cache rebuilds raise error if not confirmed."""
    from app.constants import LARGE_CACHE_REBUILD_DAYS
    today = date.today()
    old_date = today - timedelta(days=LARGE_CACHE_REBUILD_DAYS + 20) # > Threshold trigger
    
    # 1. Simulate large history (mocking query result for speed)
    # We mock snapshot_service.check_rebuild_impact to return 11000
    
    # Monkeypatching for this test
    original_check = snapshot_service.check_rebuild_impact
    snapshot_service.check_rebuild_impact = lambda db, w, d: 11000
    
    try:
        req = TransactionCreate(
            date=old_date,
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100.00"),
            classification=TransactionClassification.EXPENSE,
            description="Ancient txn",
            allow_large_cache_rebuild=False
        )
        
        with pytest.raises(ValueError) as excinfo:
            transaction_service.create_transaction(test_db, req)
        
        assert "affects 11000 historical transactions" in str(excinfo.value)
        
        # 2. Retry with confirmation
        req.allow_large_cache_rebuild = True
        txn = transaction_service.create_transaction(test_db, req)
        assert txn.id is not None
        
    finally:
        # Restore mock
        snapshot_service.check_rebuild_impact = original_check


def test_lazy_snapshot_creation(test_db: Session, sample_wallet: Wallet):
    """Test that calculating balance triggers lazy snapshot creation."""
    # 1. Setup transactions
    from app.constants import LAZY_SNAPSHOT_INTERVAL_DAYS
    today = date.today()
    yesterday = today - timedelta(days=1)
    past_date = today - timedelta(days=LAZY_SNAPSHOT_INTERVAL_DAYS + 10)
    
    # Old txn (> interval ago): +1000
    t1 = Transaction(
        date=past_date,
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("1000.00"),
        classification=TransactionClassification.INCOME
    )
    test_db.add(t1)
    
    # Today txn: -200
    t2 = Transaction(
        date=today,
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("200.00"),
        classification=TransactionClassification.EXPENSE
    )
    test_db.add(t2)
    test_db.commit()
    
    # Initial Balance: 10,000
    # Expected Balance Now: 10000 + 1000 - 200 = 10800
    # Expected Snapshot Balance (Yesterday): 10000 + 1000 = 11000
    
    # 2. Calculate Balance
    balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
    assert balance == Decimal("10800.00")
    
    # 3. Verify Snapshot Creation
    # Should have created a snapshot for yesterday
    latest = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    
    assert latest is not None
    assert latest.snapshot_date == yesterday
    assert latest.balance == Decimal("11000.00")
    
    # 4. Modify Today's txn (Snapshot should remain valid as it is for yesterday)
    # Actually, modifying Today doesn't affect Yesterday's balance, so snapshot stays.
    # But if we modify OLD txn, snapshot should die.
    
    req = TransactionUpdate(
        amount=Decimal("2000.00")
    )
    transaction_service.update_transaction(test_db, t1.id, req)
    
    # Check snapshot invalidated
    latest_after = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    assert latest_after is None



def test_credit_wallet_balance_and_snapshots(test_db: Session, sample_credit_wallet: Wallet):
    """Test balance calculation and snapshots for Credit Wallets."""
    # Logic for Credit Wallet: Balance = Outflows - Inflows (Positive Balance = Debt)
    
    # 1. Add transactions
    # Charge: 5000 (OUTFLOW)
    t1 = Transaction(
        date=date.today() - timedelta(days=20),
        wallet_id=sample_credit_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("5000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Charge 1"
    )
    test_db.add(t1)
    
    # Payment: 2000 (INFLOW)
    t2 = Transaction(
        date=date.today() - timedelta(days=15),
        wallet_id=sample_credit_wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("2000.00"),
        classification=TransactionClassification.INCOME, # or TRANSFER
        description="Payment 1"
    )
    test_db.add(t2)
    test_db.commit()
    
    # Check Balance: 5000 - 2000 = 3000 (Owed)
    balance = wallet_service.calculate_wallet_balance(test_db, sample_credit_wallet.id)
    assert balance == Decimal("3000.00")
    
    # 2. Create Snapshot (for 10 days ago)
    # At 10 days ago, both transactions existed. So balance was 3000.
    snapshot_date = date.today() - timedelta(days=10)
    snapshot_service.create_snapshot(test_db, sample_credit_wallet.id, snapshot_date, Decimal("3000.00"))
    
    # 3. Add new transaction (Today)
    # Charge: 1000 (OUTFLOW)
    t3 = Transaction(
        date=date.today(),
        wallet_id=sample_credit_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("1000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Charge 2"
    )
    test_db.add(t3)
    test_db.commit()
    
    # Check Balance: Snapshot(3000) + New_Outflow(1000) = 4000
    balance_new = wallet_service.calculate_wallet_balance(test_db, sample_credit_wallet.id)
    assert balance_new == Decimal("4000.00")
    
    # 4. Verify Lazy Snapshot Creation (if we query again later?)
    # ... Skipping for brevity, logic is shared with normal wallet
    
    # 5. Invalidation
    # Modify old transaction (t1) -> Should invalidate snapshot
    req = TransactionUpdate(amount=Decimal("6000.00"))
    transaction_service.update_transaction(test_db, t1.id, req)
    
    # Verify snapshot gone
    latest = snapshot_service.get_latest_snapshot(test_db, sample_credit_wallet.id)
    assert latest is None
    
    # Verify Balance Recalculated correctly from scratch
    # 6000 (Old Charge) - 2000 (Payment) + 1000 (New Charge) = 5000
    balance_recalc = wallet_service.calculate_wallet_balance(test_db, sample_credit_wallet.id)
    assert balance_recalc == Decimal("5000.00")

from datetime import date, timedelta
from decimal import Decimal
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models.wallet import Wallet, WalletType
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.services import wallet_service, snapshot_service, transaction_service
from app.schemas.transaction import TransactionCreate

def test_verify_lazy_rebuild_with_today_transactions(test_db: Session, sample_wallet: Wallet):
    """
    Scenario:
    1. Wallet exists, no recent snapshot (older than 7 days or none).
    2. Add several transactions for TODAY.
    3. Trigger balance calculation (which triggers cache rebuild/snapshot creation).
    4. Verify correctness by comparing:
       - Ground Truth: Full sum of all transactions.
       - Service Result: Returned balance.
       - Manual verification: New Snapshot + Today's delta.
    """
    
    # 1. Setup: Create transactions AND an old snapshot
    from app.constants import LAZY_SNAPSHOT_INTERVAL_DAYS
    today = date.today()
    old_snapshot_date = today - timedelta(days=LAZY_SNAPSHOT_INTERVAL_DAYS + 20) # Older than threshold
    
    # A. Initial Balance 10,000
    
    # B. Add OLD transactions (20 days ago)
    # +5000 Income
    # Initial (10,000) + Old (5,000) = 15,000 (Matches our snapshot below)
    t1 = Transaction(
        date=old_snapshot_date,
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("5000.00"),
        classification=TransactionClassification.INCOME,
        description="Old Income"
    )
    test_db.add(t1)
    test_db.commit()
    
    # B. Create Snapshot for 20 days ago
    # Snapshot Balance = 15,000 (Consistent with Initial 10k + Old 5k)
    snapshot_service.create_snapshot(test_db, sample_wallet.id, old_snapshot_date, Decimal("15000.00"))
    
    # Verify we start with this old snapshot
    latest = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    assert latest.snapshot_date == old_snapshot_date
    assert latest.balance == Decimal("15000.00")
    
    # C. Add Intermediate Transactions (Between Old Snapshot and Today)
    # 10 days ago: -1000 Expense
    transaction_service.create_transaction(
        test_db,
        TransactionCreate(
            date=today - timedelta(days=10), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
            amount=Decimal("1000.00"), classification=TransactionClassification.EXPENSE, description="Intermediate Expense"
        )
    )
    
    # D. Add transactions for TODAY (The user action)
    # -100 Lunch
    transaction_service.create_transaction(
        test_db, 
        TransactionCreate(
            date=today, wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100.00"), classification=TransactionClassification.EXPENSE, description="Lunch"
        )
    )
    # -50 Coffee
    transaction_service.create_transaction(
        test_db, 
        TransactionCreate(
            date=today, wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
            amount=Decimal("50.00"), classification=TransactionClassification.EXPENSE, description="Coffee"
        )
    )
    # +200 Refund
    transaction_service.create_transaction(
        test_db, 
        TransactionCreate(
            date=today, wallet_id=sample_wallet.id, direction=TransactionDirection.INFLOW,
            amount=Decimal("200.00"), classification=TransactionClassification.INCOME, description="Refund"
        )
    )
    
    # 2. Calculate GROUND TRUTH
    # User Request: "calculated manually by summing all existing transactions in the database"
    
    total_inflow = test_db.query(func.sum(Transaction.amount)).filter(
        Transaction.wallet_id == sample_wallet.id,
        Transaction.direction == TransactionDirection.INFLOW
    ).scalar() or Decimal("0.00")
    
    total_outflow = test_db.query(func.sum(Transaction.amount)).filter(
        Transaction.wallet_id == sample_wallet.id,
        Transaction.direction == TransactionDirection.OUTFLOW
    ).scalar() or Decimal("0.00")
    
    # Ground Truth = Inflows - Outflows
    # (Note: Initial balance was created as an INFLOW transaction in the fixture)
    ground_truth_balance = total_inflow - total_outflow
    
    # We still expect it to be 14050.00 based on our setup, but now it's dynamic
    assert ground_truth_balance == Decimal("14050.00"), "Ground truth calculation sanity check failed"
    
    # 3. Trigger Service Calculation (Should trigger Lazy Rebuild because snapshot is old)
    service_balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
    
    # 4. Assertions
    
    # Comparison 1: Service vs Ground Truth
    assert service_balance == ground_truth_balance, \
        f"Service balance {service_balance} != Ground Truth {ground_truth_balance}"
        
    # Check if a NEW snapshot was created
    yesterday = today - timedelta(days=1)
    new_snapshot = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    
    assert new_snapshot.snapshot_date == yesterday, "Should have created a new snapshot for Yesterday"
    assert new_snapshot.id != latest.id, "Should be a new snapshot ID"
    
    # Verify New Snapshot Balance
    # Should be: Old_Snapshot(15000) - Intermediate(1000) = 14000
    # (Today's transactions are excluded from yesterday's snapshot)
    assert new_snapshot.balance == Decimal("14000.00"), \
        f"New Snapshot Balance {new_snapshot.balance} != Expected 14000.00"
        
    # Comparison 2: Manual Check (New Snapshot + Today)
    # 14000 + (200 - 100 - 50) = 14050
    manual_calc = new_snapshot.balance + Decimal("50.00")
    assert manual_calc == service_balance


# merged tests from test_balance_edge_cases.py

def test_future_transactions_exclusion(test_db: Session, sample_wallet: Wallet):
    """Test that future transactions are excluded from current balance."""
    # 1. Initial Balance: 10,000
    
    # 2. Add Future Transaction (Tomorrow)
    # OUTFLOW: -1000
    future_date = date.today() + timedelta(days=1)
    t1 = Transaction(
        date=future_date,
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("1000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Future Bill",
        is_ignored=False
    )
    test_db.add(t1)
    test_db.commit()
    
    # 3. Check Balance
    # Should still be 10,000 (Initial). Future txn ignored.
    balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
    assert balance == Decimal("10000.00")


def test_ignored_transactions_inclusion(test_db: Session, sample_wallet: Wallet):
    """Test that ignored transactions ARE included in balance (User Spec)."""
    # 1. Initial Balance: 10,000
    
    # 2. Add Ignored Transaction (Today)
    # OUTFLOW: -2000
    t1 = Transaction(
        date=date.today(),
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("2000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Hidden Expense",
        is_ignored=True
    )
    test_db.add(t1)
    test_db.commit()
    
    # 3. Check Balance
    # Should be 8,000. Ignored txn counted.
    balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
    assert balance == Decimal("8000.00")


def test_date_change_across_snapshot_boundary(test_db: Session, sample_wallet: Wallet):
    """Test moving a transaction across snapshot boundary triggers invalidation."""
    # Setup dates
    today = date.today()
    snapshot_date = today - timedelta(days=10)
    before_snapshot = snapshot_date - timedelta(days=5) # T-15
    after_snapshot = snapshot_date + timedelta(days=5)  # T-5
    
    # 1. Create Snapshot at T-10 (Balance 15,000)
    snapshot_service.create_snapshot(test_db, sample_wallet.id, snapshot_date, Decimal("15000.00"))
    
    # 2. Create Transaction
    txn = transaction_service.create_transaction(
        test_db,
        TransactionCreate(
            date=after_snapshot,
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("1000.00"),
            classification=TransactionClassification.INCOME,
            description="Movable Income"
        )
    )
    
    # Current Balance: Using snapshot(15k) + txn(1k) = 16k
    assert wallet_service.calculate_wallet_balance(test_db, sample_wallet.id) == Decimal("16000.00")
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id) is not None
    
    # 3. Move Transaction to T-15 (Before snapshot)
    # This should INVALIDATE the snapshot because the snapshot "assumed" this transaction didn't exist then.
    transaction_service.update_transaction(
        test_db, txn.id, TransactionUpdate(date=before_snapshot)
    )
    
    # 4. Verify Snapshot Invalidation
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id) is None
    
    # 5. Verify Correct Balance
    # Recalculated from scratch:
    # Initial(10k) + Txn(1k) = 11k
    # (Note: Snapshot was 15k, but that was artificial. Real history is 10k + 1k)
    assert wallet_service.calculate_wallet_balance(test_db, sample_wallet.id) == Decimal("11000.00")


def test_bulk_insert_invalidation(test_db: Session, sample_wallet: Wallet):
    """Test bulk validation (simulating sequential inserts)."""
    # 1. Create Snapshot T-5
    snapshot_date = date.today() - timedelta(days=5)
    snapshot_service.create_snapshot(test_db, sample_wallet.id, snapshot_date, Decimal("10000.00"))
    
    # 2. Insert transaction older than snapshot (T-10)
    txn_old = TransactionCreate(
        date=date.today() - timedelta(days=10),
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100.00"),
        classification=TransactionClassification.EXPENSE,
        description="Old Bulk"
    )
    transaction_service.create_transaction(test_db, txn_old)
    
    # 3. Verify Invalidation directly
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id) is None


def test_transaction_deletion_invalidation(test_db: Session, sample_wallet: Wallet):
    """Test deleting transaction invalidates snapshot."""
    # 1. Transaction at T-10
    txn_old = transaction_service.create_transaction(
        test_db,
        TransactionCreate(
            date=date.today() - timedelta(days=10),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100.00"),
            classification=TransactionClassification.EXPENSE,
            description="To Delete"
        )
    )
    
    # 2. Create Snapshot at T-5
    snapshot_date = date.today() - timedelta(days=5)
    snapshot_service.create_snapshot(test_db, sample_wallet.id, snapshot_date, Decimal("9900.00"))
    
    # 3. Delete transaction
    transaction_service.delete_transaction(test_db, txn_old.id)
    
    # 4. Verify Invalidation
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id) is None
    

def test_complex_sequential_invalidation(test_db: Session, sample_wallet: Wallet):
    """
    Test complex chain of invalidations with sequential inserts.
    Scenario:
    - Today: 2025-12-08
    - Snapshots: Nov 23 (S1), Nov 28 (S2), Dec 03 (S3)
    - 1. Insert T1 at Nov 26 -> Invalidates S2, S3. Keeps S1.
    - 2. Balance Check -> Creates Lazy Snapshot at Dec 07 (Yesterday).
    - 3. Insert T2 at Nov 21 -> Invalidates S1 and the new Lazy Snapshot.
    """
    # Dates
    from app.constants import LAZY_SNAPSHOT_INTERVAL_DAYS
    today = date(2025, 12, 8) # Fixed by freezegun
    
    # We need S1 to be older than LAZY_SNAPSHOT_INTERVAL_DAYS (90) from today
    # So we shift everything back by ~100 days
    base_shift = timedelta(days=100)
    
    s1_date = date(2025, 11, 23) - base_shift
    s2_date = date(2025, 11, 28) - base_shift
    s3_date = date(2025, 12, 3) - base_shift
    
    t1_date = date(2025, 11, 26) - base_shift
    t2_date = date(2025, 11, 21) - base_shift
    
    # 0. Setup Snapshots
    # Arbitrary balances
    snapshot_service.create_snapshot(test_db, sample_wallet.id, s1_date, Decimal("5000.00"))
    snapshot_service.create_snapshot(test_db, sample_wallet.id, s2_date, Decimal("10000.00"))
    snapshot_service.create_snapshot(test_db, sample_wallet.id, s3_date, Decimal("15000.00"))
    
    # Verify setup
    # Note: get_latest_snapshot returns the LATEST <= date.
    # So if we query exactly `before_date=s1_date`, we get S1.
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id, s1_date).snapshot_date == s1_date
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id, s2_date).snapshot_date == s2_date
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id, s3_date).snapshot_date == s3_date
    
    # 1. Insert T1 at Nov 26
    # Should invalidate S2 (Nov 28) and S3 (Dec 03) because they are >= Nov 26
    # Should keep S1 (Nov 23)
    t1 = transaction_service.create_transaction(
        test_db,
        TransactionCreate(
            date=t1_date,
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100.00"),
            classification=TransactionClassification.EXPENSE,
            description="T1"
        )
    )
    
    # Verify Invalidation 1
    assert snapshot_service.get_latest_snapshot(test_db, sample_wallet.id, s1_date) is not None # S1 Kept
    
    # We check if S2 and S3 are gone.
    # If S2 is gone, get_latest_snapshot(s2_date) should return S1 (the previous closest).
    s2_query = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id, s2_date)
    assert s2_query.snapshot_date == s1_date # Fallback to S1
    
    s3_query = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id, s3_date)
    assert s3_query.snapshot_date == s1_date # Fallback to S1
    
    
    # 2. Balance Check -> Creation of Lazy Snapshot
    # Since latest snapshot (S1: Nov 23) is older than 7 days from Today (Dec 08),
    # calculate_wallet_balance should create a new snapshot for Yesterday (Dec 07).
    wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
    
    yesterday = today - timedelta(days=1) # Dec 07
    lazy_snapshot = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    
    assert lazy_snapshot.snapshot_date == yesterday
    
    # 3. Insert T2 at Nov 21
    # Should invalidate S1 (Nov 23) AND the new Lazy Snapshot (Dec 07)
    # Because Nov 21 <= Nov 23 <= Dec 07
    t2 = transaction_service.create_transaction(
        test_db,
        TransactionCreate(
            date=t2_date,
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("200.00"),
            classification=TransactionClassification.EXPENSE,
            description="T2"
        )
    )
    
    # Verify Invalidation 2
    # All snapshots should be gone.
    final_latest = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    assert final_latest is None # Complete wipeout

    # 4. Final Balance Check (User Question)
    # With no snapshots, it should recalculate everything from scratch.
    # Total History:
    # Initial Balance: 10,000 (from fixture, dated 2025-01-01)
    # T1 (Nov 26): -100
    # T2 (Nov 21): -200
    # Total = 10,000 - 100 - 200 = 9,700
    
    final_balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
    assert final_balance == Decimal("9700.00")
    
    # It should ALSO create a new lazy snapshot for Yesterday (Dec 07)
    # because we did a fresh calculation and the result is "cacheable" for yesterday.
    final_snapshot = snapshot_service.get_latest_snapshot(test_db, sample_wallet.id)
    assert final_snapshot is not None
    assert final_snapshot.snapshot_date == yesterday
    assert final_snapshot.balance == Decimal("9700.00")


def test_rolling_balance_history(test_db: Session):
    """Test get_rolling_balance_history calculation and side-effects."""
    # Create a fresh wallet to avoid interference from 'sample_wallet' fixture
    # which has an Initial Balance transaction at 'today' that skews history.
    fresh_wallet = Wallet(name="Fresh Wallet", wallet_type=WalletType.NORMAL)
    test_db.add(fresh_wallet)
    test_db.commit()
    test_db.refresh(fresh_wallet)
    
    today = date.today()
    
    # 1. Setup Transactions
    # T-30: +10,000 (Income)
    start_date = today - timedelta(days=30)
    t1 = Transaction(
        date=start_date,
        wallet_id=fresh_wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("10000.00"),
        classification=TransactionClassification.INCOME,
        description="Initial"
    )
    test_db.add(t1)
    
    # T-20: +1,000 (Income)
    t2 = Transaction(
        date=today - timedelta(days=20),
        wallet_id=fresh_wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("1000.00"),
        classification=TransactionClassification.INCOME
    )
    test_db.add(t2)
    
    # T-10: -2,000 (Expense)
    t3 = Transaction(
        date=today - timedelta(days=10),
        wallet_id=fresh_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("2000.00"),
        classification=TransactionClassification.EXPENSE
    )
    test_db.add(t3)
    
    test_db.commit()
    
    # 2. Query History
    # Range: T-30 to T-0. Interval: 10 days.
    # Expected Points:
    # T-30: 10000 (only t1)
    # T-20: 11000 (t1 + t2)
    # T-10: 9000 (t1 + t2 - t3)
    # T-0:  9000 (unchanged)
    
    history = wallet_service.get_rolling_balance_history(
        test_db, 
        fresh_wallet.id, 
        start_date=start_date, 
        end_date=today, 
        interval_days=10
    )
    
    # Verify Length (T-30, T-20, T-10, T-0 -> 4 points)
    assert len(history) == 4
    
    # Verify Values
    
    # Point 0: T-30
    assert history[0][0] == start_date
    assert history[0][1] == Decimal("10000.00")
    
    # Point 1: T-20
    assert history[1][0] == today - timedelta(days=20)
    assert history[1][1] == Decimal("11000.00")
    
    # Point 2: T-10
    assert history[2][0] == today - timedelta(days=10)
    assert history[2][1] == Decimal("9000.00")
    
    # Point 3: T-0
    # Should be 9000 (10000 + 1000 - 2000)
    assert history[3][0] == today
    assert history[3][1] == Decimal("9000.00")
    
    # 3. Verify NO new snapshots were created during this process
    snapshot = snapshot_service.get_latest_snapshot(test_db, fresh_wallet.id)
    assert snapshot is None

