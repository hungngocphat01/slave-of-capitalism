import pytest
from datetime import date
from decimal import Decimal
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base, get_db
from app.main import app
from app.models.wallet import Wallet, WalletType
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkedEntry, LinkType, LinkStatus
from app.services import wallet_service

# Setup Test Database
SQLALCHEMY_DATABASE_URL = "sqlite:///./test_audit.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture(scope="module")
def db_engine():
    Base.metadata.create_all(bind=engine)
    yield engine
    Base.metadata.drop_all(bind=engine)
    import os
    if os.path.exists("./test_audit.db"):
        os.remove("./test_audit.db")

@pytest.fixture(scope="function")
def db(db_engine):
    connection = db_engine.connect()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)
    yield session
    session.close()
    transaction.rollback()
    connection.close()

@pytest.fixture(scope="function")
def client(db):
    def override_get_db():
        yield db
    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    del app.dependency_overrides[get_db]

def test_server_side_audit_calculation(db, client):
    """
    Test that the server accurately calculates:
    - Balances for Normal and Credit wallets
    - Total Debts from Linked Entries
    - Total Owed from Linked Entries
    - Net Position correctly
    """
    
    # 1. Setup Wallets
    wallet_normal = Wallet(name="Cash", wallet_type=WalletType.NORMAL, emoji="💰")
    wallet_credit = Wallet(name="Credit Card", wallet_type=WalletType.CREDIT, emoji="💳", credit_limit=Decimal("1000"))
    db.add_all([wallet_normal, wallet_credit])
    db.commit()
    
    # 2. Add Transactions (Today)
    today = date.today()
    
    # Normal: +1000 Inflow
    t1 = Transaction(
        date=today, wallet_id=wallet_normal.id, direction=TransactionDirection.INFLOW,
        amount=Decimal("1000"), classification=TransactionClassification.INCOME, description="Salary"
    )
    # Credit: 300 Outflow (Spending)
    t2 = Transaction(
        date=today, wallet_id=wallet_credit.id, direction=TransactionDirection.OUTFLOW,
        amount=Decimal("300"), classification=TransactionClassification.EXPENSE, description="Shopping"
    )
    db.add_all([t1, t2])
    db.commit()
    
    # Check Balances so far
    # Normal: 1000
    # Credit: 300 (Used)
    
    # 3. Setup Debts and Owed (Linked Entries)
    # Owed: I paid 100 for someone (Split) -> Pending 100
    # Need a primary transaction for LinkedEntry.
    t_split = Transaction(
        date=today, wallet_id=wallet_normal.id, direction=TransactionDirection.OUTFLOW,
        amount=Decimal("100"), classification=TransactionClassification.SPLIT_PAYMENT, description="Dinner"
    )
    db.add(t_split)
    db.commit()
    
    owed_entry = LinkedEntry(
        link_type=LinkType.SPLIT_PAYMENT,
        primary_transaction_id=t_split.id,
        counterparty_name="Friend",
        total_amount=Decimal("100"),
        user_amount=Decimal("0"), # I paid all 100, my share is 0 (generous), so they owe 100
        pending_amount=Decimal("100"),
        status=LinkStatus.PENDING
    )
    
    # Debts: I borrowed 50 -> Pending 50
    # Debt requires an INFLOW transaction with BORROW classification
    t_debt = Transaction(
        date=today, wallet_id=wallet_normal.id, direction=TransactionDirection.INFLOW,
        amount=Decimal("50"), classification=TransactionClassification.BORROW, description="Loan from mom"
    )
    db.add(t_debt)
    db.commit()
    
    debt_entry = LinkedEntry(
        link_type=LinkType.DEBT,
        primary_transaction_id=t_debt.id,
        counterparty_name="Mom",
        total_amount=Decimal("50"),
        pending_amount=Decimal("50"),
        status=LinkStatus.PENDING
    )
    
    db.add_all([owed_entry, debt_entry])
    db.commit()
    
    # Balances Update:
    # Normal: 1000 (In) - 100 (Split Out) + 50 (Borrow In) = 950
    # Credit: 300
    
    # Expected Audit Values:
    # Owed: 100
    # Debts: 50
    # Net Position = (Normal - Credit) - Debts + Owed
    # Net Position = (950 - 300) - 50 + 100 = 650 - 50 + 100 = 700
    
    # 4. Trigger Server-Side Audit
    audit_date = today.isoformat()
    response = client.post("/api/wallets/audits", json={"date": audit_date})
    
    assert response.status_code == 200
    data = response.json()
    
    print("Audit Response:", data)
    
    # 5. Assertions
    # Verify Balances
    balances = data["balances"]
    assert balances[str(wallet_normal.id)] == 950.0
    assert balances[str(wallet_credit.id)] == 300.0
    
    # Verify Debts/Owed
    assert float(data["debts"]) == 50.0
    assert float(data["owed"]) == 100.0
    
    # Verify Net Position
    expected_net = (950 - 300) - 50 + 100
    assert float(data["net_position"]) == float(expected_net)
    
    print("Test Passed: Server-side audit calculation is correct.")
