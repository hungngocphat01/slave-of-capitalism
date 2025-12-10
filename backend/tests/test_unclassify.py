"""Tests for unclassify transaction functionality."""
import pytest
from decimal import Decimal
from datetime import date

from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkedEntry, LinkType, LinkStatus
from app.services import linked_entry_service

class TestUnclassify:
    """Tests for unclassify_transaction functionality."""
    
    def test_unclassify_split_payment(self, test_db, sample_wallet, sample_category):
        """Should revert SPLIT_PAYMENT to EXPENSE and remove linked entry."""
        # Create split transaction
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.SPLIT_PAYMENT,
            description="Dinner Split",
            category_id=sample_category.id
        )
        test_db.add(txn)
        test_db.commit()
        
        # Add linked entry
        entry = LinkedEntry(
            link_type=LinkType.SPLIT_PAYMENT,
            primary_transaction_id=txn.id,
            counterparty_name="Bob",
            total_amount=Decimal("3000.00"),
            user_amount=Decimal("1500.00"),
            pending_amount=Decimal("1500.00"),
            status=LinkStatus.PENDING
        )
        test_db.add(entry)
        test_db.commit()
        
        # Unclassify
        assert linked_entry_service.unclassify_transaction(test_db, txn.id)
        
        test_db.refresh(txn)
        assert txn.classification == TransactionClassification.EXPENSE
        
        # Ensure entry is gone
        assert db_query_entry(test_db, txn.id) is None

    def test_unclassify_loan(self, test_db, sample_wallet):
        """Should revert LEND to EXPENSE and remove linked entry."""
        # Create loan transaction
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.LEND,
            description="Lend to Bob"
        )
        test_db.add(txn)
        test_db.commit()
        
        # Add linked entry
        entry = LinkedEntry(
            link_type=LinkType.LOAN,
            primary_transaction_id=txn.id,
            counterparty_name="Bob",
            total_amount=Decimal("5000.00"),
            pending_amount=Decimal("5000.00"),
            status=LinkStatus.PENDING
        )
        test_db.add(entry)
        test_db.commit()
        
        # Unclassify
        assert linked_entry_service.unclassify_transaction(test_db, txn.id)
        
        test_db.refresh(txn)
        assert txn.classification == TransactionClassification.EXPENSE
        
        assert db_query_entry(test_db, txn.id) is None

    def test_unclassify_debt(self, test_db, sample_wallet):
        """Should revert BORROW to INCOME and remove linked entry."""
        # Create debt transaction
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.BORROW,
            description="Borrow from Bob"
        )
        test_db.add(txn)
        test_db.commit()
        
        # Add linked entry
        entry = LinkedEntry(
            link_type=LinkType.DEBT,
            primary_transaction_id=txn.id,
            counterparty_name="Bob",
            total_amount=Decimal("5000.00"),
            pending_amount=Decimal("5000.00"),
            status=LinkStatus.PENDING
        )
        test_db.add(entry)
        test_db.commit()
        
        # Unclassify
        assert linked_entry_service.unclassify_transaction(test_db, txn.id)
        
        test_db.refresh(txn)
        assert txn.classification == TransactionClassification.INCOME
        
        assert db_query_entry(test_db, txn.id) is None

    def test_unclassify_with_reimbursements(self, test_db, sample_wallet, sample_category):
        """Should revert linked reimbursements to INCOME."""
        # Split txn
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("2000.00"),
            classification=TransactionClassification.SPLIT_PAYMENT,
            description="Lunch"
        )
        test_db.add(txn)
        test_db.commit()
        
        entry = LinkedEntry(
            link_type=LinkType.SPLIT_PAYMENT,
            primary_transaction_id=txn.id,
            counterparty_name="Bob",
            total_amount=Decimal("2000.00"),
            user_amount=Decimal("1000.00"),
            pending_amount=Decimal("500.00"), # 500 paid back
            status=LinkStatus.PARTIAL
        )
        test_db.add(entry)
        test_db.commit()
        
        # Reimbursement txn
        reimbursement = Transaction(
            date=date(2025, 12, 7),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("500.00"),
            classification=TransactionClassification.DEBT_COLLECTION,
            description="Bob repaid"
        )
        test_db.add(reimbursement)
        test_db.commit()
        
        # Link them
        from app.models.linked_entry import LinkedTransaction
        link = LinkedTransaction(
            linked_entry_id=entry.id,
            transaction_id=reimbursement.id
        )
        test_db.add(link)
        test_db.commit()
        
        # Unclassify
        assert linked_entry_service.unclassify_transaction(test_db, txn.id)
        
        test_db.refresh(reimbursement)
        assert reimbursement.classification == TransactionClassification.INCOME
        
        # Link should be gone (cascaded from entry delete)
        assert test_db.query(LinkedTransaction).count() == 0

def db_query_entry(db, txn_id):
    return db.query(LinkedEntry).filter(LinkedEntry.primary_transaction_id == txn_id).first()
