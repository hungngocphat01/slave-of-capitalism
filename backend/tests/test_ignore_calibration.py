"""Tests for ignore and calibration functionality."""
import pytest
from decimal import Decimal
from datetime import date

from app.models.transaction import Transaction, TransactionDirection, TransactionClassification


class TestIgnoreTransaction:
    """Tests for transaction ignore functionality."""
    
    def test_ignore_transaction(self, test_db, sample_expense):
        """Should mark transaction as ignored."""
        from app.services import transaction_service
        
        # Initially not ignored
        assert sample_expense.is_ignored is False
        
        # Ignore it
        updated = transaction_service.ignore_transaction(test_db, sample_expense.id)
        
        assert updated.is_ignored is True
    
    def test_unignore_transaction(self, test_db, sample_expense):
        """Should unmark transaction as ignored."""
        from app.services import transaction_service
        
        # First ignore it
        sample_expense.is_ignored = True
        test_db.commit()
        
        # Then unignore
        updated = transaction_service.unignore_transaction(test_db, sample_expense.id)
        
        assert updated.is_ignored is False
    
    def test_ignored_transaction_excluded_from_budget(self, test_db, sample_wallet, sample_category):
        """Ignored transactions should not count toward monthly expense."""
        from app.services import transaction_service
        
        # Create two expenses
        exp1 = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Regular expense",
            category_id=sample_category.id,
            is_ignored=False
        )
        exp2 = Transaction(
            date=date(2025, 12, 7),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("2000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Ignored expense",
            category_id=sample_category.id,
            is_ignored=True
        )
        test_db.add_all([exp1, exp2])
        test_db.commit()
        
        # Calculate monthly expense
        total = transaction_service.calculate_monthly_expense(test_db, date(2025, 12, 1))
        
        # Only non-ignored expense should count
        assert total == Decimal("3000.00")


class TestCalibrationTransaction:
    """Tests for wallet calibration functionality."""
    
    def test_create_calibration_transaction(self, test_db, sample_wallet, sample_category):
        """Should create calibration transaction to fix wallet balance."""
        from app.services import wallet_service
        
        # Current balance: 10000 (initial)
        # Correct balance should be: 12000
        # Need to create INFLOW of 2000
        
        calibration = wallet_service.calibrate_wallet(
            test_db,
            sample_wallet.id,
            correct_balance=Decimal("12000.00"),
            misc_category_id=sample_category.id
        )
        
        assert calibration.is_calibration is True
        assert calibration.description == "CALIBRATION"
        assert calibration.amount == Decimal("2000.00")
        assert calibration.direction == TransactionDirection.INFLOW
        assert calibration.classification == TransactionClassification.INCOME
        
        # Verify balance is now correct
        new_balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
        assert new_balance == Decimal("12000.00")
    
    def test_calibration_with_negative_difference(self, test_db, sample_wallet, sample_category):
        """Should create OUTFLOW calibration when balance is too high."""
        from app.services import wallet_service
        
        # Current balance: 10000
        # Correct balance should be: 8000
        # Need to create OUTFLOW of 2000
        
        calibration = wallet_service.calibrate_wallet(
            test_db,
            sample_wallet.id,
            correct_balance=Decimal("8000.00"),
            misc_category_id=sample_category.id
        )
        
        assert calibration.is_calibration is True
        assert calibration.amount == Decimal("2000.00")
        assert calibration.direction == TransactionDirection.OUTFLOW
        assert calibration.classification == TransactionClassification.EXPENSE
    
    def test_resolve_calibration(self, test_db, sample_wallet, sample_category):
        """Should resolve calibration by creating new transaction and adjusting calibration."""
        from app.services import wallet_service, transaction_service
        from app.schemas.transaction import TransactionCreate
        
        # Create calibration
        calibration = wallet_service.calibrate_wallet(
            test_db,
            sample_wallet.id,
            correct_balance=Decimal("12000.00"),
            misc_category_id=sample_category.id
        )
        
        # User remembers: it was a ¥1000 income they forgot
        new_txn_data = TransactionCreate(
            date=date(2025, 12, 5),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("1000.00"),
            classification=TransactionClassification.INCOME,
            description="Forgot this income",
            category_id=sample_category.id
        )
        
        # Resolve calibration
        result = transaction_service.resolve_calibration(
            test_db,
            calibration.id,
            new_txn_data
        )
        
        # Calibration should be adjusted: 2000 - 1000 = 1000
        updated_calibration = test_db.get(Transaction, calibration.id)
        assert updated_calibration.amount == Decimal("1000.00")
        assert updated_calibration.is_calibration is True
        
        # New transaction should exist
        assert result.new_transaction.id is not None
        assert result.new_transaction.amount == Decimal("1000.00")
        
        # Balance should still be correct
        balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
        assert balance == Decimal("12000.00")
    
    def test_resolve_calibration_marks_ignored_when_zero(self, test_db, sample_wallet, sample_category):
        """Should mark calibration as ignored when resolved amount equals calibration amount."""
        from app.services import wallet_service, transaction_service
        from app.schemas.transaction import TransactionCreate
        
        # Create calibration of 2000
        calibration = wallet_service.calibrate_wallet(
            test_db,
            sample_wallet.id,
            correct_balance=Decimal("12000.00"),
            misc_category_id=sample_category.id
        )
        
        # Resolve with exact amount
        new_txn_data = TransactionCreate(
            date=date(2025, 12, 5),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("2000.00"),
            classification=TransactionClassification.INCOME,
            description="This was the missing amount",
            category_id=sample_category.id
        )
        
        result = transaction_service.resolve_calibration(
            test_db,
            calibration.id,
            new_txn_data
        )
        
        # Calibration should be kept but marked as ignored
        assert result.calibration_deleted is False
        updated_calibration = test_db.get(Transaction, calibration.id)
        assert updated_calibration is not None
        assert updated_calibration.is_ignored is True
        assert updated_calibration.amount == Decimal("0.00")
        
        # Balance should still be correct
        balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
        assert balance == Decimal("12000.00")
