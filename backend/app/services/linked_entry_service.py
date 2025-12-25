"""Linked entry service for splits, loans, and debts."""
from decimal import Decimal

from sqlalchemy.orm import Session

from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkedEntry, LinkedTransaction, LinkType, LinkStatus
from app.schemas.linked_entry import LinkedEntryCreate, LinkedEntryUpdate
from app.services import snapshot_service


class LinkedEntryError(Exception):
    """Custom exception for linked entry errors."""
    pass


def get_linked_entry(db: Session, entry_id: int) -> LinkedEntry | None:
    """Get a linked entry by ID."""
    return db.query(LinkedEntry).filter(LinkedEntry.id == entry_id).first()


def get_linked_entries(
    db: Session,
    link_type: LinkType | None = None,
    status: LinkStatus | None = None,
    skip: int = 0,
    limit: int = 100,
) -> list[LinkedEntry]:
    """Get linked entries with optional filtering."""
    query = db.query(LinkedEntry)
    
    if link_type:
        query = query.filter(LinkedEntry.link_type == link_type)
    
    if status:
        query = query.filter(LinkedEntry.status == status)
    
    return query.order_by(LinkedEntry.created_at.desc()).offset(skip).limit(limit).all()


def get_pending_entries(db: Session) -> list[LinkedEntry]:
    """Get all pending and partial entries."""
    return db.query(LinkedEntry).filter(
        LinkedEntry.status.in_([LinkStatus.PENDING, LinkStatus.PARTIAL])
    ).all()


def create_linked_entry(db: Session, entry: LinkedEntryCreate) -> LinkedEntry:
    """
    Create a new linked entry.
    
    Validates:
    - Transaction exists
    - Transaction not already linked
    - For SPLIT_PAYMENT: user_amount must be provided and <= total_amount
    - For LOAN: transaction must be OUTFLOW with LEND classification
    - For DEBT: transaction must be INFLOW with BORROW classification
    """
    # Get primary transaction
    txn = db.query(Transaction).filter(Transaction.id == entry.primary_transaction_id).first()
    if not txn:
        raise LinkedEntryError(f"Transaction {entry.primary_transaction_id} not found")
    
    # Check if already linked
    existing = db.query(LinkedEntry).filter(
        LinkedEntry.primary_transaction_id == entry.primary_transaction_id
    ).first()
    if existing:
        raise LinkedEntryError(f"Transaction {entry.primary_transaction_id} already has a linked entry")
    
    # Validate based on link type
    if entry.link_type == LinkType.SPLIT_PAYMENT:
        if not entry.user_amount:
            raise LinkedEntryError("user_amount is required for split payments")
        if entry.user_amount > txn.amount:
            raise LinkedEntryError("user_amount cannot exceed transaction amount")
        if txn.direction != TransactionDirection.OUTFLOW:
            raise LinkedEntryError("Split payment must be an OUTFLOW transaction")
        
        # Validate classification is already set
        if txn.classification != TransactionClassification.SPLIT_PAYMENT:
            raise LinkedEntryError("Transaction must be classified as SPLIT_PAYMENT before creating linked entry")
        
        # Calculate pending amount (what others owe)
        pending_amount = txn.amount - entry.user_amount
        
    elif entry.link_type == LinkType.LOAN:
        if txn.direction != TransactionDirection.OUTFLOW:
            raise LinkedEntryError("Loan must be an OUTFLOW transaction")
        if txn.classification != TransactionClassification.LEND:
            raise LinkedEntryError("Loan transaction must have LEND classification")
        
        pending_amount = txn.amount
        
    elif entry.link_type == LinkType.DEBT:
        if txn.direction != TransactionDirection.INFLOW:
            raise LinkedEntryError("Debt must be an INFLOW transaction")
        if txn.classification != TransactionClassification.BORROW:
            raise LinkedEntryError("Debt transaction must have BORROW classification")
        
        pending_amount = txn.amount
    
    elif entry.link_type == LinkType.INSTALLMENT:
        # Validate transaction state - must already be configured
        if txn.direction != TransactionDirection.RESERVED:
            raise LinkedEntryError("Installment transaction must have RESERVED direction")
        if txn.classification != TransactionClassification.INSTALLMENT:
            raise LinkedEntryError("Installment transaction must have INSTALLMENT classification")

        # Full amount is pending (no user_amount for installments)
        pending_amount = txn.amount

    
    # Create linked entry
    db_entry = LinkedEntry(
        link_type=entry.link_type,
        primary_transaction_id=entry.primary_transaction_id,
        counterparty_name=entry.counterparty_name,
        total_amount=txn.amount,
        user_amount=entry.user_amount,
        pending_amount=pending_amount,
        status=LinkStatus.PENDING,
        notes=entry.notes
    )
    
    db.add(db_entry)
    db.commit()
    db.refresh(db_entry)
    return db_entry


def link_transaction(
    db: Session, entry_id: int, transaction_id: int
) -> LinkedEntry:
    """
    Link a transaction to an entry (reimbursement, payback, repayment).
    """
    return link_transactions(db, entry_id, [transaction_id])


def link_transactions(
    db: Session, entry_id: int, transaction_ids: list[int]
) -> LinkedEntry:
    """
    Link multiple transactions to an entry atomically.
    
    Validates that total amount of all transactions does not exceed pending amount.
    """
    entry = get_linked_entry(db, entry_id)
    if not entry:
        raise LinkedEntryError(f"Linked entry {entry_id} not found")
        
    if entry.status == LinkStatus.SETTLED:
        raise LinkedEntryError(f"Entry {entry_id} is already fully settled")
        
    # Get all transactions
    transactions = db.query(Transaction).filter(Transaction.id.in_(transaction_ids)).all()
    if len(transactions) != len(transaction_ids):
        found_ids = {t.id for t in transactions}
        missing_ids = set(transaction_ids) - found_ids
        raise LinkedEntryError(f"Transactions not found: {missing_ids}")
        
    # Validate amounts and types
    total_amount = sum(t.amount for t in transactions)
    if total_amount > entry.pending_amount:
        raise LinkedEntryError(
            f"Total amount {total_amount} exceeds pending amount {entry.pending_amount}"
        )
        
    # Validate each transaction and link
    # We can reuse logic or replicate it. 
    # Since we need to update classifications, it's safer to replicate core logic or helper.
    
    # 1. Check existing links
    existing_links = db.query(LinkedTransaction).filter(
        LinkedTransaction.transaction_id.in_(transaction_ids)
    ).all()
    if existing_links:
        already_linked_ids = [l.transaction_id for l in existing_links]
        raise LinkedEntryError(f"Transactions already linked: {already_linked_ids}")
        
    # 2. Process each
    for txn in transactions:
        # Validate type
        if entry.link_type in [LinkType.SPLIT_PAYMENT, LinkType.LOAN]:
            if txn.direction != TransactionDirection.INFLOW:
                raise LinkedEntryError(f"Transaction {txn.id} must be INFLOW")
            
            if txn.classification == TransactionClassification.INCOME:
                txn.classification = TransactionClassification.DEBT_COLLECTION
                db.add(txn)
            elif txn.classification != TransactionClassification.DEBT_COLLECTION:
                 raise LinkedEntryError(f"Transaction {txn.id} must use correct classification")
                 
        elif entry.link_type == LinkType.DEBT:
            if txn.direction != TransactionDirection.OUTFLOW:
                raise LinkedEntryError(f"Transaction {txn.id} must be OUTFLOW")
                
            if txn.classification == TransactionClassification.EXPENSE:
                txn.classification = TransactionClassification.LOAN_REPAYMENT
                db.add(txn)
            elif txn.classification != TransactionClassification.LOAN_REPAYMENT:
                raise LinkedEntryError(f"Transaction {txn.id} must use correct classification")
        
        elif entry.link_type == LinkType.INSTALLMENT:
            # Installment charges must be OUTFLOW (same direction as parent)
            if txn.direction != TransactionDirection.OUTFLOW:
                raise LinkedEntryError(f"Installment charge {txn.id} must be OUTFLOW")
            
            # Auto-classify as INSTALLMT_CHRGE if it's regular EXPENSE
            if txn.classification == TransactionClassification.EXPENSE:
                txn.classification = TransactionClassification.INSTALLMT_CHRGE
                db.add(txn)
            elif txn.classification != TransactionClassification.INSTALLMT_CHRGE:
                raise LinkedEntryError(
                    f"Transaction {txn.id} must be EXPENSE or INSTALLMT_CHRGE"
                )
                
        # Create link
        link = LinkedTransaction(
            linked_entry_id=entry_id,
            transaction_id=txn.id
        )
        db.add(link)
        
        # Invalidate wallet snapshots if classification changed
        # This ensures balance recalculation reflects the new classification
        if txn.classification in [TransactionClassification.LOAN_REPAYMENT, TransactionClassification.INSTALLMT_CHRGE]:
            snapshot_service.invalidate_snapshots(db, txn.wallet_id, txn.date)
        
    # Update entry
    entry.pending_amount -= total_amount
    
    if entry.pending_amount == Decimal("0.00"):
        entry.status = LinkStatus.SETTLED
    else:
        entry.status = LinkStatus.PARTIAL
        
    db.commit()
    db.refresh(entry)
    return entry


def unlink_transaction(db: Session, link_id: int) -> LinkedEntry:
    """
    Unlink a transaction from an entry.
    
    Useful for correcting mistakes or when reimbursement is reversed.
    """
    link = db.query(LinkedTransaction).filter(LinkedTransaction.id == link_id).first()
    if not link:
        raise LinkedEntryError(f"Link {link_id} not found")
    
    entry = link.linked_entry
    
    # Restore pending amount
    entry.pending_amount += link.amount
    
    # Update status
    if entry.pending_amount >= entry.total_amount:
        entry.status = LinkStatus.PENDING
    elif entry.pending_amount <= Decimal("0.01"):
        entry.status = LinkStatus.SETTLED
    else:
        entry.status = LinkStatus.PARTIAL
    
    # Delete link
    db.delete(link)
    db.commit()
    db.refresh(entry)
    return entry


def unlink_transaction_by_id(db: Session, transaction_id: int) -> bool:
    """
    Unlink a transaction from its linked entry by transaction ID.
    """
    link = db.query(LinkedTransaction).filter(
        LinkedTransaction.transaction_id == transaction_id
    ).first()
    
    if not link:
        return False
        
    unlink_transaction(db, link.id)
    return True


def delete_linked_entry(db: Session, entry_id: int) -> bool:
    """Delete a linked entry and all its links."""
    entry = get_linked_entry(db, entry_id)
    if not entry:
        return False
    
    db.delete(entry)
    db.commit()
    return True


def calculate_total_owed(db: Session) -> Decimal:
    """Calculate total amount owed to user (pending splits and loans)."""
    entries = db.query(LinkedEntry).filter(
        LinkedEntry.link_type.in_([LinkType.SPLIT_PAYMENT, LinkType.LOAN]),
        LinkedEntry.status.in_([LinkStatus.PENDING, LinkStatus.PARTIAL])
    ).all()
    
    return sum(entry.pending_amount for entry in entries)


def calculate_total_debt(db: Session) -> Decimal:
    """Calculate total amount user owes (pending debts)."""
    entries = db.query(LinkedEntry).filter(
        LinkedEntry.link_type == LinkType.DEBT,
        LinkedEntry.status.in_([LinkStatus.PENDING, LinkStatus.PARTIAL])
    ).all()
    
    return sum(entry.pending_amount for entry in entries)


def calculate_pending_installments(db: Session, wallet_id: int | None = None) -> Decimal:
    """
    Calculate total pending installment amounts.
    
    This represents committed future charges that haven't been realized yet.
    These amounts reserve credit limit but haven't incurred actual debt.
    
    Args:
        db: Database session
        wallet_id: Optional wallet ID to filter by
        
    Returns:
        Total pending installment amount
    """
    from app.models.transaction import Transaction
    
    query = db.query(LinkedEntry).join(
        Transaction, LinkedEntry.primary_transaction_id == Transaction.id
    ).filter(
        LinkedEntry.link_type == LinkType.INSTALLMENT,
        LinkedEntry.status.in_([LinkStatus.PENDING, LinkStatus.PARTIAL])
    )
    
    if wallet_id:
        query = query.filter(Transaction.wallet_id == wallet_id)
    
    entries = query.all()
    
    return sum(entry.pending_amount for entry in entries)



def unclassify_transaction(db: Session, transaction_id: int) -> bool:
    """
    Unclassify a transaction (remove split/loan/debt status).
    
    1. Finds the linked entry for the transaction
    2. Deletes the linked entry (and cascades to links)
    3. Reverts transaction classification to default:
       - SPLIT_PAYMENT/LEND -> EXPENSE
       - BORROW -> INCOME
    """
    # Get transaction
    txn = db.query(Transaction).filter(Transaction.id == transaction_id).first()
    if not txn:
        return False
        
    # Get linked entry
    entry = db.query(LinkedEntry).filter(
        LinkedEntry.primary_transaction_id == transaction_id
    ).first()
    
    if entry:
        # Revert linked transactions classifications
        for link in entry.linked_transactions:
            linked_txn = link.transaction
            if linked_txn.classification == TransactionClassification.DEBT_COLLECTION:
                linked_txn.classification = TransactionClassification.INCOME
            elif linked_txn.classification == TransactionClassification.LOAN_REPAYMENT:
                linked_txn.classification = TransactionClassification.EXPENSE
        
        db.delete(entry)
    
    # Revert classification
    if txn.classification in [TransactionClassification.SPLIT_PAYMENT, TransactionClassification.LEND]:
        txn.classification = TransactionClassification.EXPENSE
    elif txn.classification == TransactionClassification.BORROW:
        txn.classification = TransactionClassification.INCOME
    elif txn.classification == TransactionClassification.INSTALLMENT:
        txn.classification = TransactionClassification.EXPENSE
        txn.direction = TransactionDirection.OUTFLOW
        
    db.commit()
    return True


def update_linked_entry(
    db: Session, entry_id: int, update_data: LinkedEntryUpdate
) -> LinkedEntry | None:
    """Update a linked entry."""
    entry = get_linked_entry(db, entry_id)
    if not entry:
        return None
        
    # Update simple fields
    if update_data.counterparty_name is not None:
        entry.counterparty_name = update_data.counterparty_name
        
    if update_data.notes is not None:
        entry.notes = update_data.notes
        
    # Handle amount update for Split Payments
    if update_data.user_amount is not None and entry.link_type == LinkType.SPLIT_PAYMENT:
        if update_data.user_amount > entry.total_amount:
            raise LinkedEntryError("User amount cannot exceed total transaction amount")
            
        # Recalculate pending amount
        # Formula: Pending = Total - User Share - Amount Already Settled
        settled_amount = sum(link.amount for link in entry.linked_transactions)
        new_pending = entry.total_amount - update_data.user_amount - settled_amount
        
        if new_pending < 0:
            raise LinkedEntryError(f"User amount too high (would result in negative pending amount: {new_pending})")
            
        entry.user_amount = update_data.user_amount
        entry.pending_amount = new_pending
        
        # Update status
        if entry.pending_amount == Decimal("0.00"):
            entry.status = LinkStatus.SETTLED
        elif settled_amount > 0:
            entry.status = LinkStatus.PARTIAL
        else:
            entry.status = LinkStatus.PENDING

    db.commit()
    db.refresh(entry)
    return entry
