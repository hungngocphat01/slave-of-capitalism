
from decimal import Decimal
from datetime import date
import pytest
from app.models.wallet import WalletType
from app.models.transaction import TransactionDirection, TransactionClassification, Transaction
from app.models.linked_entry import LinkType, LinkStatus
from app.schemas.wallet import WalletCreate
from app.schemas.transaction import TransactionCreate
from app.schemas.linked_entry import LinkedEntryCreate
from app.services import wallet_service, transaction_service, linked_entry_service

def test_installment_flow_user_story(test_db):
    """
    Test the full user story for Installment Flow:
    1. Purchase 24M Laptop (Plan) -> Check Balance/Limit
    2. Pay 2M (Charge) -> Check Balance/Limit
    3. Pay Off Card -> Check Balance/Limit
    """
    # Setup: Create Credit Wallet
    wallet = wallet_service.create_wallet(test_db, WalletCreate(
        name="Credit Card",
        wallet_type=WalletType.CREDIT,
        currency="VND",
        initial_balance=Decimal("0.00"),
        credit_limit=Decimal("50000000.00") # 50M Limit
    ))
    
    # 0. Initial State
    bal = wallet_service.calculate_wallet_balance(test_db, wallet.id)
    avail = wallet_service.calculate_available_credit(test_db, wallet.id)
    assert bal == Decimal("0.00")
    assert avail == Decimal("50000000.00")
    
    print("\n[Step 0] Initial: Balance=0, Avail=50M")

    # 1. The Purchase (Day 0) - Create Plan
    # Create Transaction
    txn_plan = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date.today(),
        wallet_id=wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("24000000.00"),
        classification=TransactionClassification.EXPENSE, # Start as expense
        description="Buy Laptop"
    ))
    
    # Convert to Installment using the service method
    # This properly sets direction=RESERVED and classification=INSTALLMENT
    from app.schemas.linked_entry import MarkAsLoanRequest
    transaction_service.mark_as_installment(test_db, txn_plan.id, MarkAsLoanRequest(
        counterparty_name="Store",
        notes=None
    ))
    
    # Verify Step 1
    # Balance should specify 0 (Excluded)
    # Available should be 50M - 24M = 26M
    bal_1 = wallet_service.calculate_wallet_balance(test_db, wallet.id)
    avail_1 = wallet_service.calculate_available_credit(test_db, wallet.id)
    
    print(f"[Step 1] After Plan: Balance={bal_1}, Avail={avail_1}")
    
    # Reload txn_plan to check updates
    test_db.refresh(txn_plan)
    assert txn_plan.direction == TransactionDirection.RESERVED, "Plan should be converted to RESERVED direction"
    assert txn_plan.classification == TransactionClassification.INSTALLMENT

    assert bal_1 == Decimal("0.00"), "Plan should NOT affect wallet balance"
    assert avail_1 == Decimal("26000000.00"), "Plan MUST reserve credit limit"

    # 2. The First Statement (Month 1) - Charge 2M
    # Create Charge Transaction
    txn_charge = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date.today(),
        wallet_id=wallet.id,
        direction=TransactionDirection.OUTFLOW, # Charge on card is outflow
        amount=Decimal("2000000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Installment 1/12"
    ))
    
    # Link to Plan
    # This automatically reclassifies txn_charge to INSTALLMT_CHRGE
    # and reduces pending amount of the plan
    entry = linked_entry_service.get_linked_entries(test_db, link_type=LinkType.INSTALLMENT)[0]
    linked_entry_service.link_transaction(test_db, entry.id, txn_charge.id)
    
    # Verify Step 2
    # Balance should be 2M (Real Debt)
    # Available should still be 26M (50 - 2M Real - 22M Pending)
    bal_2 = wallet_service.calculate_wallet_balance(test_db, wallet.id)
    avail_2 = wallet_service.calculate_available_credit(test_db, wallet.id)
    
    print(f"[Step 2] After Charge: Balance={bal_2}, Avail={avail_2}")
    
    assert bal_2 == Decimal("2000000.00"), "Charge MUST affect wallet balance"
    assert avail_2 == Decimal("26000000.00"), "Available credit should remain constant during charge realization"
    
    # 3. Paying the Credit Card Bill (Month 1 Payment)
    # Transfer 2M into the wallet
    txn_pay = transaction_service.create_transaction(test_db, TransactionCreate(
        date=date.today(),
        wallet_id=wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("2000000.00"),
        classification=TransactionClassification.TRANSFER, # Repaying card
        description="Pay Card Bill"
    ))
    
    # Verify Step 3
    # Balance should be 0 (Paid off)
    # Available should be 28M (50 - 0 Real - 22M Pending)
    bal_3 = wallet_service.calculate_wallet_balance(test_db, wallet.id)
    avail_3 = wallet_service.calculate_available_credit(test_db, wallet.id)
    
    print(f"[Step 3] After Payment: Balance={bal_3}, Avail={avail_3}")
    
    assert bal_3 == Decimal("0.00"), "Payment should clear balance"
    assert avail_3 == Decimal("28000000.00"), "Payment should free up credit limit"
