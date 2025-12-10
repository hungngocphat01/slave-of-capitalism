"""Transaction service with updated logic for direction/classification model."""
from datetime import date
from decimal import Decimal
from typing import NamedTuple

from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkedEntry, LinkType, LinkStatus
from app.schemas.transaction import (
    TransactionCreate,
    TransactionUpdate,
    TransactionMergeRequest,
    WalletTransferRequest,
    WalletTransferResponse,
    TransactionResponse
)
from app.schemas.linked_entry import (
    LinkedEntryCreate,
    LinkedEntryResponse,
    MarkAsLoanRequest,
    MarkAsDebtRequest
)


def get_transaction(db: Session, transaction_id: int) -> Transaction | None:
    """Get a transaction by ID."""
    return db.query(Transaction).filter(Transaction.id == transaction_id).first()


def get_transactions(
    db: Session,
    skip: int = 0,
    limit: int = 1000,
    wallet_id: int | None = None,
    category_id: int | None = None,
    month: date | None = None,
    direction: TransactionDirection | None = None,
    classification: TransactionClassification | None = None,
) -> list[Transaction]:
    """
    Get transactions with optional filtering.
    
    Args:
        db: Database session
        skip: Number of records to skip
        limit: Maximum number of records to return
        wallet_id: Filter by wallet
        category_id: Filter by category (includes subcategories)
        month: Filter by month
        direction: Filter by direction (INFLOW/OUTFLOW)
        classification: Filter by classification
        
    Returns:
        List of transactions
    """
    query = db.query(Transaction)
    
    if wallet_id:
        query = query.filter(Transaction.wallet_id == wallet_id)
    
    if category_id:
        query = query.filter(
            (Transaction.category_id == category_id) |
            (Transaction.subcategory.has(category_id=category_id))
        )
    
    if month:
        start_date = month.replace(day=1)
        if month.month == 12:
            end_date = date(month.year + 1, 1, 1)
        else:
            end_date = date(month.year, month.month + 1, 1)
        query = query.filter(Transaction.date >= start_date, Transaction.date < end_date)
    
    if direction:
        query = query.filter(Transaction.direction == direction)
    
    if classification:
        query = query.filter(Transaction.classification == classification)
    
    return query.order_by(Transaction.date.desc(), Transaction.id.desc()).offset(skip).limit(limit).all()


def create_transaction(db: Session, transaction: TransactionCreate, commit: bool = True) -> Transaction:
    """Create a new transaction."""
    from app.services import snapshot_service
    
    # 1. Safety Check
    # Only check impact if inserting into the past (> threshold old)
    today = date.today()
    from app.constants import LARGE_CACHE_REBUILD_DAYS, LARGE_CACHE_REBUILD_TRANSACTIONS
    
    if (today - transaction.date).days > LARGE_CACHE_REBUILD_DAYS:
        impact = snapshot_service.check_rebuild_impact(db, transaction.wallet_id, transaction.date)
        if impact > LARGE_CACHE_REBUILD_TRANSACTIONS and not transaction.allow_large_cache_rebuild:
            raise ValueError(
                f"This change affects {impact} historical transactions. "
                "Please confirm large cache rebuild."
            )
        
    db_transaction = Transaction(**transaction.model_dump(exclude={"allow_large_cache_rebuild"}))
    db.add(db_transaction)
    
    # 2. Invalidate Snapshots
    snapshot_service.invalidate_snapshots(db, transaction.wallet_id, transaction.date)
    
    if commit:
        db.commit()
        db.refresh(db_transaction)
    else:
        db.flush()
        db.refresh(db_transaction)
        
    return db_transaction


def create_wallet_transfer(db: Session, request: WalletTransferRequest, commit: bool = True) -> WalletTransferResponse:
    """
    Create a wallet transfer (paired transactions).
    
    Creates:
    - OUTFLOW from source wallet
    - INFLOW to destination wallet
    - Links them via paired_transaction_id
    """
    # Create outflow transaction
    # We instantiate models directly to ensure atomic commit at the end.
    
    outflow_data = TransactionCreate(
        date=request.date,
        time=request.time,
        wallet_id=request.from_wallet_id,
        direction=TransactionDirection.OUTFLOW,
        amount=request.amount,
        classification=TransactionClassification.TRANSFER,
        description=request.description,
        paired_transaction_id=None
    ).model_dump(exclude={"allow_large_cache_rebuild"})
    
    db_outflow = Transaction(**outflow_data)
    db.add(db_outflow)
    db.flush() # Get ID
    
    inflow_data = TransactionCreate(
        date=request.date,
        time=request.time,
        wallet_id=request.to_wallet_id,
        direction=TransactionDirection.INFLOW,
        amount=request.amount,
        classification=TransactionClassification.TRANSFER,
        description=request.description,
        paired_transaction_id=db_outflow.id
    ).model_dump(exclude={"allow_large_cache_rebuild"})
    
    db_inflow = Transaction(**inflow_data)
    db.add(db_inflow)
    db.flush()
    
    # Update outflow with paired_transaction_id
    db_outflow.paired_transaction_id = db_inflow.id
    
    # Invalidate snapshots
    from app.services import snapshot_service
    snapshot_service.invalidate_snapshots(db, request.from_wallet_id, request.date)
    snapshot_service.invalidate_snapshots(db, request.to_wallet_id, request.date)
    
    if commit:
        db.commit()
        db.refresh(db_outflow)
        db.refresh(db_inflow)
    else:
        db.flush()
        db.refresh(db_outflow)
        db.refresh(db_inflow)
    
    return WalletTransferResponse(
        outflow_transaction=TransactionResponse.model_validate(db_outflow),
        inflow_transaction=TransactionResponse.model_validate(db_inflow)
    )


def update_transaction(
    db: Session, 
    transaction_id: int, 
    transaction: TransactionUpdate,
    propagate_to_pair: bool = True
) -> Transaction | None:
    """Update a transaction."""
    db_transaction = get_transaction(db, transaction_id)
    if not db_transaction:
        return None
    
    update_data = transaction.model_dump(exclude_unset=True)
    
    # Check for date change or amount change (amount change affects balance from that date)
    # Actually ANY change to a transaction (except maybe description) could affect balance if we track it strictly,
    # but primarily Date, Amount, Wallet, Direction, Classification are critical.
    # We should always invalidate from min(old_date, new_date).
    
    old_date = db_transaction.date
    old_wallet_id = db_transaction.wallet_id
    
    new_date = update_data.get("date", old_date)
    new_wallet_id = update_data.get("wallet_id", old_wallet_id)
    
    allow_rebuild = update_data.pop("allow_large_cache_rebuild", False)
    
    # Safety Check & Invalidation
    from app.services import snapshot_service
    from app.constants import LARGE_CACHE_REBUILD_DAYS, LARGE_CACHE_REBUILD_TRANSACTIONS
    
    # 1. Old Wallet / Old Date
    today = date.today()
    if (today - old_date).days > LARGE_CACHE_REBUILD_DAYS:
        impact_old = snapshot_service.check_rebuild_impact(db, old_wallet_id, old_date)
        if impact_old > LARGE_CACHE_REBUILD_TRANSACTIONS and not allow_rebuild:
             raise ValueError(f"Update affects {impact_old} historical transactions. Confirm large rebuild.")
         
    snapshot_service.invalidate_snapshots(db, old_wallet_id, old_date)
    
    # 2. New Wallet / New Date (if different)
    if new_wallet_id != old_wallet_id or new_date < old_date:
        if (today - new_date).days > LARGE_CACHE_REBUILD_DAYS:
            impact_new = snapshot_service.check_rebuild_impact(db, new_wallet_id, new_date)
            if impact_new > LARGE_CACHE_REBUILD_TRANSACTIONS and not allow_rebuild:
                 raise ValueError(f"Update affects {impact_new} historical transactions. Confirm large rebuild.")
        snapshot_service.invalidate_snapshots(db, new_wallet_id, new_date)

    for field, value in update_data.items():
        setattr(db_transaction, field, value)
        
    # Recursive update for paired transaction
    if propagate_to_pair and db_transaction.paired_transaction_id:
        paired_update_data = {}
        # Propagate specific fields
        if transaction.amount is not None:
            paired_update_data["amount"] = transaction.amount
        if transaction.date is not None:
            paired_update_data["date"] = transaction.date
        if transaction.description is not None:
            paired_update_data["description"] = transaction.description
        if transaction.classification is not None:
            paired_update_data["classification"] = transaction.classification
            
        if paired_update_data:
            # Avoid circular dependency by importing inside function if needed, 
            # but we are in the same function so we can just call it.
            # We create a new TransactionUpdate object
            paired_update = TransactionUpdate(**paired_update_data)
            update_transaction(
                db, 
                db_transaction.paired_transaction_id, 
                paired_update, 
                propagate_to_pair=False
            )
    
    db.commit()
    db.refresh(db_transaction)
    return db_transaction



def delete_transaction(db: Session, transaction_id: int, allow_large_cache_rebuild: bool = False) -> bool:
    """Delete a transaction."""
    return delete_transactions(db, [transaction_id], allow_large_cache_rebuild=allow_large_cache_rebuild)


def _delete_transaction_impl(db: Session, transaction_id: int) -> bool:
    """Internal implementation of delete without commit."""
    db_transaction = get_transaction(db, transaction_id)
    if not db_transaction:
        return False
    
    # 1. Handle Paired Transfer
    if db_transaction.paired_transaction_id:
        paired = get_transaction(db, db_transaction.paired_transaction_id)
        if paired:
            # Break the link first
            paired.paired_transaction_id = None
            db.add(paired)
            db.flush()
            db.delete(paired)

    # 2. Handle Primary Linked Entry (This transaction created a Split/Loan/Debt)
    if db_transaction.linked_entry_primary:
        db.delete(db_transaction.linked_entry_primary)

    # 3. Handle Linked Transactions (This transaction IS a repayment)
    if db_transaction.linked_transactions:
        from app.services import linked_entry_service
        for link in list(db_transaction.linked_transactions):
            linked_entry_service.unlink_transaction(db, link.id)
    
    db.delete(db_transaction)
    return True


def delete_transactions(db: Session, transaction_ids: list[int], allow_large_cache_rebuild: bool = False) -> bool:
    """
    Delete multiple transactions atomicaly.
    """
    # 1. Pre-fetch transactions to check impact and for invalidation
    txns = db.query(Transaction).filter(Transaction.id.in_(transaction_ids)).all()
    if not txns:
        return False
        
    # Group by wallet to check impact
    affected_wallets = {} # wallet_id -> min_date
    
    for txn in txns:
        current_min = affected_wallets.get(txn.wallet_id, txn.date)
        if txn.date < current_min:
             affected_wallets[txn.wallet_id] = txn.date
        else:
             affected_wallets[txn.wallet_id] = current_min

    # 2. Safety Check
    from app.services import snapshot_service
    from datetime import date
    from app.constants import LARGE_CACHE_REBUILD_DAYS, LARGE_CACHE_REBUILD_TRANSACTIONS
    
    today = date.today()
    
    for wallet_id, min_date in affected_wallets.items():
        if (today - min_date).days > LARGE_CACHE_REBUILD_DAYS:
            impact = snapshot_service.check_rebuild_impact(db, wallet_id, min_date)
            if impact > LARGE_CACHE_REBUILD_TRANSACTIONS and not allow_large_cache_rebuild:
                raise ValueError(
                    f"Deleting these transactions affects {impact} historical entries for wallet {wallet_id}. "
                    "Please confirm large cache rebuild."
                )

    # 3. Perform Deletion
    success = True
    for txn in txns:
        # We use strict delete here. 
        # Note: _delete_transaction_impl re-fetches, which is slightly inefficient but safe.
        # Alternatively we can refactor _delete_transaction_impl to accept object.
        if not _delete_transaction_impl(db, txn.id):
            success = False

    # 4. Invalidate Snapshots
    for wallet_id, min_date in affected_wallets.items():
        snapshot_service.invalidate_snapshots(db, wallet_id, min_date)

    try:
        db.commit()
        return True
    except Exception:
        db.rollback()
        raise


def reclassify_transaction(
    db: Session, transaction_id: int, new_classification: TransactionClassification
) -> Transaction | None:
    """
    Reclassify a transaction.
    
    Useful after CSV import when user wants to change classification.
    """
    db_transaction = get_transaction(db, transaction_id)
    if not db_transaction:
        return None
    
    db_transaction.classification = new_classification
    db.commit()
    db.refresh(db_transaction)
    return db_transaction


def ignore_transaction(db: Session, transaction_id: int) -> Transaction | None:
    """
    Mark a transaction as ignored.
    """
    if ignore_transactions(db, [transaction_id]):
        return get_transaction(db, transaction_id)
    return None


def unignore_transaction(db: Session, transaction_id: int) -> Transaction | None:
    """
    Unmark a transaction as ignored.
    """
    if unignore_transactions(db, [transaction_id]):
        return get_transaction(db, transaction_id)
    return None


def ignore_transactions(db: Session, transaction_ids: list[int]) -> bool:
    """
    Mark multiple transactions as ignored.
    """
    db.query(Transaction).filter(Transaction.id.in_(transaction_ids)).update(
        {Transaction.is_ignored: True}, synchronize_session=False
    )
    db.commit()
    return True


def unignore_transactions(db: Session, transaction_ids: list[int]) -> bool:
    """
    Unmark multiple transactions as ignored.
    """
    db.query(Transaction).filter(Transaction.id.in_(transaction_ids)).update(
        {Transaction.is_ignored: False}, synchronize_session=False
    )
    db.commit()
    return True


class ResolveCalibrationResult(NamedTuple):
    """Result of resolving a calibration transaction."""
    new_transaction: Transaction
    calibration_deleted: bool
    updated_calibration: Transaction | None


def resolve_calibration(
    db: Session,
    calibration_id: int,
    new_transaction_data: TransactionCreate
) -> ResolveCalibrationResult:
    """
    Resolve a calibration transaction by creating a new transaction.
    
    When a user remembers what caused the wallet balance discrepancy,
    they can "resolve" the calibration by creating the actual transaction.
    The calibration amount is adjusted to maintain the wallet balance.
    
    Args:
        db: Database session
        calibration_id: ID of calibration transaction
        new_transaction_data: Data for the new transaction
        
    Returns:
        ResolveCalibrationResult with new transaction and calibration status
        
    Raises:
        ValueError: If transaction is not a calibration
    """
    calibration = get_transaction(db, calibration_id)
    if not calibration:
        raise ValueError("Calibration transaction not found")
    
    if not calibration.is_calibration:
        raise ValueError("Transaction is not a calibration")
    
    # Create the new transaction
    # Enforce that the new transaction belongs to the same wallet as the calibration
    if new_transaction_data.wallet_id != calibration.wallet_id:
        new_transaction_data.wallet_id = calibration.wallet_id
        
    new_txn = create_transaction(db, new_transaction_data)
    
    # Adjust calibration amount
    # If same direction, subtract; if opposite direction, add
    # If same direction, subtract; if opposite direction, add
    if new_txn.direction == calibration.direction:
        new_calibration_amount = calibration.amount - new_txn.amount
    else:
        new_calibration_amount = calibration.amount + new_txn.amount
    
    # 1. Exact Match: Amount becomes 0
    if new_calibration_amount == Decimal("0.00"):
        calibration.amount = Decimal("0.00")
        calibration.is_ignored = True
        db.commit()
        db.refresh(calibration)
        return ResolveCalibrationResult(
            new_transaction=new_txn,
            calibration_deleted=False,
            updated_calibration=calibration
        )
        
    # 2. Over-Resolution: Amount becomes negative
    elif new_calibration_amount < Decimal("0.00"):
        # Flip direction and use absolute amount
        new_direction = (
            TransactionDirection.INFLOW 
            if calibration.direction == TransactionDirection.OUTFLOW 
            else TransactionDirection.OUTFLOW
        )
        # Flip classification too for consistency? 
        # Usually EXPENSE <-> INCOME. 
        # But classification is loose. Let's try to map it intelligently.
        new_classification = (
            TransactionClassification.INCOME
            if new_direction == TransactionDirection.INFLOW
            else TransactionClassification.EXPENSE
        )
        
        calibration.amount = abs(new_calibration_amount)
        calibration.direction = new_direction
        calibration.classification = new_classification
        calibration.is_ignored = False # Ensure active
        
        db.commit()
        db.refresh(calibration)
        
        return ResolveCalibrationResult(
            new_transaction=new_txn,
            calibration_deleted=False,
            updated_calibration=calibration
        )
    
    # 3. Partial Resolution: Amount still positive
    else:
        calibration.amount = new_calibration_amount
        db.commit()
        db.refresh(calibration)
        
        return ResolveCalibrationResult(
            new_transaction=new_txn,
            calibration_deleted=False,
            updated_calibration=calibration
        )


def merge_transactions(db: Session, request: TransactionMergeRequest) -> Transaction:
    """
    Merge multiple transactions into one.
    
    Validates:
    - At least 2 transactions.
    - Same wallet.
    - Same direction.
    
    Creates a new transaction with sum of amounts and specified details.
    Deletes the original transactions.
    """
    # 1. Fetch all transactions
    txns = db.query(Transaction).filter(Transaction.id.in_(request.transaction_ids)).all()
    
    if len(txns) != len(request.transaction_ids):
        raise ValueError("Some transactions not found")
        
    if len(txns) < 2:
        raise ValueError("Must select at least 2 transactions to merge")
        
    # 2. Validate consistency
    first_txn = txns[0]
    wallet_id = first_txn.wallet_id
    direction = first_txn.direction
    
    total_amount = Decimal("0.00")
    
    for txn in txns:
        if txn.wallet_id != wallet_id:
            raise ValueError("All transactions must belong to the same wallet")
        if txn.direction != direction:
            raise ValueError("All transactions must have the same direction")
            
        # Check for special transactions
        if txn.is_calibration:
            raise ValueError("Cannot merge special transactions (Calibration)")
            
        if txn.classification not in [TransactionClassification.EXPENSE, TransactionClassification.INCOME]:
             raise ValueError(f"Cannot merge special transactions ({txn.classification})")
            
        total_amount += txn.amount
        
    # 3. Create new transaction
    classification = first_txn.classification
    
    same_classification = all(t.classification == first_txn.classification for t in txns)
    if not same_classification:
        classification = (
            TransactionClassification.EXPENSE 
            if direction == TransactionDirection.OUTFLOW 
            else TransactionClassification.INCOME
        )
        
    new_txn = Transaction(
        date=request.date,
        wallet_id=wallet_id,
        direction=direction,
        amount=total_amount,
        classification=classification,
        description=request.description,
        category_id=request.category_id,
        subcategory_id=request.subcategory_id
    )
    
    db.add(new_txn)
    
    # 4. Delete old transactions
    for txn in txns:
        _delete_transaction_impl(db, txn.id)
        
    db.commit()
    db.refresh(new_txn)
    return new_txn

def calculate_monthly_expense(db: Session, month: date) -> Decimal:
    """
    Calculate true monthly expense.
    
    Formula:
    - Sum all OUTFLOW transactions with classification=EXPENSE
    - For SPLIT_PAYMENT, only count user's share
    - Exclude LEND, LOAN_REPAYMENT, TRANSFER (not expenses)
    - Exclude ignored transactions (is_ignored=True)
    
    Args:
        db: Database session
        month: Month to calculate (any date in the month)
        
    Returns:
        Total monthly expense
    """
    start_date = month.replace(day=1)
    if month.month == 12:
        end_date = date(month.year + 1, 1, 1)
    else:
        end_date = date(month.year, month.month + 1, 1)
    
    # Regular expenses (excluding ignored)
    regular_expense = (
        db.query(func.sum(Transaction.amount))
        .filter(
            Transaction.date >= start_date,
            Transaction.date < end_date,
            Transaction.direction == TransactionDirection.OUTFLOW,
            Transaction.classification == TransactionClassification.EXPENSE,
            Transaction.is_ignored == False  # Exclude ignored transactions
        )
        .scalar()
    ) or Decimal("0.00")
    
    # Split payments - only count user's share (excluding ignored)
    split_expense = Decimal("0.00")
    split_entries = (
        db.query(LinkedEntry)
        .join(Transaction, LinkedEntry.primary_transaction_id == Transaction.id)
        .filter(
            Transaction.date >= start_date,
            Transaction.date < end_date,
            LinkedEntry.link_type == LinkType.SPLIT_PAYMENT,
            Transaction.is_ignored == False  # Exclude ignored transactions
        )
        .all()
    )
    
    for entry in split_entries:
        if entry.user_amount:
            split_expense += entry.user_amount
    
    return regular_expense + split_expense


def calculate_category_breakdown(db: Session, month: date) -> dict[str, Decimal]:
    """
    Calculate spending breakdown by category for a month.
    
    Excludes ignored transactions.
    
    Args:
        db: Database session
        month: Month to calculate
        
    Returns:
        Dictionary mapping category name to total amount
    """
    from app.models.category import Category
    
    start_date = month.replace(day=1)
    if month.month == 12:
        end_date = date(month.year + 1, 1, 1)
    else:
        end_date = date(month.year, month.month + 1, 1)
    
    # Get all expense transactions for the month (excluding ignored)
    transactions = (
        db.query(Transaction)
        .options(joinedload(Transaction.linked_entry_primary))
        .filter(
            Transaction.date >= start_date,
            Transaction.date < end_date,
            Transaction.direction == TransactionDirection.OUTFLOW,
            Transaction.classification.in_([
                TransactionClassification.EXPENSE,
                TransactionClassification.SPLIT_PAYMENT
            ]),
            Transaction.is_ignored == False  # Exclude ignored transactions
        )
        .all()
    )
    
    breakdown = {}
    
    for txn in transactions:
        category_name = txn.category.name if txn.category else "Uncategorized"
        
        if txn.classification == TransactionClassification.SPLIT_PAYMENT:
            # Only count user's share
            entry = txn.linked_entry_primary
            amount = entry.user_amount if entry and entry.user_amount else txn.amount
        else:
            amount = txn.amount
        
        breakdown[category_name] = breakdown.get(category_name, Decimal("0.00")) + amount
    
    return breakdown


def mark_as_loan(db: Session, transaction_id: int, request: MarkAsLoanRequest) -> LinkedEntryResponse:
    """
    Mark an OUTFLOW transaction as a LOAN.
    """
    txn = get_transaction(db, transaction_id)
    if not txn:
        raise ValueError("Transaction not found")
        
    if txn.direction != TransactionDirection.OUTFLOW:
        raise ValueError("Loan must be an OUTFLOW transaction")

    # Update classification
    previous_classification = txn.classification
    txn.classification = TransactionClassification.LEND
    
    try:
        from app.services import linked_entry_service
        entry_create = LinkedEntryCreate(
            primary_transaction_id=transaction_id,
            link_type=LinkType.LOAN,
            counterparty_name=request.counterparty_name,
            notes=request.notes
        )
        # We need to do this carefully. linked_entry_service.create_linked_entry performs a commit.
        # Ideally we refactor linked_entry_service too, but for now let's use it 
        # as it encapsulates the creation logic.
        # However, we changed classification above but haven't committed.
        # create_linked_entry will commit the classification change as part of its commit because it uses the same session.
        
        entry = linked_entry_service.create_linked_entry(db, entry_create)
        return LinkedEntryResponse.model_validate(entry)
        
    except Exception as e:
        db.rollback() # Rollback classification change
        # If the error was from create_linked_entry validation, it's raised before commit there.
        # If it committed there, we can't rollback easily unless we nested.
        # But create_linked_entry checks logic before adding to DB.
        raise e


def mark_as_debt(db: Session, transaction_id: int, request: MarkAsDebtRequest) -> LinkedEntryResponse:
    """
    Mark an INFLOW transaction as a DEBT.
    """
    txn = get_transaction(db, transaction_id)
    if not txn:
        raise ValueError("Transaction not found")
        
    if txn.direction != TransactionDirection.INFLOW:
        raise ValueError("Debt must be an INFLOW transaction")

    # Update classification
    txn.classification = TransactionClassification.BORROW
    
    try:
        from app.services import linked_entry_service
        entry_create = LinkedEntryCreate(
            primary_transaction_id=transaction_id,
            link_type=LinkType.DEBT,
            counterparty_name=request.counterparty_name,
            notes=request.notes
        )
        entry = linked_entry_service.create_linked_entry(db, entry_create)
        return LinkedEntryResponse.model_validate(entry)
        
    except Exception as e:
        db.rollback()
        raise e
