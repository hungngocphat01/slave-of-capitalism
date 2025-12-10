"""Additional transaction endpoints for ignore and calibration features."""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.transaction import TransactionCreate, TransactionResponse
from app.services import transaction_service

router = APIRouter()


class ResolveCalibrationRequest(BaseModel):
    """Request to resolve a calibration transaction."""
    new_transaction: TransactionCreate


class ResolveCalibrationResponse(BaseModel):
    """Response for resolving a calibration."""
    new_transaction: TransactionResponse
    calibration_deleted: bool
    updated_calibration: TransactionResponse | None = None


@router.post(
    "/{transaction_id}/resolve",
    response_model=ResolveCalibrationResponse,
    summary="Resolve a calibration transaction",
    description="""
    Resolve a calibration by creating the actual transaction that caused the discrepancy.
    
    **What it does:**
    - Verifies the transaction is a calibration (is_calibration=True)
    - Creates the new transaction you provide
    - Adjusts the calibration amount to maintain wallet balance:
      - Same direction: calibration -= new_amount
      - Opposite direction: calibration += new_amount
    - If calibration amount becomes ≤0, deletes the calibration
    
    **Example:** You calibrated wallet with +¥2000. Later you remember it was a ¥1500 income
    you forgot. Resolve with the ¥1500 income transaction, and calibration adjusts to ¥500.
    
    **Use case:** When you remember what caused the wallet balance discrepancy.
    
    **Note:** Only available for calibration transactions (is_calibration=True).
    """,
    responses={
        200: {"description": "Calibration resolved successfully"},
        400: {"description": "Transaction is not a calibration"},
        404: {"description": "Transaction not found"}
    }
)
def resolve_calibration_endpoint(
    transaction_id: int,
    request: ResolveCalibrationRequest,
    db: Session = Depends(get_db)
) -> ResolveCalibrationResponse:
    """
    Resolve a calibration transaction.
    
    Only works on transactions where is_calibration=True.
    
    Args:
        transaction_id: ID of the calibration transaction
        request: New transaction data
    
    Returns:
        Result with new transaction and calibration status
    """
    try:
        result = transaction_service.resolve_calibration(
            db, transaction_id, request.new_transaction
        )
        
        return ResolveCalibrationResponse(
            new_transaction=TransactionResponse.model_validate(result.new_transaction),
            calibration_deleted=result.calibration_deleted,
            updated_calibration=(
                TransactionResponse.model_validate(result.updated_calibration)
                if result.updated_calibration else None
            )
        )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
