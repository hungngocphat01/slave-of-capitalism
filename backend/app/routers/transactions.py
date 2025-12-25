"""Transaction API router with updated model."""
from datetime import date
from decimal import Decimal

from typing import Union, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.transaction import (
    TransactionCreate,
    TransactionResponse,
    TransactionUpdate,
    TransactionWithDetails,
    ReclassifyRequest,
    WalletTransferRequest,
    WalletTransferResponse,
    BulkActionRequest,
    BulkLinkRequest,
    TransactionMergeRequest,
    BulkImportRequest
)
from app.models.transaction import TransactionDirection, TransactionClassification, Transaction
from app.models.linked_entry import LinkType
from app.services import transaction_service, linked_entry_service
from app.schemas.linked_entry import (
    LinkedEntryCreate,
    LinkedEntryResponse,
    MarkAsSplitRequest,
    MarkAsLoanRequest,
    MarkAsDebtRequest,
)

router = APIRouter()


@router.post("/bulk-import", status_code=status.HTTP_201_CREATED)
def bulk_import(request: BulkImportRequest, db: Session = Depends(get_db)):
    """
    Bulk import transactions and transfers.
    
    Atomic operation: all or nothing.
    """
    try:
        count = 0
        for item in request.items:
            # Helper to distinguish types safely
            # WalletTransferRequest has 'from_wallet_id'
            # TransactionCreate has 'wallet_id'
            
            if hasattr(item, "from_wallet_id"):
                 # It's a transfer
                 transaction_service.create_wallet_transfer(db, item, commit=False)
            else:
                 # It's a transaction
                 transaction_service.create_transaction(db, item, commit=False)
            count += 1
            
        db.commit()
        return {"imported_count": count, "message": "Import successful"}
        
    except Exception as e:
        db.rollback()
        # Log the error potentially?
        print(f"Bulk import failed: {e}")
        raise HTTPException(status_code=400, detail=f"Import failed: {str(e)}")


@router.get("/", response_model=list[TransactionWithDetails])
def list_transactions(
    skip: int = 0,
    limit: int = 1000,
    wallet_id: int | None = Query(None, description="Filter by wallet ID"),
    category_id: int | None = Query(None, description="Filter by category ID"),
    month: Optional[str] = Query(None, description="Filter by month (YYYY-MM-DD)"),
    direction: TransactionDirection | None = Query(None, description="Filter by direction"),
    classification: TransactionClassification | None = Query(None, description="Filter by classification"),
    db: Session = Depends(get_db),
):
    """List transactions with optional filtering."""
    month_date = None
    if month:
        from datetime import date as dt_date # avoid conflict if needed, or use date.fromisoformat
        # Actually 'date' is imported.
        try:
             month_date = date.fromisoformat(month)
        except ValueError:
             # If invalid format, maybe raise 422? Or let service decide? 
             # FastAPI would handle validation for `date` type, but for `str` we do it.
             raise HTTPException(status_code=422, detail="Invalid date format. Use YYYY-MM-DD")

    transactions = transaction_service.get_transactions(
        db, skip=skip, limit=limit, wallet_id=wallet_id, category_id=category_id,
        month=month_date, direction=direction, classification=classification
    )
    
    # Enrich with details
    enriched = []
    for txn in transactions:
        txn_dict = TransactionResponse.model_validate(txn).model_dump()
        txn_dict["wallet_name"] = txn.wallet.name if txn.wallet else None
        txn_dict["wallet_type"] = txn.wallet.wallet_type.value if txn.wallet else None
        txn_dict["category_name"] = txn.category.name if txn.category else None
        txn_dict["subcategory_name"] = txn.subcategory.name if txn.subcategory else None
        txn_dict["has_linked_entry"] = txn.linked_entry_primary is not None
        txn_dict["is_linked_to_entry"] = len(txn.linked_transactions) > 0
        if txn.linked_entry_primary:
            entry_dict = LinkedEntryResponse.model_validate(txn.linked_entry_primary).model_dump()
            # Populate linked transactions
            entry_dict["linked_transactions"] = [
                {
                    "id": lt.id,
                    "linked_entry_id": lt.linked_entry_id,
                    "transaction_id": lt.transaction_id,
                    "amount": lt.amount,
                    "created_at": lt.created_at,
                    "date": lt.transaction.date if lt.transaction else None,
                    "description": lt.transaction.description if lt.transaction else None
                }
                for lt in txn.linked_entry_primary.linked_transactions
            ]
            txn_dict["linked_entry"] = entry_dict
        enriched.append(TransactionWithDetails(**txn_dict))
    
    return enriched


@router.get("/{transaction_id}", response_model=TransactionWithDetails)
def get_transaction(transaction_id: int, db: Session = Depends(get_db)):
    """Get a specific transaction by ID."""
    txn = transaction_service.get_transaction(db, transaction_id)
    if not txn:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} not found"
        )
    
    
    txn_dict = TransactionResponse.model_validate(txn).model_dump()
    txn_dict["wallet_name"] = txn.wallet.name if txn.wallet else None
    txn_dict["wallet_type"] = txn.wallet.wallet_type.value if txn.wallet else None
    txn_dict["category_name"] = txn.category.name if txn.category else None
    txn_dict["subcategory_name"] = txn.subcategory.name if txn.subcategory else None
    txn_dict["has_linked_entry"] = txn.linked_entry_primary is not None
    txn_dict["is_linked_to_entry"] = len(txn.linked_transactions) > 0
    if txn.linked_entry_primary:
        txn_dict["linked_entry"] = LinkedEntryResponse.model_validate(txn.linked_entry_primary).model_dump()
    
    return TransactionWithDetails(**txn_dict)


@router.post("/", response_model=TransactionResponse, status_code=status.HTTP_201_CREATED)
def create_transaction(transaction: TransactionCreate, db: Session = Depends(get_db)):
    """Create a new transaction."""
    db_transaction = transaction_service.create_transaction(db, transaction)
    return TransactionResponse.model_validate(db_transaction)


@router.delete("/", status_code=status.HTTP_204_NO_CONTENT)
def delete_transactions(request: BulkActionRequest, db: Session = Depends(get_db)):
    """
    Delete multiple transactions.
    
    This is an atomic operation: either all transactions are deleted, or none are.
    """
    transaction_service.delete_transactions(db, request.transaction_ids)
    return None


@router.post("/ignore", status_code=status.HTTP_204_NO_CONTENT)
def ignore_transactions(request: BulkActionRequest, db: Session = Depends(get_db)):
    """
    Ignore multiple transactions.
    
    Ignored transactions are excluded from all calculations but remain in the database.
    This operation is atomic.
    """
    transaction_service.ignore_transactions(db, request.transaction_ids)
    return None


@router.post("/unignore", status_code=status.HTTP_204_NO_CONTENT)
def unignore_transactions(request: BulkActionRequest, db: Session = Depends(get_db)):
    """
    Un-ignore multiple transactions.
    
    Restores transactions to be included in calculations.
    This operation is atomic.
    """
    transaction_service.unignore_transactions(db, request.transaction_ids)
    return None


@router.post("/{transaction_id}/unlink", status_code=status.HTTP_204_NO_CONTENT)
def unlink_single_transaction(transaction_id: int, db: Session = Depends(get_db)):
    """
    Unlink a transaction from any linked entry.
    """
    success = linked_entry_service.unlink_transaction_by_id(db, transaction_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} is not linked to any entry"
        )
    return None


@router.post("/link", response_model=LinkedEntryResponse)
def link_transactions(request: BulkLinkRequest, db: Session = Depends(get_db)):
    """
    Link multiple transactions to an entry.

    Useful for linking multiple partial payments to a single debt/split.
    Validates that:
    - All transaction types match the entry type.
    - Total amount does not exceed the pending amount.
    """
    try:
        entry = linked_entry_service.link_transactions(
            db, request.linked_entry_id, request.transaction_ids
        )
        return LinkedEntryResponse.model_validate(entry)
    except linked_entry_service.LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.put("/{transaction_id}", response_model=TransactionResponse)
def update_transaction(
    transaction_id: int, transaction: TransactionUpdate, db: Session = Depends(get_db)
):
    """Update an existing transaction (for inline editing)."""
    db_transaction = transaction_service.update_transaction(db, transaction_id, transaction)
    if not db_transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} not found"
        )
    return TransactionResponse.model_validate(db_transaction)


@router.post("/{transaction_id}/reclassify", response_model=TransactionResponse)
def reclassify_transaction(
    transaction_id: int, request: ReclassifyRequest, db: Session = Depends(get_db)
):
    """Reclassify a transaction (useful after CSV import)."""
    db_transaction = transaction_service.reclassify_transaction(
        db, transaction_id, request.classification
    )
    if not db_transaction:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} not found"
        )
    return TransactionResponse.model_validate(db_transaction)


@router.delete("/{transaction_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_single_transaction(transaction_id: int, db: Session = Depends(get_db)):
    """Delete a transaction."""
    deleted = transaction_service.delete_transaction(db, transaction_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} not found"
        )
    return None


@router.get("/monthly-summary/", response_model=dict)
def get_monthly_summary(
    month: str = Query(..., description="Month to summarize (YYYY-MM-DD)"),
    db: Session = Depends(get_db),
):
    """Get monthly expense summary."""
    try:
        from datetime import date as dt_date
        month_date = dt_date.fromisoformat(month)
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid date format. Use YYYY-MM-DD")

    total_expense = transaction_service.calculate_monthly_expense(db, month_date)
    category_breakdown = transaction_service.calculate_category_breakdown(db, month_date)
    
    return {
        "month": month_date.strftime("%Y-%m"),
        "total_expense": float(total_expense),
        "category_breakdown": {
            cat: float(amount) for cat, amount in category_breakdown.items()
        },
    }


@router.post("/wallet-transfer", response_model=WalletTransferResponse, status_code=status.HTTP_201_CREATED)
def create_wallet_transfer(request: WalletTransferRequest, db: Session = Depends(get_db)):
    """
    Create a wallet transfer (paired transactions).
    
    Creates two transactions:
    - OUTFLOW from source wallet
    - INFLOW to destination wallet
    Both linked via paired_transaction_id.
    """
    """
    Create a wallet transfer (paired transactions).
    
    Creates two transactions:
    - OUTFLOW from source wallet
    - INFLOW to destination wallet
    Both linked via paired_transaction_id.
    """
    return transaction_service.create_wallet_transfer(db, request)


@router.post(
    "/{transaction_id}/mark-split",
    response_model=LinkedEntryResponse,
    summary="Mark transaction as split payment",
    description="""
    Marks an OUTFLOW transaction as a split payment where you paid for others.
    
    **What it does:**
    - Changes transaction classification to SPLIT_PAYMENT
    - Creates a LinkedEntry tracking who owes you money
    - Calculates pending_amount = total_amount - user_amount
    - Only your share (user_amount) counts toward monthly expenses
    
    **Example:** You paid ¥3,000 for dinner with Bob. Your share is ¥1,500.
    - total_amount: ¥3,000 (what you paid)
    - user_amount: ¥1,500 (your share)
    - pending_amount: ¥1,500 (Bob owes you)
    """,
    responses={
        200: {"description": "Split payment created successfully"},
        400: {"description": "Invalid request (e.g., not an OUTFLOW, user_amount > total, already linked)"},
        404: {"description": "Transaction not found"}
    }
)
def mark_transaction_as_split(
    transaction_id: int, request: MarkAsSplitRequest, db: Session = Depends(get_db)
):
    """
    Mark a transaction as a split payment.
    
    Args:
        transaction_id: ID of the transaction to mark
        request: Contains counterparty_name, user_amount, and optional notes
    
    Returns:
        LinkedEntryResponse: The created linked entry with pending amount
    """
    try:
        return transaction_service.mark_as_split(db, transaction_id, request)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except linked_entry_service.LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.post(
    "/{transaction_id}/mark-loan",
    response_model=LinkedEntryResponse,
    summary="Mark transaction as loan",
    description="""
    Marks an OUTFLOW transaction as a loan where you lent money to someone.
    
    **What it does:**
    - Changes transaction classification from EXPENSE to LEND
    - Creates a LinkedEntry tracking the loan
    - Sets pending_amount = total_amount (full amount is owed)
    - Does NOT count toward monthly expenses (lending is not spending)
    
    **Example:** You lent Bob ¥5,000.
    - total_amount: ¥5,000
    - pending_amount: ¥5,000 (Bob owes you the full amount)
    - Supports partial repayments via /linked-entries/{id}/link
    """,
    responses={
        200: {"description": "Loan created successfully"},
        400: {"description": "Invalid request (e.g., not an OUTFLOW, already linked)"},
        404: {"description": "Transaction not found"}
    }
)
def mark_transaction_as_loan(
    transaction_id: int, request: MarkAsLoanRequest, db: Session = Depends(get_db)
):
    """
    Mark a transaction as a loan.
    
    Args:
        transaction_id: ID of the transaction to mark
        request: Contains counterparty_name and optional notes
    
    Returns:
        LinkedEntryResponse: The created linked entry
    """
    try:
        return transaction_service.mark_as_loan(db, transaction_id, request)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except linked_entry_service.LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.post(
    "/{transaction_id}/mark-debt",
    response_model=LinkedEntryResponse,
    summary="Mark transaction as debt",
    description="""
    Marks an INFLOW transaction as a debt where someone lent you money.
    
    **What it does:**
    - Changes transaction classification from INCOME to BORROW
    - Creates a LinkedEntry tracking the debt
    - Sets pending_amount = total_amount (full amount you owe)
    - Does NOT count toward monthly income (borrowing is not earning)
    
    **Example:** Alice lent you ¥10,000.
    - total_amount: ¥10,000
    - pending_amount: ¥10,000 (you owe Alice the full amount)
    - Supports partial repayments via /linked-entries/{id}/link
    """,
    responses={
        200: {"description": "Debt created successfully"},
        400: {"description": "Invalid request (e.g., not an INFLOW, already linked)"},
        404: {"description": "Transaction not found"}
    }
)
def mark_transaction_as_debt(
    transaction_id: int, request: MarkAsDebtRequest, db: Session = Depends(get_db)
):
    """
    Mark a transaction as a debt.
    
    Args:
        transaction_id: ID of the transaction to mark
        request: Contains counterparty_name and optional notes
    
    Returns:
        LinkedEntryResponse: The created linked entry
    """
    try:
        return transaction_service.mark_as_debt(db, transaction_id, request)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except linked_entry_service.LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.post(
    "/{transaction_id}/mark-installment",
    response_model=LinkedEntryResponse,
    summary="Mark transaction as installment",
    description="""
    Marks an OUTFLOW transaction as an installment plan for a credit card purchase.
    
    **What it does:**
    - Changes transaction classification to INSTALLMENT (placeholder)
    - Creates a LinkedEntry tracking the installment plan
    - Sets pending_amount = total_amount (unrealized charges)
    - Does NOT count toward current balance (placeholder only)
    - Reserves credit limit but doesn't increase debt
    
    **Example:** ¥30,000 laptop paid over 3 months.
    - total_amount: ¥30,000 (placeholder)
    - pending_amount: ¥30,000 (to be charged later)
    - Each ¥10,000 charge links to this entry as INSTALLMT_CHRGE
    - Only actual charges count toward monthly expenses
    """,
    responses={
        200: {"description": "Installment plan created successfully"},
        400: {"description": "Invalid request (e.g., not an OUTFLOW, already linked)"},
        404: {"description": "Transaction not found"}
    }
)
def mark_transaction_as_installment(
    transaction_id: int, request: MarkAsLoanRequest, db: Session = Depends(get_db)
):
    """
    Mark a transaction as an installment plan.
    
    Args:
        transaction_id: ID of the transaction to mark
        request: Contains counterparty_name and optional notes
    
    Returns:
        LinkedEntryResponse: The created linked entry
    """
    try:
        return transaction_service.mark_as_installment(db, transaction_id, request)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except linked_entry_service.LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.post(
    "/{transaction_id}/unclassify",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Unclassify a transaction",
    description="""
    Removes split/loan/debt classification from a transaction and reverts it to standard EXPENSE or INCOME.
    
    **What it does:**
    - Deletes the associated LinkedEntry (and all linked transactions)
    - Reverts classification:
      - SPLIT_PAYMENT/LEND → EXPENSE
      - BORROW → INCOME
    - Reverts any linked reimbursement transactions:
      - DEBT_COLLECTION → INCOME
      - LOAN_REPAYMENT → EXPENSE
    
    **Use case:** You mistakenly marked a transaction as a split/loan/debt and want to undo it.
    
    **Warning:** This will unlink all associated reimbursement/repayment transactions!
    """,
    responses={
        204: {"description": "Transaction unclassified successfully"},
        404: {"description": "Transaction not found"}
    }
)
def unclassify_transaction_endpoint(
    transaction_id: int, db: Session = Depends(get_db)
):
    """
    Unclassify a transaction and revert it to standard EXPENSE/INCOME.
    
    Args:
        transaction_id: ID of the transaction to unclassify
    
    Returns:
        None (204 No Content)
    """
    success = linked_entry_service.unclassify_transaction(db, transaction_id)
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Transaction {transaction_id} not found"
        )
    return None


@router.post("/merge", response_model=TransactionResponse, status_code=status.HTTP_201_CREATED)
def merge_transactions(request: TransactionMergeRequest, db: Session = Depends(get_db)):
    """
    Merge multiple transactions into a single transaction.
    
    Combines amounts, deletes original transactions, and creates a new one.
    """
    try:
        new_txn = transaction_service.merge_transactions(db, request)
        return TransactionResponse.model_validate(new_txn)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
