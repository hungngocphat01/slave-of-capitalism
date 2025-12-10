"""Integration tests for refactored router endpoints."""
import pytest
from decimal import Decimal
from datetime import date

from app.models.transaction import TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkType, LinkStatus


class TestWalletTransferRouter:
    """Tests for wallet transfer router endpoints."""
    
    def test_create_wallet_transfer_via_transactions_router(self, client, test_db, sample_wallet):
        """Should create wallet transfer via POST /transactions/wallet-transfer."""
        from app.models.wallet import Wallet, WalletType
        
        # Create second wallet
        wallet2 = Wallet(
            name="Cash Wallet",
            wallet_type=WalletType.NORMAL
        )
        test_db.add(wallet2)
        test_db.commit()
        test_db.refresh(wallet2)
        
        # Add Initial Balance Transaction
        from app.models.transaction import Transaction
        txn = Transaction(
            wallet_id=wallet2.id,
            amount=Decimal("1000.00"),
            direction=TransactionDirection.INFLOW,
            classification=TransactionClassification.INCOME,
            description="INITIAL BALANCE",
            date=date(2025, 12, 1),
            is_ignored=True
        )
        test_db.add(txn)
        test_db.commit()
        
        # Make request
        response = client.post("/api/transactions/wallet-transfer", json={
            "from_wallet_id": sample_wallet.id,
            "to_wallet_id": wallet2.id,
            "amount": 2500.00,
            "date": "2025-12-07",
            "description": "Transfer to cash"
        })
        
        assert response.status_code == 201
        data = response.json()
        
        # Verify response structure
        assert "outflow_transaction" in data
        assert "inflow_transaction" in data
        
        outflow = data["outflow_transaction"]
        inflow = data["inflow_transaction"]
        
        # Verify outflow
        assert outflow["wallet_id"] == sample_wallet.id
        assert outflow["direction"] == "outflow"
        assert outflow["amount"] == "2500.00"
        assert outflow["classification"] == "transfer"
        
        # Verify inflow
        assert inflow["wallet_id"] == wallet2.id
        assert inflow["direction"] == "inflow"
        assert inflow["amount"] == "2500.00"
        assert inflow["classification"] == "transfer"
        
        # Verify pairing
        assert outflow["paired_transaction_id"] == inflow["id"]
        assert inflow["paired_transaction_id"] == outflow["id"]
    
    def test_create_transfer_via_wallets_router(self, client, test_db, sample_wallet):
        """Should create wallet transfer via POST /wallets/transfer."""
        from app.models.wallet import Wallet, WalletType
        
        wallet2 = Wallet(
            name="Savings",
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
        
        response = client.post("/api/wallets/transfer", json={
            "from_wallet_id": sample_wallet.id,
            "to_wallet_id": wallet2.id,
            "amount": 3000.00,
            "date": "2025-12-07",
            "description": "Save money"
        })
        
        assert response.status_code == 200
        data = response.json()
        
        assert "from" in data
        assert "to" in data
        
        assert data["from"]["amount"] == "3000.00"
        assert data["to"]["amount"] == "3000.00"
    
    def test_wallet_transfer_missing_fields(self, client, sample_wallet):
        """Should return 400 if required fields missing."""
        response = client.post("/api/wallets/transfer", json={
            "from_wallet_id": sample_wallet.id,
            # Missing to_wallet_id, amount, date
        })
        
        assert response.status_code == 400
        assert "Missing required field" in response.json()["detail"]
    
    def test_wallet_transfer_invalid_wallet(self, client, sample_wallet):
        """Should return 404 if wallet doesn't exist."""
        response = client.post("/api/wallets/transfer", json={
            "from_wallet_id": sample_wallet.id,
            "to_wallet_id": 99999,
            "amount": 1000.00,
            "date": "2025-12-07"
        })
        
        # Should get error about wallet not found or constraint failure
        assert response.status_code in [400, 404]


class TestMarkAsLoanRouter:
    """Tests for mark as loan router endpoint."""
    
    def test_mark_transaction_as_loan(self, client, test_db, sample_wallet):
        """Should mark transaction as loan via POST /transactions/{id}/mark-loan."""
        from app.services import transaction_service
        from app.schemas.transaction import TransactionCreate
        
        # Create OUTFLOW transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.OUTFLOW,
                amount=Decimal("5000.00"),
                classification=TransactionClassification.EXPENSE,
                description="Money for friend"
            )
        )
        
        # Mark as loan
        response = client.post(f"/api/transactions/{txn.id}/mark-loan", json={
            "counterparty_name": "Bob",
            "notes": "Emergency loan"
        })
        
        assert response.status_code == 200
        data = response.json()
        
        # Verify linked entry created
        assert data["link_type"] == "loan"
        assert data["counterparty_name"] == "Bob"
        assert data["notes"] == "Emergency loan"
        assert data["total_amount"] == "5000.00"
        assert data["pending_amount"] == "5000.00"
        assert data["status"] == "pending"
        
        # Verify transaction classification updated
        txn_response = client.get(f"/api/transactions/{txn.id}")
        assert txn_response.json()["classification"] == "lend"
    
    def test_mark_as_loan_inflow_fails(self, client, test_db, sample_wallet):
        """Should fail if transaction is INFLOW."""
        from app.services import transaction_service
        from app.schemas.transaction import TransactionCreate
        
        # Create INFLOW transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.INFLOW,
                amount=Decimal("3000.00"),
                classification=TransactionClassification.INCOME,
                description="Income"
            )
        )
        
        response = client.post(f"/api/transactions/{txn.id}/mark-loan", json={
            "counterparty_name": "Bob"
        })
        
        assert response.status_code == 400
        assert "OUTFLOW" in response.json()["detail"]
    
    def test_mark_as_loan_not_found(self, client):
        """Should return 404 if transaction doesn't exist."""
        response = client.post("/api/transactions/99999/mark-loan", json={
            "counterparty_name": "Bob"
        })
        
        assert response.status_code == 400  # ValueError gets converted to 400


class TestMarkAsDebtRouter:
    """Tests for mark as debt router endpoint."""
    
    def test_mark_transaction_as_debt(self, client, test_db, sample_wallet):
        """Should mark transaction as debt via POST /transactions/{id}/mark-debt."""
        from app.services import transaction_service
        from app.schemas.transaction import TransactionCreate
        
        # Create INFLOW transaction
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.INFLOW,
                amount=Decimal("10000.00"),
                classification=TransactionClassification.INCOME,
                description="Borrowed money"
            )
        )
        
        # Mark as debt
        response = client.post(f"/api/transactions/{txn.id}/mark-debt", json={
            "counterparty_name": "Alice",
            "notes": "Borrowed for emergency"
        })
        
        assert response.status_code == 200
        data = response.json()
        
        # Verify linked entry created
        assert data["link_type"] == "debt"
        assert data["counterparty_name"] == "Alice"
        assert data["notes"] == "Borrowed for emergency"
        assert data["total_amount"] == "10000.00"
        assert data["pending_amount"] == "10000.00"
        assert data["status"] == "pending"
        
        # Verify transaction classification updated
        txn_response = client.get(f"/api/transactions/{txn.id}")
        assert txn_response.json()["classification"] == "borrow"
    
    def test_mark_as_debt_outflow_fails(self, client, test_db, sample_wallet):
        """Should fail if transaction is OUTFLOW."""
        from app.services import transaction_service
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
        
        response = client.post(f"/api/transactions/{txn.id}/mark-debt", json={
            "counterparty_name": "Alice"
        })
        
        assert response.status_code == 400
        assert "INFLOW" in response.json()["detail"]
    
    def test_mark_as_debt_not_found(self, client):
        """Should return 404 if transaction doesn't exist."""
        response = client.post("/api/transactions/99999/mark-debt", json={
            "counterparty_name": "Alice"
        })
        
        assert response.status_code == 400


class TestEndToEndWorkflows:
    """End-to-end tests for common workflows."""
    
    def test_loan_and_repayment_workflow(self, client, test_db, sample_wallet):
        """Test complete loan workflow: lend money, receive repayment."""
        from app.services import transaction_service
        from app.schemas.transaction import TransactionCreate
        
        # 1. Create OUTFLOW transaction (lending money)
        txn = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 7),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.OUTFLOW,
                amount=Decimal("5000.00"),
                classification=TransactionClassification.EXPENSE,
                description="Lend to Bob"
            )
        )
        
        # 2. Mark as loan
        loan_response = client.post(f"/api/transactions/{txn.id}/mark-loan", json={
            "counterparty_name": "Bob"
        })
        assert loan_response.status_code == 200
        linked_entry_id = loan_response.json()["id"]
        
        # 3. Create repayment transaction (INFLOW)
        repayment = transaction_service.create_transaction(
            test_db,
            TransactionCreate(
                date=date(2025, 12, 15),
                wallet_id=sample_wallet.id,
                direction=TransactionDirection.INFLOW,
                amount=Decimal("5000.00"),
                classification=TransactionClassification.INCOME,
                description="Bob repayment"
            )
        )
        
        # 4. Link repayment to loan
        link_response = client.post("/api/transactions/link", json={
            "linked_entry_id": linked_entry_id,
            "transaction_ids": [repayment.id]
        })
        assert link_response.status_code == 200
        
        # 5. Verify loan is settled
        entry_data = link_response.json()
        assert entry_data["status"] == "settled"
        assert entry_data["pending_amount"] == "0.00"
        
        # 6. Verify repayment transaction classification changed
        repayment_response = client.get(f"/api/transactions/{repayment.id}")
        assert repayment_response.json()["classification"] == "debt_collection"
    
    def test_wallet_transfer_workflow(self, client, test_db, sample_wallet):
        """Test wallet transfer affects both wallet balances."""
        from app.models.wallet import Wallet, WalletType
        from app.services import wallet_service
        
        # Create second wallet
        wallet2 = Wallet(
            name="Savings",
            wallet_type=WalletType.NORMAL
        )
        test_db.add(wallet2)
        test_db.commit()
        test_db.refresh(wallet2)
        
        from app.models.transaction import Transaction
        txn = Transaction(
            wallet_id=wallet2.id,
            amount=Decimal("2000.00"),
            direction=TransactionDirection.INFLOW,
            classification=TransactionClassification.INCOME,
            description="INITIAL BALANCE",
            date=date(2025, 12, 1),
            is_ignored=True
        )
        test_db.add(txn)
        test_db.commit()
        
        # Get initial balances
        initial_balance1 = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
        initial_balance2 = wallet_service.calculate_wallet_balance(test_db, wallet2.id)
        
        # Create transfer
        transfer_amount = Decimal("3000.00")
        response = client.post("/api/wallets/transfer", json={
            "from_wallet_id": sample_wallet.id,
            "to_wallet_id": wallet2.id,
            "amount": float(transfer_amount),
            "date": "2025-12-07"
        })
        
        assert response.status_code == 200
        
        # Verify balances updated
        final_balance1 = wallet_service.calculate_wallet_balance(test_db, sample_wallet.id)
        final_balance2 = wallet_service.calculate_wallet_balance(test_db, wallet2.id)
        
        assert final_balance1 == initial_balance1 - transfer_amount
        assert final_balance2 == initial_balance2 + transfer_amount
