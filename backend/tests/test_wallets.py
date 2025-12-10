
import pytest
from decimal import Decimal
from app.models.wallet import Wallet, WalletType
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.services import wallet_service, transaction_service
from app.schemas.wallet import WalletCreate, WalletUpdate
from app.schemas.transaction import TransactionCreate

def test_create_wallet_with_emoji(test_db):
    """Test creating a wallet with an emoji."""
    wallet_data = WalletCreate(
        name="Travel Fund",
        wallet_type=WalletType.NORMAL,
        initial_balance=Decimal("1000.00"),
        emoji="✈️"
    )
    wallet = wallet_service.create_wallet(test_db, wallet_data)
    
    assert wallet.name == "Travel Fund"
    assert wallet.emoji == "✈️"
    
def test_update_wallet_emoji(test_db):
    """Test updating a wallet's emoji."""
    wallet_data = WalletCreate(
        name="Food",
        wallet_type=WalletType.NORMAL,
        emoji="🍔"
    )
    wallet = wallet_service.create_wallet(test_db, wallet_data)
    
    update_data = WalletUpdate(emoji="🍕")
    updated_wallet = wallet_service.update_wallet(test_db, wallet.id, update_data)
    
    assert updated_wallet.emoji == "🍕"

def test_delete_wallet_restriction(test_db):
    """Test that a wallet cannot be deleted if it has transactions."""
    # Create wallet
    wallet = wallet_service.create_wallet(test_db, WalletCreate(name="Main Bank"))
    
    # Add transaction
    txn_data = TransactionCreate(
        date="2023-01-01",
        description="Salary",
        amount=Decimal("5000"),
        direction=TransactionDirection.INFLOW,
        classification=TransactionClassification.INCOME,
        wallet_id=wallet.id
    )
    # Using transaction service or just creating model directly for speed
    # Let's use service if possible, or just add to DB
    txn = Transaction(
        date=txn_data.date,
        description=txn_data.description,
        amount=Decimal(str(txn_data.amount)),
        direction=TransactionDirection.INFLOW,
        classification=TransactionClassification.INCOME,
        wallet_id=wallet.id
    )
    test_db.add(txn)
    test_db.commit()
    
    # Try to delete
    try:
        wallet_service.delete_wallet(test_db, wallet.id)
        assert False, "Should have raised ValueError"
    except ValueError as e:
        assert str(e) == "Cannot delete wallet with existing transactions"

    # Delete transaction then wallet
    test_db.delete(txn)
    test_db.commit()
    
    result = wallet_service.delete_wallet(test_db, wallet.id)
    assert result is True


def test_wallet_transfer(test_db):
    """Test creating a transfer between two wallets."""
    from datetime import date
    
    # Create two wallets
    wallet1 = wallet_service.create_wallet(test_db, WalletCreate(
        name="Bank Account",
        wallet_type=WalletType.NORMAL,
        initial_balance=Decimal("10000.00")
    ))
    
    wallet2 = wallet_service.create_wallet(test_db, WalletCreate(
        name="Cash",
        wallet_type=WalletType.NORMAL,
        initial_balance=Decimal("0.00")
    ))
    
    # Create transfer transactions
    transfer_amount = Decimal("5000.00")
    transfer_date = date(2025, 12, 7)
    
    # Create outflow transaction
    outflow_txn = Transaction(
        date=transfer_date,
        wallet_id=wallet1.id,
        direction=TransactionDirection.OUTFLOW,
        amount=transfer_amount,
        classification=TransactionClassification.TRANSFER,
        description="Transfer to Cash"
    )
    test_db.add(outflow_txn)
    test_db.flush()
    
    # Create inflow transaction
    inflow_txn = Transaction(
        date=transfer_date,
        wallet_id=wallet2.id,
        direction=TransactionDirection.INFLOW,
        amount=transfer_amount,
        classification=TransactionClassification.TRANSFER,
        description="Transfer from Bank",
        paired_transaction_id=outflow_txn.id
    )
    test_db.add(inflow_txn)
    test_db.flush()
    
    # Link them
    outflow_txn.paired_transaction_id = inflow_txn.id
    test_db.commit()
    
    # Verify balances
    bank_balance = wallet_service.calculate_wallet_balance(test_db, wallet1.id)
    cash_balance = wallet_service.calculate_wallet_balance(test_db, wallet2.id)
    
    assert bank_balance == Decimal("5000.00")  # 10000 - 5000
    assert cash_balance == Decimal("5000.00")  # 0 + 5000
    
    # Verify transactions are paired
    test_db.refresh(outflow_txn)
    test_db.refresh(inflow_txn)
    assert outflow_txn.paired_transaction_id == inflow_txn.id
    assert inflow_txn.paired_transaction_id == outflow_txn.id

