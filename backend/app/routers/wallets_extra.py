"""Additional wallet endpoints for calibration feature."""
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.transaction import TransactionResponse
from app.services import wallet_service

router = APIRouter()


class CalibrateWalletRequest(BaseModel):
    """Request to calibrate a wallet balance."""
    correct_balance: Decimal = Field(..., description="What the balance should actually be")
    misc_category_id: int = Field(..., gt=0, description="ID of Miscellaneous category for calibration transaction")


@router.post(
    "/{wallet_id}/calibrate",
    response_model=TransactionResponse,
    summary="Calibrate wallet balance",
    description="""
    Create a calibration transaction to fix wallet balance discrepancies.
    
    **What it does:**
    - Calculates difference between current and correct balance
    - Creates a calibration transaction (is_calibration=True):
      - If difference > 0: INFLOW/INCOME transaction
      - If difference < 0: OUTFLOW/EXPENSE transaction
    - Description is set to "CALIBRATION"
    - Assigned to Miscellaneous category
    - Marked with special calibration flag
    
    **Use case:** When your actual wallet balance doesn't match the calculated balance
    (e.g., forgot to record transactions, cash discrepancy).
    
    **Example:** Wallet shows ¥10,000 but you actually have ¥12,000. Calibrate with
    correct_balance=12000 to create a +¥2,000 calibration transaction.
    
    **Note:** You can later "resolve" the calibration when you remember what caused
    the discrepancy using the /transactions/{id}/resolve endpoint.
    """,
    responses={
        200: {"description": "Calibration transaction created successfully"},
        400: {"description": "Wallet balance is already correct or invalid data"},
        404: {"description": "Wallet or category not found"}
    }
)
def calibrate_wallet_endpoint(
    wallet_id: int,
    request: CalibrateWalletRequest,
    db: Session = Depends(get_db)
) -> TransactionResponse:
    """
    Calibrate a wallet's balance.
    
    Args:
        wallet_id: ID of the wallet to calibrate
        request: Calibration request with correct balance and category
    
    Returns:
        Created calibration transaction
    """
    try:
        calibration = wallet_service.calibrate_wallet(
            db,
            wallet_id,
            request.correct_balance,
            request.misc_category_id
        )
        return TransactionResponse.model_validate(calibration)
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
