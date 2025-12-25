"""Tests for new transaction model with direction and classification."""
import pytest
from decimal import Decimal
from datetime import date

from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.services import transaction_service


class TestTransactionCRUD:
    """Tests for transaction CRUD operations."""
    
    def test_create_expense_transaction(self, test_db, sample_wallet, sample_category):
        """Should create expense transaction with OUTFLOW direction."""
        from app.schemas.transaction import TransactionCreate
        
        txn_data = TransactionCreate(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("2000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Test expense",
            category_id=sample_category.id
        )
        
        txn = transaction_service.create_transaction(test_db, txn_data)
        
        assert txn.id is not None
        assert txn.direction == TransactionDirection.OUTFLOW
        assert txn.classification == TransactionClassification.EXPENSE
        assert txn.amount == Decimal("2000.00")
    
    def test_create_lend_transaction(self, test_db, sample_wallet):
        """Should create lend transaction."""
        from app.schemas.transaction import TransactionCreate
        
        txn_data = TransactionCreate(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.LEND,
            description="Lend to Bob"
        )
        
        txn = transaction_service.create_transaction(test_db, txn_data)
        
        assert txn.classification == TransactionClassification.LEND
        assert txn.direction == TransactionDirection.OUTFLOW
    
    def test_create_borrow_transaction(self, test_db, sample_wallet):
        """Should create borrow transaction."""
        from app.schemas.transaction import TransactionCreate
        
        txn_data = TransactionCreate(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.BORROW,
            description="Borrowed from Alice"
        )
        
        txn = transaction_service.create_transaction(test_db, txn_data)
        
        assert txn.classification == TransactionClassification.BORROW
        assert txn.direction == TransactionDirection.INFLOW
    
    def test_reclassify_transaction(self, test_db, sample_expense):
        """Should reclassify transaction."""
        updated = transaction_service.reclassify_transaction(
            test_db, sample_expense.id, TransactionClassification.SPLIT_PAYMENT
        )
        
        assert updated.classification == TransactionClassification.SPLIT_PAYMENT


class TestWalletBalance:
    """Tests for wallet balance calculation with direction."""
    
    def test_normal_wallet_with_inflow_outflow(self, test_db, sample_wallet):
        """Normal wallet balance = initial + inflow - outflow."""
        # Add inflow
        inflow = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.INCOME,
            description="Income"
        )
        # Add outflow
        outflow = Transaction(
            date=date(2025, 12, 7),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Expense"
        )
        test_db.add_all([inflow, outflow])
        test_db.commit()
        
        from app.services import wallet_service
        balance = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
        
        # 10000 + 5000 - 3000 = 12000
        assert balance == Decimal("12000.00")
    
    def test_credit_wallet_balance(self, test_db, sample_credit_wallet):
        """Credit wallet balance = outflow - inflow (amount owed)."""
        # Charge 5000
        charge = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_credit_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Purchase"
        )
        # Pay 2000
        payment = Transaction(
            date=date(2025, 12, 7),
            wallet_id=sample_credit_wallet.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("2000.00"),
            classification=TransactionClassification.INCOME,
            description="Payment"
        )
        test_db.add_all([charge, payment])
        test_db.commit()
        
        from app.services import wallet_service
        balance = wallet_service.calculate_wallet_balance(test_db, sample_credit_wallet.id)
        
        # 5000 - 2000 = 3000 owed
        assert balance == Decimal("3000.00")


class TestMonthlyExpense:
    """Tests for monthly expense calculation."""
    
    def test_expense_only_counts_expense_classification(self, test_db, sample_wallet, sample_category):
        """Monthly expense should only count EXPENSE classification."""
        # Regular expense
        exp1 = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("3000.00"),
            classification=TransactionClassification.EXPENSE,
            description="Expense",
            category_id=sample_category.id
        )
        # Lend (should not count)
        lend = Transaction(
            date=date(2025, 12, 7),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("5000.00"),
            classification=TransactionClassification.LEND,
            description="Lend to Bob"
        )
        # Transfer (should not count)
        transfer = Transaction(
            date=date(2025, 12, 8),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("2000.00"),
            classification=TransactionClassification.TRANSFER,
            description="Transfer"
        )
        test_db.add_all([exp1, lend, transfer])
        test_db.commit()
        
        total = transaction_service.calculate_monthly_expense(test_db, date(2025, 12, 1))
        
        # Only expense counted
        assert total == Decimal("3000.00")


class TestWalletTransfer:
    """Tests for wallet transfer functionality."""
    
    def test_create_paired_transfer(self, test_db, sample_wallet):
        """Should create paired transfer transactions."""
        from app.models.wallet import Wallet, WalletType
        
        # Create second wallet
        wallet2 = Wallet(
            name="Wallet 2",
            wallet_type=WalletType.NORMAL
        )
        test_db.add(wallet2)
        test_db.commit()
        
        # Create outflow
        outflow = Transaction(
            date=date(2025, 12, 6),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.TRANSFER,
            description="Transfer to Wallet 2"
        )
        test_db.add(outflow)
        test_db.commit()
        
        # Create inflow
        inflow = Transaction(
            date=date(2025, 12, 6),
            wallet_id=wallet2.id,
            direction=TransactionDirection.INFLOW,
            amount=Decimal("10000.00"),
            classification=TransactionClassification.TRANSFER,
            description="Transfer from Wallet 1",
            paired_transaction_id=outflow.id
        )
        test_db.add(inflow)
        test_db.commit()
        
        # Update outflow
        outflow.paired_transaction_id = inflow.id
        test_db.commit()
        
        # Verify pairing
        assert outflow.paired_transaction_id == inflow.id
        assert inflow.paired_transaction_id == outflow.id
        
        # Verify balances
        from app.services import wallet_service
        balance1 = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
        balance2 = wallet_service.calculate_wallet_balance(test_db, wallet2.id)
        
        assert balance1 == Decimal("0.00")  # 10000 - 10000
        assert balance2 == Decimal("10000.00")  # 0 + 10000

class TestBulkOperations:
    """Tests for bulk transaction operations."""
    
    def test_delete_transactions(self, test_db, sample_wallet):
        """Should delete multiple transactions atomically."""
        # Create transactions
        txns = []
        for i in range(3):
            txns.append(
                transaction_service.create_transaction(
                    test_db, 
                    transaction_service.TransactionCreate(
                        date=date(2025, 12, 6),
                        wallet_id=sample_wallet.id,
                        direction=TransactionDirection.OUTFLOW,
                        amount=Decimal(f"100.{i}"),
                        classification=TransactionClassification.EXPENSE,
                        description=f"Txn {i}"
                    )
                )
            )
        
        ids = [t.id for t in txns]
        
        # Delete first two
        success = transaction_service.delete_transactions(test_db, ids[:2])
        assert success
        
        # Verify deletion
        t0 = transaction_service.get_transaction(test_db, ids[0])
        t1 = transaction_service.get_transaction(test_db, ids[1])
        t2 = transaction_service.get_transaction(test_db, ids[2])
        
        assert t0 is None
        assert t1 is None
        assert t2 is not None

    def test_delete_single_transaction_helper(self, test_db, sample_wallet):
        """Should delete single transaction using bulk helper."""
        txn = transaction_service.create_transaction(
            test_db, 
            transaction_service.TransactionCreate(
                date=date(2025, 12, 6),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.OUTFLOW,
                amount=Decimal("100.00"),
                classification=TransactionClassification.EXPENSE,
                description="Txn"
            )
        )
        
        success = transaction_service.delete_transaction(test_db, txn.id)
        assert success
        
        assert transaction_service.get_transaction(test_db, txn.id) is None

    def test_ignore_transactions(self, test_db, sample_wallet):
        """Should ignore multiple transactions."""
        txns = []
        for i in range(3):
            txns.append(
                transaction_service.create_transaction(
                    test_db, 
                    transaction_service.TransactionCreate(
                        date=date(2025, 12, 6),
                        wallet_id=sample_wallet.id,
                        direction=TransactionDirection.OUTFLOW,
                        amount=Decimal(f"100.{i}"),
                        classification=TransactionClassification.EXPENSE,
                        description=f"Txn {i}"
                    )
                )
            )
            
        ids = [t.id for t in txns]
        
        # Ignore first two
        success = transaction_service.ignore_transactions(test_db, ids[:2])
        assert success
        
        test_db.expire_all()
        
        t0 = transaction_service.get_transaction(test_db, ids[0])
        t1 = transaction_service.get_transaction(test_db, ids[1])
        t2 = transaction_service.get_transaction(test_db, ids[2])
        
        assert t0.is_ignored
        assert t1.is_ignored
        assert not t2.is_ignored

    def test_unignore_transactions(self, test_db, sample_wallet):
        """Should unignore multiple transactions."""
        txns = []
        for i in range(2):
            txn = transaction_service.create_transaction(
                    test_db, 
                    transaction_service.TransactionCreate(
                        date=date(2025, 12, 6),
                        wallet_id=sample_wallet.id,
                        direction=TransactionDirection.OUTFLOW,
                        amount=Decimal(f"100.{i}"),
                        classification=TransactionClassification.EXPENSE,
                        description=f"Txn {i}"
                    )
                )
            txn.is_ignored = True
            test_db.add(txn)
            txns.append(txn)
        test_db.commit()
            
        ids = [t.id for t in txns]
        
        # Unignore all
        success = transaction_service.unignore_transactions(test_db, ids)
        assert success
        
        test_db.expire_all()
        
        t0 = transaction_service.get_transaction(test_db, ids[0])
        t1 = transaction_service.get_transaction(test_db, ids[1])
        
        assert not t0.is_ignored
        assert not t1.is_ignored
        
    def test_link_transactions(self, test_db, sample_wallet):
        """Should link multiple transactions to an entry."""
        from app.models.linked_entry import LinkedEntry, LinkType, LinkStatus
        from app.services import linked_entry_service
        
        # Create transactions (INFLOW because we'll make a SPLIT_PAYMENT entry)
        txns = []
        for i in range(2):
            txns.append(
                transaction_service.create_transaction(
                    test_db, 
                    transaction_service.TransactionCreate(
                        date=date(2025, 12, 6),
                        wallet_id=sample_wallet.id,
                        direction=TransactionDirection.INFLOW,
                        amount=Decimal("1000.00"),
                        classification=TransactionClassification.INCOME,
                        description=f"Payment {i}"
                    )
                )
            )
            
        # Create a split payment linked entry
        # Primary transaction for the split (OUTFLOW)
        primary_txn = transaction_service.create_transaction(
            test_db,
            transaction_service.TransactionCreate(
                date=date(2025, 12, 5),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.OUTFLOW,
                amount=Decimal("5000.00"),
                classification=TransactionClassification.SPLIT_PAYMENT,
                description="Dinner Bill"
            )
        )
        
        entry = linked_entry_service.create_linked_entry(
            test_db,
            linked_entry_service.LinkedEntryCreate(
                link_type=LinkType.SPLIT_PAYMENT,
                primary_transaction_id=primary_txn.id,
                counterparty_name="Friends",
                user_amount=Decimal("3000.00"), # We paid 3000 for ourselves, 2000 for others
                notes="Split"
            )
        )
        
        assert entry.pending_amount == Decimal("2000.00")
        
        # Link the two 1000.00 inflow transactions
        ids = [t.id for t in txns]
        updated_entry = linked_entry_service.link_transactions(test_db, entry.id, ids)
        
        assert updated_entry.pending_amount == Decimal("0.00")
        assert updated_entry.status == LinkStatus.SETTLED
        
        # Verify transaction classifications updated
        test_db.refresh(txns[0])
        test_db.refresh(txns[1])
        assert txns[0].classification == TransactionClassification.DEBT_COLLECTION
        assert txns[1].classification == TransactionClassification.DEBT_COLLECTION


class TestMergeTransactions:
    """Tests for merging transactions."""
    
    def test_merge_success(self, test_db, sample_wallet, sample_category):
        """Should successfully merge multiple transactions."""
        from app.schemas.transaction import TransactionCreate, TransactionMergeRequest
        
        # Create 3 transactions
        txns = []
        for i in range(3):
            txns.append(
                transaction_service.create_transaction(
                    test_db, 
                    TransactionCreate(
                        date=date(2025, 12, 6),
                        wallet_id=sample_wallet.id,
                        direction=TransactionDirection.OUTFLOW,
                        amount=Decimal("100.00"),
                        classification=TransactionClassification.EXPENSE,
                        description=f"Item {i}",
                        category_id=sample_category.id
                    )
                )
            )
            
        merge_req = TransactionMergeRequest(
            transaction_ids=[t.id for t in txns],
            date=date(2025, 12, 7),
            description="Merged Items",
            category_id=sample_category.id,
            subcategory_id=None
        )
        
        merged_txn = transaction_service.merge_transactions(test_db, merge_req)
        
        assert merged_txn.id is not None
        assert merged_txn.amount == Decimal("300.00")
        assert merged_txn.description == "Merged Items"
        assert merged_txn.date == date(2025, 12, 7)
        assert merged_txn.wallet_id == sample_wallet.id
        assert merged_txn.direction == TransactionDirection.OUTFLOW
        assert merged_txn.classification == TransactionClassification.EXPENSE
        
        # Verify old transactions are gone
        for t in txns:
            assert transaction_service.get_transaction(test_db, t.id) is None

    def test_merge_fail_different_wallets(self, test_db, sample_wallet):
        """Should fail if transactions are from different wallets."""
        from app.models.wallet import Wallet, WalletType
        from app.schemas.transaction import TransactionCreate, TransactionMergeRequest
        
        wallet2 = Wallet(name="Wallet 2", wallet_type=WalletType.NORMAL)
        test_db.add(wallet2)
        test_db.commit()
        
        t1 = transaction_service.create_transaction(test_db, TransactionCreate(
            date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100"), classification=TransactionClassification.EXPENSE
        ))
        t2 = transaction_service.create_transaction(test_db, TransactionCreate(
            date=date(2025, 12, 6), wallet_id=wallet2.id, direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100"), classification=TransactionClassification.EXPENSE
        ))
        
        with pytest.raises(ValueError, match="All transactions must belong to the same wallet"):
            transaction_service.merge_transactions(test_db, TransactionMergeRequest(
                transaction_ids=[t1.id, t2.id], date=date(2025, 12, 6), description="Merge"
            ))

    def test_merge_fail_different_directions(self, test_db, sample_wallet):
        """Should fail if transactions have different directions."""
        from app.schemas.transaction import TransactionCreate, TransactionMergeRequest
        
        t1 = transaction_service.create_transaction(test_db, TransactionCreate(
            date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.OUTFLOW,
            amount=Decimal("100"), classification=TransactionClassification.EXPENSE
        ))
        t2 = transaction_service.create_transaction(test_db, TransactionCreate(
            date=date(2025, 12, 6), wallet_id=sample_wallet.id, direction=TransactionDirection.INFLOW,
            amount=Decimal("100"), classification=TransactionClassification.INCOME
        ))
        
        with pytest.raises(ValueError, match="All transactions must have the same direction"):
            transaction_service.merge_transactions(test_db, TransactionMergeRequest(
                transaction_ids=[t1.id, t2.id], date=date(2025, 12, 6), description="Merge"
            ))

