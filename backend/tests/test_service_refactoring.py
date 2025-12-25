"""Tests for refactored transaction service methods."""
import pytest
from decimal import Decimal
from datetime import date

from app.models.transaction import TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkType, LinkStatus
from app.services import transaction_service, linked_entry_service
from app.schemas.transaction import WalletTransferRequest
from app.schemas.linked_entry import MarkAsLoanRequest, MarkAsDebtRequest


class TestCreateWalletTransfer:
    """Tests for create_wallet_transfer service method."""
    
    def test_create_wallet_transfer_success(self, test_db, sample_wallet):
        """Should create paired transfer transactions atomically."""
        from app.models.wallet import Wallet, WalletType
        
        # Create second wallet
        wallet2 = Wallet(
            name="Wallet 2",
            wallet_type=WalletType.NORMAL
        )
        test_db.add(wallet2)
        test_db.commit()
        test_db.refresh(wallet2)
        
        from app.models.transaction import Transaction
        txn = Transaction(
            wallet_id=wallet2.id,
            amount=Decimal("5000.00"),
            direction=TransactionDirection.INFLOW,
            classification=TransactionClassification.INCOME,
            description="INITIAL BALANCE",
            date=date(2025, 12, 1),
            is_ignored=True
        )
        test_db.add(txn)
        test_db.commit()
        
        # Create transfer request
        request = WalletTransferRequest(
            from_wallet_id=sample_wallet.id,
            to_wallet_id=wallet2.id,
            amount=Decimal("3000.00"),
            date=date(2025, 12, 7),
            time=None,
            description="Transfer to Wallet 2"
        )
        
        # Execute transfer
        result = transaction_service.create_wallet_transfer(test_db, request)
        
        # Verify response structure
        assert result.outflow_transaction is not None
        assert result.inflow_transaction is not None
        
        # Verify outflow transaction
        outflow = result.outflow_transaction
        assert outflow.wallet_id == sample_wallet.id
        assert outflow.direction == TransactionDirection.OUTFLOW
        assert outflow.amount == Decimal("3000.00")
        assert outflow.classification == TransactionClassification.TRANSFER
        assert outflow.description == "Transfer to Wallet 2"
        
        # Verify inflow transaction
        inflow = result.inflow_transaction
        assert inflow.wallet_id == wallet2.id
        assert inflow.direction == TransactionDirection.INFLOW
        assert inflow.amount == Decimal("3000.00")
        assert inflow.classification == TransactionClassification.TRANSFER
        assert inflow.description == "Transfer to Wallet 2"
        
        # Verify pairing
        assert outflow.paired_transaction_id == inflow.id
        assert inflow.paired_transaction_id == outflow.id
        
        # Verify wallet balances
        from app.services import wallet_service
        balance1 = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
        balance2 = wallet_service.calculate_wallet_balance(test_db, wallet2.id)
        
        assert balance1 == Decimal("7000.00")  # 10000 - 3000
        assert balance2 == Decimal("8000.00")  # 5000 + 3000
    
    def test_create_wallet_transfer_with_time(self, test_db, sample_wallet):
        """Should create transfer with time specified."""
        from app.models.wallet import Wallet, WalletType
        from datetime import time
        
        wallet2 = Wallet(
            name="Wallet 2",
            wallet_type=WalletType.NORMAL
        )
        test_db.add(wallet2)
        test_db.commit()
        
        request = WalletTransferRequest(
            from_wallet_id=sample_wallet.id,
            to_wallet_id=wallet2.id,
            amount=Decimal("1000.00"),
            date=date(2025, 12, 7),
            time=time(14, 30, 0),
            description="Afternoon transfer"
        )
        
        result = transaction_service.create_wallet_transfer(test_db, request)
        
        assert result.outflow_transaction.time == time(14, 30, 0)
        assert result.inflow_transaction.time == time(14, 30, 0)
    
    def test_create_wallet_transfer_atomicity(self, test_db, sample_wallet):
        """Should rollback both transactions if one fails."""
        # This test verifies atomicity by checking that invalid wallet_id causes rollback
        request = WalletTransferRequest(
            from_wallet_id=sample_wallet.id,
            to_wallet_id=99999,  # Non-existent wallet
            amount=Decimal("1000.00"),
            date=date(2025, 12, 7),
            description="Invalid transfer"
        )
        
        # Should raise error due to foreign key constraint
        with pytest.raises(Exception):  # IntegrityError or similar
            transaction_service.create_wallet_transfer(test_db, request)
        
        # Rollback the session to reset its state after the exception
        test_db.rollback()
        
        # Verify no transactions were created (atomicity)
        from app.models.transaction import Transaction
        txns = test_db.query(Transaction).filter(
            Transaction.wallet_id == sample_wallet.id
        ).all()
        assert len(txns) == 1 # Has Initial Balance Txn


class TestMarkAsLoan:
    """Tests for mark_as_loan service method."""
    
    def test_mark_as_loan_success(self, test_db, sample_wallet):
        """Should mark OUTFLOW transaction as loan and create linked entry."""
        from app.schemas.transaction import TransactionCreate
        
        # Create an OUTFLOW expense transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.OUTFLOW,
                amount=Decimal("5000.00"),
                classification=TransactionClassification.EXPENSE,
                description="Money for Bob"
            )
        )
        
        # Mark as loan
        request = MarkAsLoanRequest(
            counterparty_name="Bob",
            notes="Loan for emergency"
        )
        
        result = transaction_service.mark_as_loan(test_db, txn.id, request)
        
        # Verify linked entry created
        assert result.id is not None
        assert result.link_type == LinkType.LOAN
        assert result.counterparty_name == "Bob"
        assert result.notes == "Loan for emergency"
        assert result.total_amount == Decimal("5000.00")
        assert result.pending_amount == Decimal("5000.00")
        assert result.status == LinkStatus.PENDING
        
        # Verify transaction classification updated
        test_db.refresh(txn)
        assert txn.classification == TransactionClassification.LEND
    
    def test_mark_as_loan_already_lend(self, test_db, sample_wallet):
        """Should work even if transaction is already LEND."""
        from app.schemas.transaction import TransactionCreate
        
        # Create LEND transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.OUTFLOW,
                amount=Decimal("3000.00"),
                classification=TransactionClassification.LEND,
                description="Loan"
            )
        )
        
        request = MarkAsLoanRequest(counterparty_name="Alice")
        result = transaction_service.mark_as_loan(test_db, txn.id, request)
        
        assert result.link_type == LinkType.LOAN
        assert result.total_amount == Decimal("3000.00")
    
    def test_mark_as_loan_fail_inflow(self, test_db, sample_wallet):
        """Should fail if transaction is INFLOW."""
        from app.schemas.transaction import TransactionCreate
        
        # Create INFLOW transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.INFLOW,
                amount=Decimal("2000.00"),
                classification=TransactionClassification.INCOME,
                description="Income"
            )
        )
        
        request = MarkAsLoanRequest(counterparty_name="Bob")
        
        with pytest.raises(ValueError, match="Loan must be an OUTFLOW transaction"):
            transaction_service.mark_as_loan(test_db, txn.id, request)
    
    def test_mark_as_loan_fail_not_found(self, test_db):
        """Should fail if transaction doesn't exist."""
        request = MarkAsLoanRequest(counterparty_name="Bob")
        
        with pytest.raises(ValueError, match="Transaction not found"):
            transaction_service.mark_as_loan(test_db, 99999, request)
    
    def test_mark_as_loan_fail_already_linked(self, test_db, sample_wallet):
        """Should fail if transaction already has a linked entry."""
        from app.schemas.transaction import TransactionCreate
        from app.schemas.linked_entry import LinkedEntryCreate
        
        # Create transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.OUTFLOW,
                amount=Decimal("5000.00"),
                classification=TransactionClassification.SPLIT_PAYMENT,
                description="Split dinner"
            )
        )
        
        # Create linked entry (split payment)
        linked_entry_service.create_linked_entry(
            test_db,
            LinkedEntryCreate(
                primary_transaction_id=txn.id,
                link_type=LinkType.SPLIT_PAYMENT,
                counterparty_name="Friends",
                user_amount=Decimal("2000.00")
            )
        )
        
        # Try to mark as loan
        request = MarkAsLoanRequest(counterparty_name="Bob")
        
        with pytest.raises(Exception):  # LinkedEntryError
            transaction_service.mark_as_loan(test_db, txn.id, request)


class TestMarkAsDebt:
    """Tests for mark_as_debt service method."""
    
    def test_mark_as_debt_success(self, test_db, sample_wallet):
        """Should mark INFLOW transaction as debt and create linked entry."""
        from app.schemas.transaction import TransactionCreate
        
        # Create an INFLOW income transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.INFLOW,
                amount=Decimal("10000.00"),
                classification=TransactionClassification.INCOME,
                description="Money from Alice"
            )
        )
        
        # Mark as debt
        request = MarkAsDebtRequest(
            counterparty_name="Alice",
            notes="Borrowed for rent"
        )
        
        result = transaction_service.mark_as_debt(test_db, txn.id, request)
        
        # Verify linked entry created
        assert result.id is not None
        assert result.link_type == LinkType.DEBT
        assert result.counterparty_name == "Alice"
        assert result.notes == "Borrowed for rent"
        assert result.total_amount == Decimal("10000.00")
        assert result.pending_amount == Decimal("10000.00")
        assert result.status == LinkStatus.PENDING
        
        # Verify transaction classification updated
        test_db.refresh(txn)
        assert txn.classification == TransactionClassification.BORROW
    
    def test_mark_as_debt_already_borrow(self, test_db, sample_wallet):
        """Should work even if transaction is already BORROW."""
        from app.schemas.transaction import TransactionCreate
        
        # Create BORROW transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.INFLOW,
                amount=Decimal("7000.00"),
                classification=TransactionClassification.BORROW,
                description="Debt"
            )
        )
        
        request = MarkAsDebtRequest(counterparty_name="Charlie")
        result = transaction_service.mark_as_debt(test_db, txn.id, request)
        
        assert result.link_type == LinkType.DEBT
        assert result.total_amount == Decimal("7000.00")
    
    def test_mark_as_debt_fail_outflow(self, test_db, sample_wallet):
        """Should fail if transaction is OUTFLOW."""
        from app.schemas.transaction import TransactionCreate
        
        # Create OUTFLOW transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.OUTFLOW,
                amount=Decimal("2000.00"),
                classification=TransactionClassification.EXPENSE,
                description="Expense"
            )
        )
        
        request = MarkAsDebtRequest(counterparty_name="Alice")
        
        with pytest.raises(ValueError, match="Only INFLOW transactions can be marked as debt"):
            transaction_service.mark_as_debt(test_db, txn.id, request)
    
    def test_mark_as_debt_fail_not_found(self, test_db):
        """Should fail if transaction doesn't exist."""
        request = MarkAsDebtRequest(counterparty_name="Alice")
        
        with pytest.raises(ValueError, match="Transaction 99999 not found"):
            transaction_service.mark_as_debt(test_db, 99999, request)
    
    def test_mark_as_debt_rollback_on_error(self, test_db, sample_wallet):
        """Should rollback classification change if linked entry creation fails."""
        from app.schemas.transaction import TransactionCreate
        
        # Create transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.INFLOW,
                amount=Decimal("5000.00"),
                classification=TransactionClassification.INCOME,
                description="Income"
            )
        )
        
        # Mark as debt first time (should succeed)
        request1 = MarkAsDebtRequest(counterparty_name="Alice")
        result = transaction_service.mark_as_debt(test_db, txn.id, request1)
        assert result.link_type == LinkType.DEBT
        
        # Try to mark as debt again (should fail due to duplicate linked entry)
        request2 = MarkAsDebtRequest(counterparty_name="Bob")
        
        with pytest.raises(Exception):  # LinkedEntryError about already linked
            transaction_service.mark_as_debt(test_db, txn.id, request2)
        
        # Verify only one linked entry exists
        from app.models.linked_entry import LinkedEntry
        entries = test_db.query(LinkedEntry).filter(
            LinkedEntry.primary_transaction_id == txn.id
        ).all()
        assert len(entries) == 1
        assert entries[0].counterparty_name == "Alice"  # First one, not second
