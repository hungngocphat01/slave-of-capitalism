
from decimal import Decimal
from datetime import date
import pytest
from app.models.wallet import WalletType
from app.models.transaction import TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkType
from app.schemas.wallet import WalletCreate
from app.schemas.transaction import TransactionCreate
from app.schemas.linked_entry import LinkedEntryCreate
from app.services import wallet_service, transaction_service, linked_entry_service

def test_reproduction_bug_40k(test_db):
    # 0. Setup Credit Wallet (Limit 100k)
    wallet = wallet_service.create_wallet(test_db, WalletCreate(
        name="Credit Card",
        wallet_type=WalletType.CREDIT,
        currency="VND",
        initial_balance=Decimal("0.00"),
        credit_limit=Decimal("100000.00")
    ))
    
    # helper to check state
    def check(step_name, expected_balance, expected_pending, expected_used):
        bal = wallet_service.calculate_wallet_balance(test_db, wallet.id)
        pending = linked_entry_service.calculate_pending_installments(test_db, wallet.id)
        # Used = Balance (Debt) + Pending
        # Note: Balance for Credit Wallet is positive for Debt in some contexts? 
        # let's check calculate_wallet_balance implementation.
        # It returns positive for debt usually?
        # In wallet_service.py: 
        # if wallet.wallet_type == WalletType.CREDIT:
        #     balance_change = outflow_sum - inflow_sum
        #     final_balance = start_balance + balance_change
        # So YES, positive balance = Debt.
        
        used = bal + pending
        print(f"\n[{step_name}] Bal={bal}, Pending={pending}, Used={used}")
        
        # We assert strictly to catch the bug
        assert bal == expected_balance, f"{step_name}: Balance mismatch"
        assert pending == expected_pending, f"{step_name}: Pending mismatch"
        assert used == expected_used, f"{step_name}: Used Credit mismatch"

    # 1. Create Installment Plan (30k) via Transaction Service
    txn_plan = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date.today(),
        wallet_id=wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("30000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Plan 30k"
    ))
    
    # Use the service method that the UI uses
    from app.schemas.linked_entry import MarkAsLoanRequest
    transaction_service.mark_as_installment(test_db, txn_plan.id, MarkAsLoanRequest(
        counterparty_name="Store"
    ))
    
    # Expect: Bal=0, Pending=30k, Used=30k
    # BUG: If mark_as_installment fails to set RESERVED, Bal will be 30k
    check("Step 1 (Plan 30k)", Decimal("0"), Decimal("30000"), Decimal("30000"))
    
    # 2. Charge 1 (10k) - repayment transaction 1
    charge1 = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date.today(),
        wallet_id=wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("10000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Charge 1"
    ))
    
    # Link it
    entry = linked_entry_service.get_linked_entries(test_db, link_type=LinkType.INSTALLMENT)[0]
    linked_entry_service.link_transaction(test_db, entry.id, charge1.id)
    
    # Expect: Bal=10k, Pending=20k, Used=30k
    check("Step 2 (Charge 10k)", Decimal("10000"), Decimal("20000"), Decimal("30000"))
    
    # 3. Charge 2 (10k) - repayment transaction 2
    charge2 = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date.today(),
        wallet_id=wallet.id,
        direction=TransactionDirection.OUTFLOW, # Charge is outflow
        amount=Decimal("10000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Charge 2"
    ))
    linked_entry_service.link_transaction(test_db, entry.id, charge2.id)
    
    # Expect: Bal=20k, Pending=10k, Used=30k
    check("Step 3 (Charge 10k)", Decimal("20000"), Decimal("10000"), Decimal("30000"))
    
    # 4. Payback 10k (Transfer Inflow)
    payback = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date.today(),
        wallet_id=wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("10000.00"),
        classification=TransactionClassification.TRANSFER,
        description="Payback 10k"
    ))
    
    # Expect: Bal=10k (20-10), Pending=10k, Used=20k
    # User sees Used=40k here?
    check("Step 4 (Payback 10k)", Decimal("10000"), Decimal("10000"), Decimal("20000"))
