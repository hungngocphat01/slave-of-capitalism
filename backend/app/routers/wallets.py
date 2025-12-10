"""Wallet API router."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.wallet import (
    WalletCreate,
    WalletResponse,
    WalletUpdate,
    WalletWithBalance,
)
from app.services import wallet_service

router = APIRouter()


@router.get("/", response_model=list[WalletWithBalance])
def list_wallets(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """List all wallets with current balances."""
    from app.models.wallet import WalletType
    
    wallets = wallet_service.get_wallets(db, skip=skip, limit=limit)
    
    # Enrich with current balance and available credit (for credit wallets)
    wallets_with_balance = []
    for wallet in wallets:
        balance = wallet_service.calculate_wallet_balance(db, wallet.id)
        wallet_dict = WalletResponse.model_validate(wallet).model_dump()
        wallet_dict["current_balance"] = balance
        
        # For credit wallets, calculate available credit
        if wallet.wallet_type == WalletType.CREDIT:
            wallet_dict["available_credit"] = wallet.credit_limit - balance
        else:
            wallet_dict["available_credit"] = None
        
        wallets_with_balance.append(WalletWithBalance(**wallet_dict))
    
    return wallets_with_balance


@router.get("/{wallet_id}", response_model=WalletWithBalance)
def get_wallet(wallet_id: int, db: Session = Depends(get_db)):
    """Get a specific wallet by ID."""
    from app.models.wallet import WalletType
    
    wallet = wallet_service.get_wallet(db, wallet_id)
    if not wallet:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Wallet {wallet_id} not found"
        )
    
    balance = wallet_service.calculate_wallet_balance(db, wallet.id)
    wallet_dict = WalletResponse.model_validate(wallet).model_dump()
    wallet_dict["current_balance"] = balance
    
    # For credit wallets, calculate available credit
    if wallet.wallet_type == WalletType.CREDIT:
        wallet_dict["available_credit"] = wallet.credit_limit - balance
    else:
        wallet_dict["available_credit"] = None
    
    return WalletWithBalance(**wallet_dict)


@router.post("/", response_model=WalletResponse, status_code=status.HTTP_201_CREATED)
def create_wallet(wallet: WalletCreate, db: Session = Depends(get_db)):
    """Create a new wallet."""
    try:
        db_wallet = wallet_service.create_wallet(db, wallet)
        return WalletResponse.model_validate(db_wallet)
    except Exception as e:
        # Handle unique constraint violation
        if "UNIQUE constraint failed" in str(e):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Wallet with name '{wallet.name}' already exists"
            )
        raise


@router.put("/{wallet_id}", response_model=WalletResponse)
def update_wallet(wallet_id: int, wallet: WalletUpdate, db: Session = Depends(get_db)):
    """Update an existing wallet."""
    db_wallet = wallet_service.update_wallet(db, wallet_id, wallet)
    if not db_wallet:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Wallet {wallet_id} not found"
        )
    return WalletResponse.model_validate(db_wallet)


@router.delete("/{wallet_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_wallet(wallet_id: int, db: Session = Depends(get_db)):
    """Delete a wallet."""
    try:
        deleted = wallet_service.delete_wallet(db, wallet_id)
        if not deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Wallet {wallet_id} not found"
            )
        return None
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.post(
    "/transfer",
    response_model=dict,
    summary="Create a wallet-to-wallet transfer",
    description="""
    Creates a transfer between two wallets by creating two paired transactions:
    - An OUTFLOW transaction from the source wallet with description "Transfer → {destination}"
    - An INFLOW transaction to the destination wallet with description "Transfer ← {source}"
    
    The transactions are linked via paired_transaction_id to maintain referential integrity.
    
    **Note**: This does NOT affect monthly expense calculations as TRANSFER transactions are excluded.
    """,
    responses={
        200: {
            "description": "Transfer created successfully",
            "content": {
                "application/json": {
                    "example": {
                        "from": {
                            "id": 1,
                            "date": "2025-12-07",
                            "wallet_id": 1,
                            "direction": "outflow",
                            "amount": 10000,
                            "classification": "transfer",
                            "description": "Transfer → Cash"
                        },
                        "to": {
                            "id": 2,
                            "date": "2025-12-07",
                            "wallet_id": 2,
                            "direction": "inflow",
                            "amount": 10000,
                            "classification": "transfer",
                            "description": "Transfer ← Bank Account"
                        }
                    }
                }
            }
        },
        400: {"description": "Missing required fields or invalid data"},
        404: {"description": "Source or destination wallet not found"}
    }
)
def create_transfer(transfer_data: dict, db: Session = Depends(get_db)):
    """
    Create a transfer between two wallets.
    
    Args:
        transfer_data: Dictionary containing:
            - from_wallet_id (int): Source wallet ID
            - to_wallet_id (int): Destination wallet ID
            - amount (float): Amount to transfer
            - date (str): Transfer date in ISO format (YYYY-MM-DD)
            - time (str, optional): Transfer time in ISO format (HH:MM:SS)
            - description (str, optional): Custom description (defaults to auto-generated with arrows)
    
    Returns:
        dict: Contains "from" and "to" transaction objects
    
    Example:
        ```json
        {
            "from_wallet_id": 1,
            "to_wallet_id": 2,
            "amount": 10000,
            "date": "2025-12-07",
            "description": "Transfer"
        }
        ```
    """
    from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
    from app.schemas.transaction import TransactionResponse
    from datetime import date as date_type, time as time_type
    
    from app.services import transaction_service
    from app.schemas.transaction import WalletTransferRequest

    # Validate required fields
    required_fields = ["from_wallet_id", "to_wallet_id", "amount", "date"]
    for field in required_fields:
        if field not in transfer_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Missing required field: {field}"
            )
            
    # Parse into request object
    try:
        request = WalletTransferRequest(
            from_wallet_id=transfer_data["from_wallet_id"],
            to_wallet_id=transfer_data["to_wallet_id"],
            amount=transfer_data["amount"],
            date=transfer_data["date"],
            time=transfer_data.get("time"),
            description=transfer_data.get("description", "Transfer")
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid data: {str(e)}"
        )
        
    # Delegate to service
    try:
        response = transaction_service.create_wallet_transfer(db, request)
        return {
            "from": response.outflow_transaction,
            "to": response.inflow_transaction
        }
    except Exception as e:
        # Check if wallet not found error (which might come from foreign key constraints or service checks)
        # The service doesn't explicitly check existence, but DB will raise error if FK fails.
        # Ideally service should check.
        # But let's handle general errors.
        if "Foreign key constraint failed" in str(e) or "constraint failed" in str(e):
             raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="One of the wallets was not found"
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


