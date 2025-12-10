"""Service for managing wallet snapshots."""
from datetime import date
from decimal import Decimal

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.models.snapshot import WalletSnapshot
from app.models.transaction import Transaction


def create_snapshot(
    db: Session,
    wallet_id: int,
    snapshot_date: date,
    balance: Decimal
) -> WalletSnapshot:
    """
    Create a new wallet snapshot.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        snapshot_date: Date for the snapshot
        balance: Balance amount
        
    Returns:
        Created snapshot
    """
    snapshot = WalletSnapshot(
        wallet_id=wallet_id,
        snapshot_date=snapshot_date,
        balance=balance
    )
    db.add(snapshot)
    db.commit()
    db.refresh(snapshot)
    return snapshot


def get_latest_snapshot(
    db: Session,
    wallet_id: int,
    before_date: date | None = None
) -> WalletSnapshot | None:
    """
    Get the latest snapshot for a wallet before or on a specific date.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        before_date: If provided, find latest snapshot <= this date.
                     If None, find latest snapshot overall.
    
    Returns:
        Latest WalletSnapshot or None
    """
    query = db.query(WalletSnapshot).filter(WalletSnapshot.wallet_id == wallet_id)
    
    if before_date:
        query = query.filter(WalletSnapshot.snapshot_date <= before_date)
        
    return query.order_by(WalletSnapshot.snapshot_date.desc()).first()


def invalidate_snapshots(
    db: Session,
    wallet_id: int,
    from_date: date
) -> int:
    """
    Invalidate (delete) all snapshots from a specific date onwards.
    
    Used when a transaction is added/modified/deleted in the past,
    rendering future snapshots incorrect.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        from_date: Date from which to invalidate (inclusive)
        
    Returns:
        Number of deleted snapshots
    """
    # Create query for deletion
    query = db.query(WalletSnapshot).filter(
        WalletSnapshot.wallet_id == wallet_id,
        WalletSnapshot.snapshot_date >= from_date
    )
    
    # Execute delete
    deleted_count = query.delete(synchronize_session=False)
    db.commit()
    return deleted_count


def check_rebuild_impact(
    db: Session,
    wallet_id: int,
    from_date: date
) -> int:
    """
    Check how many transactions will need to be re-summed if we invalidate from this date.
    
    This is used to warn the user if they are editing very old history.
    
    Args:
        db: Database session
        wallet_id: Wallet ID
        from_date: Date of the change
        
    Returns:
        Count of transactions that exist after from_date
    """
    return db.query(func.count(Transaction.id)).filter(
        Transaction.wallet_id == wallet_id,
        Transaction.date >= from_date
    ).scalar() or 0
