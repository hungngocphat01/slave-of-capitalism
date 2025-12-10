"""Test configuration and fixtures for new transaction model."""
import pytest
from datetime import date
from decimal import Decimal
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from fastapi.testclient import TestClient

from app.database import Base, get_db
from app.main import app
from app.models.wallet import Wallet, WalletType
from app.models.category import Category
from app.models.subcategory import Subcategory
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.linked_entry import LinkedEntry, LinkedTransaction, LinkType, LinkStatus


@pytest.fixture(autouse=True)
def freeze_time():
    """Freeze time to a specific date for consistent testing."""
    from freezegun import freeze_time
    # Freeze to the date provided in metadata: 2025-12-08
    with freeze_time("2025-12-08"):
        yield

# Test database URL - in-memory SQLite
SQLALCHEMY_TEST_DATABASE_URL = "sqlite:///:memory:"


@pytest.fixture(scope="function")
def test_db():
    """Create a fresh test database for each test."""
    from sqlalchemy import event
    
    engine = create_engine(
        SQLALCHEMY_TEST_DATABASE_URL,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool  # Use StaticPool for in-memory SQLite
    )
    
    # Enable foreign key constraints for SQLite
    @event.listens_for(engine, "connect")
    def set_sqlite_pragma(dbapi_conn, connection_record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()
    
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    
    # Create all tables
    Base.metadata.create_all(bind=engine)
    
    # Create session
    db = TestingSessionLocal()
    
    try:
        yield db
    finally:
        db.close()
        # Drop all tables after test
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


@pytest.fixture(scope="function")
def client(test_db):
    """Create a test client with the test database."""
    from fastapi import FastAPI
    from fastapi.middleware.cors import CORSMiddleware
    
    # Create a test app without lifespan to avoid database conflicts
    test_app = FastAPI(
        title="Expense Manager API (Test)",
        description="Test instance",
        version="0.1.0",
    )
    
    # Configure CORS (same as main app)
    test_app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # Register routers (same as main app)
    from app.routers import wallets, wallets_extra, categories, transactions, transactions_extra, linked_entries, budgets
    
    test_app.include_router(wallets.router, prefix="/api/wallets", tags=["wallets"])
    test_app.include_router(wallets_extra.router, prefix="/api/wallets", tags=["wallets"])
    test_app.include_router(categories.router, prefix="/api/categories", tags=["categories"])
    test_app.include_router(transactions.router, prefix="/api/transactions", tags=["transactions"])
    test_app.include_router(transactions_extra.router, prefix="/api/transactions", tags=["transactions"])
    test_app.include_router(linked_entries.router, prefix="/api/linked-entries", tags=["linked-entries"])
    test_app.include_router(budgets.router, prefix="/api/budgets", tags=["budgets"])
    
    # Override get_db to use test database
    def override_get_db():
        try:
            yield test_db
        finally:
            pass
    
    test_app.dependency_overrides[get_db] = override_get_db
    
    with TestClient(test_app) as test_client:
        yield test_client
    
    test_app.dependency_overrides.clear()


@pytest.fixture
def sample_wallet(test_db):
    """Create a sample normal wallet with initial balance transaction."""
    # 1. Create Wallet (no initial_balance column)
    wallet = Wallet(
        name="Test Wallet",
        wallet_type=WalletType.NORMAL,
        credit_limit=Decimal("0.00")
    )
    test_db.add(wallet)
    test_db.commit()
    test_db.refresh(wallet)
    
    # 2. Add "INITIAL BALANCE" transaction
    # We want effective balance to be 10,000 for tests
    transaction = Transaction(
        date=date(2025, 1, 1), # Old date to be "initial"
        wallet_id=wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("10000.00"),
        classification=TransactionClassification.INCOME,
        description="INITIAL BALANCE",
        is_ignored=True
    )
    test_db.add(transaction)
    test_db.commit()
    
    return wallet


@pytest.fixture
def sample_credit_wallet(test_db):
    """Create a sample credit wallet."""
    wallet = Wallet(
        name="Test Credit Card",
        wallet_type=WalletType.CREDIT,
        credit_limit=Decimal("100000.00")
    )
    test_db.add(wallet)
    test_db.commit()
    test_db.refresh(wallet)
    return wallet


@pytest.fixture
def sample_category(test_db):
    """Create a sample category."""
    category = Category(
        name="Test Category",
        emoji="🧪",
        color="#FF0000",
        is_system=False
    )
    test_db.add(category)
    test_db.commit()
    test_db.refresh(category)
    return category


@pytest.fixture
def sample_expense(test_db, sample_wallet, sample_category):
    """Create a sample expense transaction."""
    transaction = Transaction(
        date=date(2025, 12, 6),
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.OUTFLOW,
        amount=Decimal("3000.00"),
        classification=TransactionClassification.EXPENSE,
        description="Test Expense",
        category_id=sample_category.id
    )
    test_db.add(transaction)
    test_db.commit()
    test_db.refresh(transaction)
    return transaction


@pytest.fixture
def sample_income(test_db, sample_wallet):
    """Create a sample income transaction."""
    transaction = Transaction(
        date=date(2025, 12, 6),
        wallet_id=sample_wallet.id,
        direction=TransactionDirection.INFLOW,
        amount=Decimal("5000.00"),
        classification=TransactionClassification.INCOME,
        description="Test Income"
    )
    test_db.add(transaction)
    test_db.commit()
    test_db.refresh(transaction)
    return transaction
