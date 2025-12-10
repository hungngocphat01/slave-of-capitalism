"""Tests for transaction merge restriction."""
import pytest
from decimal import Decimal
from datetime import date

from app.models.transaction import TransactionDirection, TransactionClassification
from app.services import transaction_service

def test_merge_fail_special_transactions(test_db, sample_wallet):
    """Should fail if trying to merge special transactions."""
    from app.schemas.transaction import TransactionCreate, TransactionMergeRequest
    
    # Test 1: Transfer
    t1 = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100"), classification=TransactionClassification.TRANSFER, description="Transfer"
    ))
    t2 = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100"), classification=TransactionClassification.EXPENSE, description="Expense"
    ))
    
    with pytest.raises(ValueError, match="Cannot merge special transactions"):
        transaction_service.merge_transactions(test_db, TransactionMergeRequest(
            transaction_ids=[t1.id, t2.id], date=date(2025, 12, 6), description="Merge"
        ))

    # Test 2: Calibration
    t3 = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100"), classification=TransactionClassification.EXPENSE, 
        description="Calibration", is_calibration=True
    ))
    t4 = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100"), classification=TransactionClassification.EXPENSE, description="Expense"
    ))
    
    with pytest.raises(ValueError, match="Cannot merge special transactions"):
        transaction_service.merge_transactions(test_db, TransactionMergeRequest(
            transaction_ids=[t3.id, t4.id], date=date(2025, 12, 6), description="Merge"
        ))

    # Test 3: Linked Transaction (Part of Split)
    # Testing classification SPLIT_PAYMENT is enough for now.
    
    t5 = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100"), classification=TransactionClassification.SPLIT_PAYMENT, description="Split"
    ))
    t6 = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100"), classification=TransactionClassification.EXPENSE, description="Expense"
    ))
    
    with pytest.raises(ValueError, match="Cannot merge special transactions"):
        transaction_service.merge_transactions(test_db, TransactionMergeRequest(
            transaction_ids=[t5.id, t6.id], date=date(2025, 12, 6), description="Merge"
        ))
