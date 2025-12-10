import pytest
from decimal import Decimal
from datetime import date
from sqlalchemy.orm import Session
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.wallet import Wallet, WalletType
from app.schemas.transaction import TransactionCreate
from app.services.transaction_service import resolve_calibration

@pytest.fixture
def sample_wallet(test_db):
    wallet = Wallet(
        name="Test Wallet",
        wallet_type=WalletType.NORMAL
    )
    test_db.add(wallet)
    test_db.commit()
    test_db.refresh(wallet)
    
    # Add initial transaction logic if needed, or just keep it simple as 0 balance is fine here?
    # Keeping it simple unless test fails on balance
    return wallet

def test_resolve_calibration_calculation_logic(test_db: Session, sample_wallet: Wallet):
    """Test the math logic of resolving calibrations."""
    # Setup Wallet
    wallet = sample_wallet
    
    # Case 1: Same Direction (Outflow / Outflow) -> Subtract
    # Calibration: Outflow 1300
    calib1 = Transaction(
        wallet_id=wallet.id,
        amount=Decimal("1300"),
        date=date.today(),
        direction=TransactionDirection.OUTFLOW,
        classification=TransactionClassification.EXPENSE,
        is_calibration=True,
        description="Calibration 1"
    )
    test_db.add(calib1)
    test_db.commit()
    test_db.refresh(calib1)
    
    # Resolve with Outflow 500
    txn1 = TransactionCreate(
        wallet_id=wallet.id,
        amount=Decimal("500"),
        date=date.today(),
        direction=TransactionDirection.OUTFLOW,
        classification=TransactionClassification.EXPENSE,
        description="Resolution 1"
    )
    
    result1 = resolve_calibration(test_db, calib1.id, txn1)
    
    # Expectation: 1300 - 500 = 800 (Outflow)
    assert result1.updated_calibration is not None
    assert result1.updated_calibration.amount == Decimal("800")
    assert result1.updated_calibration.direction == TransactionDirection.OUTFLOW
    
    # Case 2: Same Direction (Inflow / Inflow) -> Subtract
    # Calibration: Inflow 1000
    calib2 = Transaction(
        wallet_id=wallet.id,
        amount=Decimal("1000"),
        date=date.today(),
        direction=TransactionDirection.INFLOW,
        classification=TransactionClassification.INCOME,
        is_calibration=True,
        description="Calibration 2"
    )
    test_db.add(calib2)
    test_db.commit()
    test_db.refresh(calib2)
    
    # Resolve with Inflow 200
    txn2 = TransactionCreate(
        wallet_id=wallet.id,
        amount=Decimal("200"),
        date=date.today(),
        direction=TransactionDirection.INFLOW,
        classification=TransactionClassification.INCOME,
        description="Resolution 2"
    )
    
    result2 = resolve_calibration(test_db, calib2.id, txn2)
    
    # Expectation: 1000 - 200 = 800 (Inflow)
    assert result2.updated_calibration is not None
    assert result2.updated_calibration.amount == Decimal("800")
    assert result2.updated_calibration.direction == TransactionDirection.INFLOW

    # Case 3: Opposite Direction (Outflow Calibration / Inflow Transaction) -> Add
    # Calibration: Outflow 800 (from Result 1)
    # Resolve with Inflow 200
    txn3 = TransactionCreate(
        wallet_id=wallet.id,
        amount=Decimal("200"),
        date=date.today(),
        direction=TransactionDirection.INFLOW,
        classification=TransactionClassification.INCOME,
        description="Resolution 3"
    )
    
    result3 = resolve_calibration(test_db, calib1.id, txn3)
    
    # Expectation: 800 + 200 = 1000 (Outflow)
    assert result3.updated_calibration is not None
    assert result3.updated_calibration.amount == Decimal("1000")
    assert result3.updated_calibration.direction == TransactionDirection.OUTFLOW

    # Case 4: Exact Match -> Amount becomes 0 -> Ignored but Not Deleted
    # Calibration: Outflow 1000 (from Result 3)
    # Resolve with Outflow 1000
    txn4 = TransactionCreate(
        wallet_id=wallet.id,
        amount=Decimal("1000"),
        date=date.today(),
        direction=TransactionDirection.OUTFLOW,
        classification=TransactionClassification.EXPENSE,
        description="Resolution 4 (Exact)"
    )
    
    result4 = resolve_calibration(test_db, calib1.id, txn4)
    
    # Expectation: 1000 - 1000 = 0.
    # Should NOT be deleted. Should be ignored.
    assert result4.calibration_deleted is False
    assert result4.updated_calibration is not None
    assert result4.updated_calibration.amount == Decimal("0.00")
    assert result4.updated_calibration.is_ignored is True
    
    # Case 5: Over Resolution -> Amount becomes Negative -> Flip Direction
    # Reset calibration to clean state for test: Outflow 500
    calib_over = Transaction(
        wallet_id=wallet.id,
        amount=Decimal("500"),
        date=date.today(),
        direction=TransactionDirection.OUTFLOW,
        classification=TransactionClassification.EXPENSE,
        is_calibration=True,
        description="Calibration Over"
    )
    test_db.add(calib_over)
    test_db.commit()
    test_db.refresh(calib_over)
    
    # Resolve with Outflow 700 (200 more than needed)
    txn5 = TransactionCreate(
        wallet_id=wallet.id,
        amount=Decimal("700"),
        date=date.today(),
        direction=TransactionDirection.OUTFLOW,
        classification=TransactionClassification.EXPENSE,
        description="Resolution 5 (Over)"
    )
    
    result5 = resolve_calibration(test_db, calib_over.id, txn5)
    
    # Expectation: 500 - 700 = -200.
    # Should flip direction: Outflow -> Inflow. Amount -> 200.
    # Should NOT be ignored.
    assert result5.calibration_deleted is False
    assert result5.updated_calibration is not None
    assert result5.updated_calibration.amount == Decimal("200.00")
    assert result5.updated_calibration.direction == TransactionDirection.INFLOW
    assert result5.updated_calibration.is_ignored is False
