import pytest
from decimal import Decimal
from datetime import date
from sqlalchemy.orm import Session
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.wallet import Wallet, WalletType
from app.schemas.transaction import TransactionCreate
from app.services.transaction_service import resolve_calibration

def test_resolve_calibration_enforces_same_wallet(test_db: Session):
    """Test that resolving a calibration forces using the same wallet ID."""
    # 1. Create two wallets
    wallet1 = Wallet(name="Wallet 1", wallet_type=WalletType.NORMAL)
    wallet2 = Wallet(name="Wallet 2", wallet_type=WalletType.NORMAL)
    test_db.add_all([wallet1, wallet2])
    test_db.commit()
    test_db.refresh(wallet1)
    test_db.refresh(wallet2)
    
    # 2. Create a calibration transaction in Wallet 1
    calibration = Transaction(
        wallet_id=wallet1.id,
        amount=Decimal("500"),
        date=date.today(),
        direction=TransactionDirection.OUTFLOW,
        classification=TransactionClassification.EXPENSE,
        is_calibration=True,
        description="Calibration"
    )
    test_db.add(calibration)
    test_db.commit()
    test_db.refresh(calibration)
    
    # 3. Try to resolve it using Wallet 2
    new_txn_data = TransactionCreate(
        wallet_id=wallet2.id,  # INTENTIONALLY DIFFERENT
        amount=Decimal("100"),
        date=date.today(),
        direction=TransactionDirection.OUTFLOW,
        classification=TransactionClassification.EXPENSE,
        description="Resolved Item"
    )
    
    # 4. Perform resolution
    result = resolve_calibration(test_db, calibration.id, new_txn_data)
    
    # 5. Verify the NEW transaction is actually in Wallet 1 (enforced)
    assert result.new_transaction.wallet_id == wallet1.id
    assert result.new_transaction.wallet_id != wallet2.id
    
    # 6. Verify regular details carried over
    assert result.new_transaction.amount == Decimal("100")
