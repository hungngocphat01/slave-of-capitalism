"""Tests for linked entry system (splits, loans, debts)."""
import pytest
from decimal import Decimal
from datetime import date

from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkedEntry, LinkedTransaction, LinkType, LinkStatus
from app.services.linked_entry_service import LinkedEntryError
from app.services import linked_entry_service


class TestSplitPayment:
    """Tests for split payment functionality."""
    
    def test_create_split_payment(self, test_db, sample_wallet, sample_category):
        """Should create split payment entry."""
        from app.schemas.linked_entry import LinkedEntryCreate
        
        # Create expense
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.EXPENSE,  # Will be updated
            description="Dinner with Bob",
            category_id=sample_category.id
        )
        test_db.add(txn)
        test_db.commit()
        
        # Create split entry
        entry_data = LinkedEntryCreate(
            primary_transaction_id=txn.id,
            link_type=LinkType.SPLIT_PAYMENT,
            counterparty_name="Bob",
            user_amount=Decimal("1500.00")
        )
        
        entry = linked_entry_service.create_linked_entry(test_db, entry_data)
        
        assert entry.link_type == LinkType.SPLIT_PAYMENT
        assert entry.total_amount == Decimal("3000.00")
        assert entry.user_amount == Decimal("1500.00")
        assert entry.pending_amount == Decimal("1500.00")  # Bob owes
        assert entry.status == LinkStatus.PENDING
        
        # Transaction should be reclassified
        test_db.refresh(txn)
        assert txn.classification == TransactionClassification.SPLIT_PAYMENT
    
    def test_link_reimbursement(self, test_db, sample_wallet, sample_category):
        """Should link reimbursement to split payment."""
        # Create split payment
        expense = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.SPLIT_PAYMENT,
            description="Dinner with Bob",
            category_id=sample_category.id
        )
        test_db.add(expense)
        test_db.commit()
        
        from app.schemas.linked_entry import LinkedEntryCreate
        entry_data = LinkedEntryCreate(
            primary_transaction_id=expense.id,
            link_type=LinkType.SPLIT_PAYMENT,
            counterparty_name="Bob",
            user_amount=Decimal("1500.00")
        )
        entry = linked_entry_service.create_linked_entry(test_db, entry_data)
        
        # Create reimbursement
        reimbursement = Transaction(
            date=date(2025, 12, 7),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("1500.00"),
            classification=TransactionClassification.DEBT_COLLECTION,
            description="Reimbursement from Bob"
        )
        test_db.add(reimbursement)
        test_db.commit()
        
        # Link
        updated_entry = linked_entry_service.link_transaction(
            test_db, entry.id, reimbursement.id
        )
        
        assert updated_entry.pending_amount == Decimal("0.00")
        assert updated_entry.status == LinkStatus.SETTLED
    
    def test_monthly_expense_with_split(self, test_db, sample_wallet, sample_category):
        """Monthly expense should only count user's share."""
        # Create split payment
        expense = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.SPLIT_PAYMENT,
            description="Dinner with Bob",
            category_id=sample_category.id
        )
        test_db.add(expense)
        test_db.commit()
        
        from app.schemas.linked_entry import LinkedEntryCreate
        entry_data = LinkedEntryCreate(
            primary_transaction_id=expense.id,
            link_type=LinkType.SPLIT_PAYMENT,
            counterparty_name="Bob",
            user_amount=Decimal("1500.00")
        )
        linked_entry_service.create_linked_entry(test_db, entry_data)
        
        from app.services import transaction_service
        total = transaction_service.calculate_monthly_expense(test_db, date(2025, 12, 1))
        
        # Only user's share counted
        assert total == Decimal("1500.00")


class TestLoan:
    """Tests for loan functionality."""
    
    def test_create_loan(self, test_db, sample_wallet):
        """Should create loan entry."""
        from app.schemas.linked_entry import LinkedEntryCreate
        
        # Create lend transaction
        lend = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.LEND,
            description="Lend to Bob"
        )
        test_db.add(lend)
        test_db.commit()
        
        # Create loan entry
        entry_data = LinkedEntryCreate(
            primary_transaction_id=lend.id,
            link_type=LinkType.LOAN,
            counterparty_name="Bob"
        )
        
        entry = linked_entry_service.create_linked_entry(test_db, entry_data)
        
        assert entry.link_type == LinkType.LOAN
        assert entry.total_amount == Decimal("5000.00")
        assert entry.pending_amount == Decimal("5000.00")
        assert entry.user_amount is None  # Not applicable for loans
    
    def test_partial_loan_repayment(self, test_db, sample_wallet):
        """Should handle partial loan repayments."""
        # Create loan
        lend = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.LEND,
            description="Lend to Bob"
        )
        test_db.add(lend)
        test_db.commit()
        
        from app.schemas.linked_entry import LinkedEntryCreate
        entry_data = LinkedEntryCreate(
            primary_transaction_id=lend.id,
            link_type=LinkType.LOAN,
            counterparty_name="Bob"
        )
        entry = linked_entry_service.create_linked_entry(test_db, entry_data)
        
        # First payback: 2000
        payback1 = Transaction(
            date=date(2025, 12, 10),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("2000.00"),
            classification=TransactionClassification.DEBT_COLLECTION,
            description="Partial payback from Bob"
        )
        test_db.add(payback1)
        test_db.commit()
        
        entry = linked_entry_service.link_transaction(
            test_db, entry.id, payback1.id
        )
        
        assert entry.pending_amount == Decimal("3000.00")
        assert entry.status == LinkStatus.PARTIAL
        
        # Second payback: 3000
        payback2 = Transaction(
            date=date(2025, 12, 15),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.DEBT_COLLECTION,
            description="Final payback from Bob"
        )
        test_db.add(payback2)
        test_db.commit()
        
        entry = linked_entry_service.link_transaction(
            test_db, entry.id, payback2.id
        )
        
        assert entry.pending_amount == Decimal("0.00")
        assert entry.status == LinkStatus.SETTLED
        assert len(entry.linked_transactions) == 2
    
    def test_loan_not_counted_as_expense(self, test_db, sample_wallet):
        """Lending should not count as monthly expense."""
        lend = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.LEND,
            description="Lend to Bob"
        )
        test_db.add(lend)
        test_db.commit()
        
        from app.services import transaction_service
        total = transaction_service.calculate_monthly_expense(test_db, date(2025, 12, 1))
        
        # Lending is not an expense
        assert total == Decimal("0.00")


class TestDebt:
    """Tests for debt functionality."""
    
    def test_create_debt(self, test_db, sample_wallet):
        """Should create debt entry."""
        from app.schemas.linked_entry import LinkedEntryCreate
        
        # Create borrow transaction
        borrow = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.BORROW,
            description="Borrowed from Alice"
        )
        test_db.add(borrow)
        test_db.commit()
        
        # Create debt entry
        entry_data = LinkedEntryCreate(
            primary_transaction_id=borrow.id,
            link_type=LinkType.DEBT,
            counterparty_name="Alice"
        )
        
        entry = linked_entry_service.create_linked_entry(test_db, entry_data)
        
        assert entry.link_type == LinkType.DEBT
        assert entry.total_amount == Decimal("10000.00")
        assert entry.pending_amount == Decimal("10000.00")
    
    def test_debt_repayment(self, test_db, sample_wallet):
        """Should link debt repayment."""
        # Create debt
        borrow = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.BORROW,
            description="Borrowed from Alice"
        )
        test_db.add(borrow)
        test_db.commit()
        
        from app.schemas.linked_entry import LinkedEntryCreate
        entry_data = LinkedEntryCreate(
            primary_transaction_id=borrow.id,
            link_type=LinkType.DEBT,
            counterparty_name="Alice"
        )
        entry = linked_entry_service.create_linked_entry(test_db, entry_data)
        
        # Repay
        repayment = Transaction(
            date=date(2025, 12, 20),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.LOAN_REPAYMENT,
            description="Repay Alice"
        )
        test_db.add(repayment)
        test_db.commit()
        
        entry = linked_entry_service.link_transaction(
            test_db, entry.id, repayment.id
        )
        
        assert entry.pending_amount == Decimal("0.00")
        assert entry.status == LinkStatus.SETTLED
    
    def test_repayment_not_counted_as_expense(self, test_db, sample_wallet):
        """Debt repayment should not count as expense."""
        repayment = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.LOAN_REPAYMENT,
            description="Repay Alice"
        )
        test_db.add(repayment)
        test_db.commit()
        
        from app.services import transaction_service
        total = transaction_service.calculate_monthly_expense(test_db, date(2025, 12, 1))
        
        # Repayment is not an expense
        assert total == Decimal("0.00")


class TestLinkedEntryValidation:
    """Tests for linked entry validation."""
    
    def test_cannot_link_same_transaction_twice(self, test_db, sample_wallet):
        """Should prevent linking same transaction twice."""
        # Create expense
        expense = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Expense"
        )
        test_db.add(expense)
        test_db.commit()
        
        from app.schemas.linked_entry import LinkedEntryCreate
        entry_data = LinkedEntryCreate(
            primary_transaction_id=expense.id,
            link_type=LinkType.SPLIT_PAYMENT,
            counterparty_name="Bob",
            user_amount=Decimal("1500.00")
        )
        linked_entry_service.create_linked_entry(test_db, entry_data)
        
        # Try to create another entry for same transaction
        with pytest.raises(LinkedEntryError, match="already has a linked entry"):
            linked_entry_service.create_linked_entry(test_db, entry_data)
    
    def test_user_amount_cannot_exceed_total(self, test_db, sample_wallet):
        """User amount cannot exceed transaction amount."""
        expense = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Expense"
        )
        test_db.add(expense)
        test_db.commit()
        
        from app.schemas.linked_entry import LinkedEntryCreate
        entry_data = LinkedEntryCreate(
            primary_transaction_id=expense.id,
            link_type=LinkType.SPLIT_PAYMENT,
            counterparty_name="Bob",
            user_amount=Decimal("5000.00")  # More than total!
        )
        
        with pytest.raises(LinkedEntryError, match="cannot exceed transaction amount"):
            linked_entry_service.create_linked_entry(test_db, entry_data)


class TestTotalOwedAndDebt:
    """Tests for calculating total owed and debt."""
    
    def test_calculate_total_owed(self, test_db, sample_wallet, sample_category):
        """Should calculate total amount owed to user."""
        # Split payment: Bob owes 1500
        split = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.SPLIT_PAYMENT,
            description="Dinner",
            category_id=sample_category.id
        )
        # Loan: Alice owes 5000
        loan = Transaction(
            date=date(2025, 12, 7),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.LEND,
            description="Lend to Alice"
        )
        test_db.add_all([split, loan])
        test_db.commit()
        
        from app.schemas.linked_entry import LinkedEntryCreate
        
        split_entry = LinkedEntryCreate(
            primary_transaction_id=split.id,
            link_type=LinkType.SPLIT_PAYMENT,
            counterparty_name="Bob",
            user_amount=Decimal("1500.00")
        )
        loan_entry = LinkedEntryCreate(
            primary_transaction_id=loan.id,
            link_type=LinkType.LOAN,
            counterparty_name="Alice"
        )
        
        linked_entry_service.create_linked_entry(test_db, split_entry)
        linked_entry_service.create_linked_entry(test_db, loan_entry)
        
        total_owed = linked_entry_service.calculate_total_owed(test_db)
        
        # 1500 + 5000 = 6500
        assert total_owed == Decimal("6500.00")
    
    def test_calculate_total_debt(self, test_db, sample_wallet):
        """Should calculate total debt user owes."""
        # Borrow from Alice: owe 10000
        borrow = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.BORROW,
            description="Borrowed from Alice"
        )
        test_db.add(borrow)
        test_db.commit()
        
        from app.schemas.linked_entry import LinkedEntryCreate
        debt_entry = LinkedEntryCreate(
            primary_transaction_id=borrow.id,
            link_type=LinkType.DEBT,
            counterparty_name="Alice"
        )
        linked_entry_service.create_linked_entry(test_db, debt_entry)
        
        total_debt = linked_entry_service.calculate_total_debt(test_db)
        
        assert total_debt == Decimal("10000.00")
