"""Linked entry API router for splits, loans, and debts."""
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.linked_entry import LinkType, LinkStatus
from app.schemas.linked_entry import (
    LinkedEntryCreate,
    LinkedEntryResponse,
    LinkedEntryWithDetails,
    LinkTransactionRequest,
    LinkedTransactionResponse,
    LinkedEntryUpdate,
)
from app.services.linked_entry_service import LinkedEntryError
from app.services import linked_entry_service

router = APIRouter()


@router.get("/", response_model=list[LinkedEntryWithDetails])
def list_linked_entries(
    link_type: LinkType | None = Query(None, description="Filter by link type"),
    status_filter: LinkStatus | None = Query(None, alias="status", description="Filter by status"),
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
):
    """List all linked entries with optional filtering."""
    entries = linked_entry_service.get_linked_entries(
        db, link_type=link_type, status=status_filter, skip=skip, limit=limit
    )
    
    # Enrich with details
    enriched = []
    for entry in entries:
        entry_dict = LinkedEntryResponse.model_validate(entry).model_dump()
        
        # Add primary transaction details
        if entry.primary_transaction:
            entry_dict["primary_transaction_description"] = entry.primary_transaction.description
            entry_dict["primary_transaction_date"] = entry.primary_transaction.date.isoformat()
        
        # Add linked transactions
        entry_dict["linked_transactions"] = []
        for lt in entry.linked_transactions:
            lt_dict = LinkedTransactionResponse.model_validate(lt).model_dump()
            if lt.transaction:
                lt_dict["date"] = lt.transaction.date
                lt_dict["description"] = lt.transaction.description
            entry_dict["linked_transactions"].append(lt_dict)
        
        # Calculate settled amount
        settled = sum(lt.amount for lt in entry.linked_transactions)
        entry_dict["settled_amount"] = settled
        
        enriched.append(LinkedEntryWithDetails(**entry_dict))
    
    return enriched


@router.get("/pending", response_model=list[LinkedEntryWithDetails])
def list_pending_entries(db: Session = Depends(get_db)):
    """Get all pending and partial entries (for linking UI)."""
    entries = linked_entry_service.get_pending_entries(db)
    
    # Enrich with details
    enriched = []
    for entry in entries:
        entry_dict = LinkedEntryResponse.model_validate(entry).model_dump()
        
        if entry.primary_transaction:
            entry_dict["primary_transaction_description"] = entry.primary_transaction.description
            entry_dict["primary_transaction_date"] = entry.primary_transaction.date.isoformat()
        
        entry_dict["linked_transactions"] = []
        for lt in entry.linked_transactions:
            lt_dict = LinkedTransactionResponse.model_validate(lt).model_dump()
            if lt.transaction:
                lt_dict["date"] = lt.transaction.date
                lt_dict["description"] = lt.transaction.description
            entry_dict["linked_transactions"].append(lt_dict)
        
        settled = sum(lt.amount for lt in entry.linked_transactions)
        entry_dict["settled_amount"] = settled
        
        enriched.append(LinkedEntryWithDetails(**entry_dict))
    
    return enriched


@router.get("/{entry_id}", response_model=LinkedEntryWithDetails)
def get_linked_entry(entry_id: int, db: Session = Depends(get_db)):
    """Get a specific linked entry by ID."""
    entry = linked_entry_service.get_linked_entry(db, entry_id)
    if not entry:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Linked entry {entry_id} not found"
        )
    
    entry_dict = LinkedEntryResponse.model_validate(entry).model_dump()
    
    if entry.primary_transaction:
        entry_dict["primary_transaction_description"] = entry.primary_transaction.description
        entry_dict["primary_transaction_date"] = entry.primary_transaction.date.isoformat()
    
    entry_dict["linked_transactions"] = []
    for lt in entry.linked_transactions:
        lt_dict = LinkedTransactionResponse.model_validate(lt).model_dump()
        if lt.transaction:
            lt_dict["date"] = lt.transaction.date
            lt_dict["description"] = lt.transaction.description
        entry_dict["linked_transactions"].append(lt_dict)
    
    settled = sum(lt.amount for lt in entry.linked_transactions)
    entry_dict["settled_amount"] = settled
    
    return LinkedEntryWithDetails(**entry_dict)


@router.post("/", response_model=LinkedEntryResponse, status_code=status.HTTP_201_CREATED)
def create_linked_entry(entry: LinkedEntryCreate, db: Session = Depends(get_db)):
    """Create a new linked entry (split payment, loan, or debt)."""
    try:
        db_entry = linked_entry_service.create_linked_entry(db, entry)
        return LinkedEntryResponse.model_validate(db_entry)
    except LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.post(
    "/{entry_id}/link",
    response_model=LinkedEntryResponse,
    summary="Link a reimbursement/repayment transaction to an entry",
    description="""
    Links an existing transaction to a LinkedEntry as a reimbursement or repayment.
    
    **What it does:**
    - Links the transaction to the entry (creates a LinkedTransaction record)
    - Deducts the transaction amount from pending_amount
    - Updates entry status (PENDING → PARTIAL → SETTLED)
    - Auto-converts transaction classification:
      - INCOME → DEBT_COLLECTION (for split/loan reimbursements)
      - EXPENSE → LOAN_REPAYMENT (for debt repayments)
    
    **The amount is automatically derived from the transaction** - no need to specify it separately.
    
    **Example:** Bob owes you ¥1,500 from a split payment. He sends you ¥1,500.
    1. Create the INFLOW transaction (¥1,500, INCOME)
    2. Link it to the split payment entry
    3. System automatically:
       - Changes transaction to DEBT_COLLECTION
       - Reduces pending_amount from ¥1,500 to ¥0
       - Marks entry as SETTLED
    
    **Supports partial repayments:** If Bob only sends ¥500, pending_amount becomes ¥1,000 and status becomes PARTIAL.
    """,
    responses={
        200: {"description": "Transaction linked successfully, entry updated"},
        400: {"description": "Invalid request (e.g., amount exceeds pending, transaction already linked, wrong direction)"},
        404: {"description": "Entry or transaction not found"}
    }
)
def link_transaction_to_entry(
    entry_id: int, request: LinkTransactionRequest, db: Session = Depends(get_db)
):
    """
    Link a transaction to an entry as reimbursement/repayment.
    
    Args:
        entry_id: ID of the LinkedEntry to link to
        request: Contains transaction_id (amount is derived from transaction)
    
    Returns:
        LinkedEntryResponse: Updated entry with new pending_amount and status
    """
    try:
        db_entry = linked_entry_service.link_transaction(
            db, entry_id, request.transaction_id
        )
        return LinkedEntryResponse.model_validate(db_entry)
    except LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.put("/{entry_id}", response_model=LinkedEntryResponse)
def update_linked_entry(
    entry_id: int, entry: LinkedEntryUpdate, db: Session = Depends(get_db)
):
    """Update a linked entry (e.g. counterparty name, notes, user amount)."""
    try:
        updated_entry = linked_entry_service.update_linked_entry(db, entry_id, entry)
        if not updated_entry:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Linked entry {entry_id} not found"
            )
        return LinkedEntryResponse.model_validate(updated_entry)
    except LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
@router.delete("/{entry_id}/unlink/{link_id}", response_model=LinkedEntryResponse)
def unlink_transaction_from_entry(
    entry_id: int, link_id: int, db: Session = Depends(get_db)
):
    """Unlink a transaction from an entry."""
    try:
        db_entry = linked_entry_service.unlink_transaction(db, link_id)
        if db_entry.id != entry_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Link {link_id} does not belong to entry {entry_id}"
            )
        return LinkedEntryResponse.model_validate(db_entry)
    except LinkedEntryError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.delete("/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_linked_entry(entry_id: int, db: Session = Depends(get_db)):
    """Delete a linked entry and all its links."""
    deleted = linked_entry_service.delete_linked_entry(db, entry_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Linked entry {entry_id} not found"
        )
    return None


@router.get("/summary/owed", response_model=dict)
def get_owed_summary(db: Session = Depends(get_db)):
    """Get total amount owed to user (pending splits and loans)."""
    total_owed = linked_entry_service.calculate_total_owed(db)
    pending_entries = linked_entry_service.get_pending_entries(db)
    
    # Filter to only splits and loans
    owed_entries = [e for e in pending_entries if e.link_type in [LinkType.SPLIT_PAYMENT, LinkType.LOAN]]
    
    return {
        "total_owed": float(total_owed),
        "pending_count": len(owed_entries),
    }


@router.get("/summary/debt", response_model=dict)
def get_debt_summary(db: Session = Depends(get_db)):
    """Get total amount user owes (pending debts)."""
    total_debt = linked_entry_service.calculate_total_debt(db)
    pending_entries = linked_entry_service.get_pending_entries(db)
    
    # Filter to only debts
    debt_entries = [e for e in pending_entries if e.link_type == LinkType.DEBT]
    
    return {
        "total_debt": float(total_debt),
        "pending_count": len(debt_entries),
    }
