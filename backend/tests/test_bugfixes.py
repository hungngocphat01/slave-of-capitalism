"""Tests for specific bugfixes identified during code review."""
import pytest
from decimal import Decimal
from datetime import date

from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkedEntry, LinkedTransaction, LinkType, LinkStatus
from app.services import linked_entry_service, transaction_service, wallet_service
from app.schemas.transaction import TransactionCreate
from app.schemas.linked_entry import MarkAsLoanRequest, LinkedEntryCreate


class TestDirectionClassificationValidator:
    """Test that invalid direction/classification combos are rejected at flush time."""

    def test_valid_combination_expense_outflow(self, test_db, sample_wallet):
        """EXPENSE + OUTFLOW should be valid."""
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100.00"),
            classification=TransactionClassification.EXPENSE,
            description="Valid combo",
        )
        test_db.add(txn)
        test_db.commit()  # Should not raise

    def test_invalid_combination_expense_inflow(self, test_db, sample_wallet):
        """EXPENSE + INFLOW should be rejected."""
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("100.00"),
            classification=TransactionClassification.EXPENSE,
            description="Invalid combo",
        )
        test_db.add(txn)
        with pytest.raises(ValueError, match="Invalid combination"):
            test_db.commit()
        test_db.rollback()

    def test_invalid_combination_income_outflow(self, test_db, sample_wallet):
        """INCOME + OUTFLOW should be rejected."""
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100.00"),
            classification=TransactionClassification.INCOME,
            description="Invalid combo",
        )
        test_db.add(txn)
        with pytest.raises(ValueError, match="Invalid combination"):
            test_db.commit()
        test_db.rollback()

    def test_installment_transition_both_fields(self, test_db, sample_wallet):
        """Setting both direction=RESERVED and classification=INSTALLMENT should work."""
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("1000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Will become installment",
        )
        test_db.add(txn)
        test_db.commit()

        # Now transition to installment (set both fields before flush)
        txn.classification = TransactionClassification.INSTALLMENT
        txn.direction = TransactionDirection.RESERVED
        test_db.commit()  # Should not raise - validated after both are set

        test_db.refresh(txn)
        assert txn.direction == TransactionDirection.RESERVED
        assert txn.classification == TransactionClassification.INSTALLMENT


class TestSplitUnlinkStatus:
    """Test that unlinking all transactions from a split returns status to PENDING."""

    def test_unlink_all_returns_pending(self, test_db, sample_wallet):
        """After unlinking all reimbursements, split should be PENDING not PARTIAL."""
        # Create split
        txn = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.SPLIT_PAYMENT,
            description="Group dinner",
        )
        test_db.add(txn)
        test_db.commit()

        entry = LinkedEntry(
            link_type=LinkType.SPLIT_PAYMENT,
            primary_transaction_id=txn.id,
            counterparty_name="Friends",
            total_amount=Decimal("10000.00"),
            user_amount=Decimal("3000.00"),
            pending_amount=Decimal("7000.00"),
            status=LinkStatus.PENDING,
        )
        test_db.add(entry)
        test_db.commit()

        # Link a reimbursement
        reimburse = Transaction(
            date=date(2025, 12, 7),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("4000.00"),
            classification=TransactionClassification.DEBT_COLLECTION,
            description="Friends paid back",
        )
        test_db.add(reimburse)
        test_db.commit()

        link = LinkedTransaction(
            linked_entry_id=entry.id,
            transaction_id=reimburse.id,
        )
        test_db.add(link)
        entry.pending_amount = Decimal("3000.00")
        entry.status = LinkStatus.PARTIAL
        test_db.commit()

        # Unlink the reimbursement
        result = linked_entry_service.unlink_transaction(test_db, link.id)

        assert result.pending_amount == Decimal("7000.00")
        assert result.status == LinkStatus.PENDING  # Was PARTIAL before the fix


class TestUnclassifyInstallment:
    """Test that unclassifying an installment reverts INSTALLMT_CHRGE charges."""

    def test_unclassify_installment_reverts_charges(self, test_db, sample_wallet):
        """INSTALLMT_CHRGE linked transactions should revert to EXPENSE."""
        # Create installment parent
        parent = Transaction(
            date=date(2025, 12, 1),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.RESERVED,
            amount=Decimal("24000.00"),
            classification=TransactionClassification.INSTALLMENT,
            description="Laptop Plan",
        )
        test_db.add(parent)
        test_db.commit()

        entry = LinkedEntry(
            link_type=LinkType.INSTALLMENT,
            primary_transaction_id=parent.id,
            counterparty_name="Store",
            total_amount=Decimal("24000.00"),
            pending_amount=Decimal("22000.00"),
            status=LinkStatus.PARTIAL,
        )
        test_db.add(entry)
        test_db.commit()

        # Create an installment charge
        charge = Transaction(
            date=date(2025, 12, 5),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("2000.00"),
            classification=TransactionClassification.INSTALLMT_CHRGE,
            description="Laptop charge 1/12",
        )
        test_db.add(charge)
        test_db.commit()

        link = LinkedTransaction(
            linked_entry_id=entry.id,
            transaction_id=charge.id,
        )
        test_db.add(link)
        test_db.commit()

        # Unclassify the installment
        assert linked_entry_service.unclassify_transaction(test_db, parent.id)

        test_db.refresh(parent)
        test_db.refresh(charge)

        # Parent should revert to OUTFLOW + EXPENSE
        assert parent.direction == TransactionDirection.OUTFLOW
        assert parent.classification == TransactionClassification.EXPENSE

        # Charge should revert from INSTALLMT_CHRGE to EXPENSE
        assert charge.classification == TransactionClassification.EXPENSE


class TestAtomicResolveCalibration:
    """Test that resolve_calibration is atomic."""

    def test_resolve_calibration_creates_both_in_single_commit(
        self, test_db, sample_wallet, sample_category
    ):
        """Both the new transaction and calibration update should happen atomically."""
        # Create a calibration
        calibration = Transaction(
            date=date(2025, 12, 8),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("500.00"),
            classification=TransactionClassification.EXPENSE,
            description="CALIBRATION",
            category_id=sample_category.id,
            is_calibration=True,
        )
        test_db.add(calibration)
        test_db.commit()
        test_db.refresh(calibration)

        # Resolve partially
        new_txn_data = TransactionCreate(
            date=date(2025, 12, 8),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("200.00"),
            classification=TransactionClassification.EXPENSE,
            description="Actual purchase",
            category_id=sample_category.id,
        )

        result = transaction_service.resolve_calibration(
            test_db, calibration.id, new_txn_data
        )

        # Both should exist
        assert result.new_transaction.id is not None
        assert result.updated_calibration.amount == Decimal("300.00")
