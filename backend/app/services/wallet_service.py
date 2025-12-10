"""Wallet service for CRUD operations and balance calculations."""
from datetime import date, timedelta
from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.transaction import Transaction
from app.models.wallet import Wallet
from app.schemas.wallet import WalletCreate, WalletUpdate


def get_wallet(db: Session, wallet_id: int) -> Wallet | None:
    """
    Get wallet by ID.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        
    Returns:
        Wallet or None if not found
    """
    return db.query(Wallet).filter(Wallet.id == wallet_id).first()


def get_wallets(db: Session, skip: int = 0, limit: int = 100) -> list[Wallet]:
    """
    Get all wallets with pagination.
    
    Args:
        db: Database session
        skip: Number of records to skip
        limit: Maximum number of records to return
        
    Returns:
        List of wallets
    """
    return db.query(Wallet).offset(skip).limit(limit).all()


def create_wallet(db: Session, wallet: WalletCreate) -> Wallet:
    """
    Create a new wallet.
    
    If initial_balance is provided, creates an "INITIAL BALANCE" transaction.
    """
    from app.models.transaction import TransactionDirection, TransactionClassification
    from datetime import date

    # Extract initial_balance (not in model)
    initial_balance = wallet.initial_balance
    wallet_data = wallet.model_dump(exclude={"initial_balance"})
    
    db_wallet = Wallet(**wallet_data)
    db.add(db_wallet)
    db.commit()
    db.refresh(db_wallet)
    
    # Create initial transaction if needed
    if initial_balance > Decimal("0.00"):
        # We need to create a transaction
        # Direction: INFLOW
        # Classification: INCOME (technically it's capital)
        init_txn = Transaction(
            date=date.today(),
            wallet_id=db_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=initial_balance,
            classification=TransactionClassification.INCOME,
            description="INITIAL BALANCE",
            is_ignored=True # Should be ignored for income/expense reports, but counts for balance
        )
        db.add(init_txn)
        db.commit()
        
    return db_wallet


def update_wallet(db: Session, wallet_id: int, wallet: WalletUpdate) -> Wallet | None:
    """
    Update an existing wallet.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        wallet: Wallet update data
        
    Returns:
        Updated wallet or None if not found
    """
    db_wallet = get_wallet(db, wallet_id)
    if not db_wallet:
        return None
    
    # Update only provided fields
    update_data = wallet.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_wallet, field, value)
    
    db.commit()
    db.refresh(db_wallet)
    return db_wallet


def delete_wallet(db: Session, wallet_id: int) -> bool:
    """
    Delete a wallet.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        
    Returns:
        True if deleted, False if not found
        
    Raises:
        ValueError: If wallet has associated transactions
    """
    db_wallet = get_wallet(db, wallet_id)
    if not db_wallet:
        return False
        
    # Check for existing transactions
    has_transactions = db.query(Transaction).filter(Transaction.wallet_id == wallet_id).first()
    if has_transactions:
        raise ValueError("Cannot delete wallet with existing transactions")
    
    db.delete(db_wallet)
    db.commit()
    return True


def calculate_wallet_balance(
    db: Session, 
    wallet_id: int, 
    for_date: date | None = None, 
    trigger_lazy_snapshot: bool = True
) -> Decimal:
    """
    Calculate current balance for a wallet.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        for_date: Optional date to calculate balance for (inclusive). Defaults to Today.
        trigger_lazy_snapshot: Whether to trigger lazy snapshot creation. 
                               Should be False for historical queries.
        
    Returns:
        Current balance (for normal) or amount owed (for credit)
    """
    from app.services import snapshot_service
    from app.models.wallet import WalletType
    from app.models.transaction import TransactionDirection
    from datetime import date, timedelta
    
    wallet = get_wallet(db, wallet_id)
    if not wallet:
        return Decimal("0.00")
    
    # Determine target date
    target_date = for_date if for_date else date.today()
        
    # 1. Get latest snapshot BEFORE or ON target_date
    latest_snapshot = snapshot_service.get_latest_snapshot(db, wallet_id, before_date=target_date)
    
    start_balance = Decimal("0.00")
    query_start_date = date.min
    
    if latest_snapshot:
        start_balance = latest_snapshot.balance
        # Filter transactions AFTER the snapshot date
        query_start_date = latest_snapshot.snapshot_date

    # 2. Sum transactions since snapshot (or beginning)
    # Note: We need to handle the date filter carefully. 
    # Snapshot balance is at END of snapshot_date. So we sum > snapshot_date.
    
    # Common filters
    filters = [
        Transaction.wallet_id == wallet_id,
        Transaction.date <= target_date  # Up to target date
    ]
    
    if latest_snapshot:
        filters.append(Transaction.date > query_start_date)
    
    inflow_sum = db.query(func.sum(Transaction.amount)).filter(
        *filters,
        Transaction.direction == TransactionDirection.INFLOW
    ).scalar() or Decimal("0.00")
    
    outflow_sum = db.query(func.sum(Transaction.amount)).filter(
        *filters,
        Transaction.direction == TransactionDirection.OUTFLOW
    ).scalar() or Decimal("0.00")
    
    # 3. Calculate final balance based on type
    if wallet.wallet_type == WalletType.CREDIT:
        # Credit Wallet Logic
        balance_change = outflow_sum - inflow_sum
        final_balance = start_balance + balance_change
        
        # We don't implement lazy snapshots for Credit Wallets in this path yet generally, 
        # but if we did, logic would be similar to below.
        return final_balance
        
    else:
        # Normal Wallet Logic
        balance_change = inflow_sum - outflow_sum
        final_balance = start_balance + balance_change
        
        # Lazy Snapshot Creation
        # Only if:
        # 1. trigger_lazy_snapshot is True
        # 2. We are calculating for TODAY (historical snapshots shouldn't be created lazily 
        #    based on random queries, though arguably valid, but let's stick to safe 'Yesterday' logic)
        # 3. target_date is today (implicit in logic)
        
        # Actually, if we query for a past date, establishing a snapshot there is fine IF it's accurate.
        # But 'lazy snapshot' logic is specifically "Create snapshot for Yesterday if Today's lookup is slow".
        # If we query for T-100, we technically calculate T-100 balance. We COULD snapshot T-100.
        # But let's respect the flag.
        
        if trigger_lazy_snapshot and target_date == date.today():
             today = date.today()
             from app.constants import LAZY_SNAPSHOT_INTERVAL_DAYS
             should_create_snapshot = False
             
             if not latest_snapshot:
                 should_create_snapshot = True
             elif (today - latest_snapshot.snapshot_date).days > LAZY_SNAPSHOT_INTERVAL_DAYS:
                 should_create_snapshot = True
                 
             if should_create_snapshot:
                 snapshot_date = today - timedelta(days=1)
                 
                 if latest_snapshot and latest_snapshot.snapshot_date >= snapshot_date:
                      pass
                 else:
                     # Calculate balance at end of snapshot_date (Yesterday)
                     # Balance(Yesterday) = Current Balance - Inflows(Today) + Outflows(Today)
                     
                     # Check if we have transactions today that we need to reverse
                     inflows_today = db.query(func.sum(Transaction.amount)).filter(
                         Transaction.wallet_id == wallet_id,
                         Transaction.direction == TransactionDirection.INFLOW,
                         Transaction.date == today
                     ).scalar() or Decimal("0.00")
                     
                     outflows_today = db.query(func.sum(Transaction.amount)).filter(
                         Transaction.wallet_id == wallet_id,
                         Transaction.direction == TransactionDirection.OUTFLOW,
                         Transaction.date == today
                     ).scalar() or Decimal("0.00")
                     
                     balance_yesterday = final_balance - inflows_today + outflows_today
                     
                     existing = snapshot_service.get_latest_snapshot(db, wallet_id, before_date=snapshot_date)
                     # Check exact match. get_latest returns <= date.
                     if existing and existing.snapshot_date == snapshot_date:
                         pass 
                     else:
                         snapshot_service.create_snapshot(db, wallet_id, snapshot_date, balance_yesterday)

        return final_balance


def calibrate_wallet(
    db: Session,
    wallet_id: int,
    correct_balance: Decimal,
    misc_category_id: int
) -> Transaction:
    """
    Calibrate wallet balance by creating an adjustment transaction.
    
    When the actual wallet balance doesn't match the calculated balance,
    this creates a calibration transaction to fix the discrepancy.
    
    Args:
        db: Database session
        wallet_id: Wallet ID to calibrate
        correct_balance: What the balance should actually be
        misc_category_id: ID of "Miscellaneous" category for calibration
        
    Returns:
        Created calibration transaction
        
    Raises:
        ValueError: If wallet not found
    """
    from app.models.transaction import TransactionDirection, TransactionClassification
    from datetime import date
    
    wallet = get_wallet(db, wallet_id)
    if not wallet:
        raise ValueError("Wallet not found")
    
    # Calculate current balance
    current_balance = calculate_wallet_balance(db, wallet_id)
    
    # Calculate difference
    difference = correct_balance - current_balance
    
    # If no difference, no calibration needed
    if difference == Decimal("0.00"):
        raise ValueError("Wallet balance is already correct")
    
    # Determine direction and classification based on difference
    if difference > Decimal("0.00"):
        # Need to add money (INFLOW)
        direction = TransactionDirection.INFLOW
        classification = TransactionClassification.INCOME
        amount = difference
    else:
        # Need to remove money (OUTFLOW)
        direction = TransactionDirection.OUTFLOW
        classification = TransactionClassification.EXPENSE
        amount = abs(difference)
    
    # Create calibration transaction
    calibration = Transaction(
        date=date.today(),
        wallet_id=wallet_id,
        direction=direction,
        amount=amount,
        classification=classification,
        description="CALIBRATION",
        category_id=misc_category_id,
        is_calibration=True,
        is_ignored=False  # Calibrations count toward budget by default
    )
    
    db.add(calibration)
    db.commit()
    db.add(calibration)
    db.commit()
    db.refresh(calibration)
    
    return calibration


def get_rolling_balance_history(
    db: Session, 
    wallet_id: int, 
    start_date: date, 
    end_date: date, 
    interval_days: int
) -> list[tuple[date, Decimal]]:
    """
    Get rolling balance history for a wallet.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        start_date: Start date (inclusive)
        end_date: End date (inclusive)
        interval_days: Step size in days
        
    Returns:
        List of (date, balance) tuples
    """
    history = []
    current_date = start_date
    
    while current_date <= end_date:
        # Calculate balance for this specific date
        # Important: transparently uses existing snapshot logic (READS cache)
        # but disables lazy snapshot creation (NO WRITES) to avoid polluting cache with intermediate steps.
        balance = calculate_wallet_balance(
            db, 
            wallet_id, 
            for_date=current_date, 
            trigger_lazy_snapshot=False
        )
        history.append((current_date, balance))
        current_date += timedelta(days=interval_days)
        
    return history

