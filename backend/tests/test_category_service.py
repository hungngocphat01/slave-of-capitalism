"""Tests for category service."""
import pytest
from sqlalchemy.orm import Session

from app.models.category import Category
from app.models.subcategory import Subcategory
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.wallet import Wallet
from app.schemas.category import CategoryCreate, CategoryUpdate, SubcategoryCreate, SubcategoryUpdate
from app.services import category_service
from datetime import date
from decimal import Decimal


@pytest.fixture
def sample_wallet(test_db: Session) -> Wallet:
    """Create a sample wallet for testing."""
    wallet = Wallet(name="Test Wallet")
    test_db.add(wallet)
    test_db.commit()
    test_db.refresh(wallet)
    
    # Add initial balance transaction
    from app.models.transaction import Transaction
    txn = Transaction(
        wallet_id=wallet.id,
        amount=Decimal("1000.00"),
        direction=TransactionDirection.INFLOW,
        classification=TransactionClassification.INCOME,
        description="INITIAL BALANCE",
        date=date(2024, 1, 1),
        is_ignored=True
    )
    test_db.add(txn)
    test_db.commit()
    
    return wallet


@pytest.fixture
def sample_category(test_db: Session) -> Category:
    """Create a sample category for testing."""
    category = Category(name="Food", emoji="🍔", is_system=False)
    test_db.add(category)
    test_db.commit()
    test_db.refresh(category)
    return category


@pytest.fixture
def system_category(test_db: Session) -> Category:
    """Create a system category for testing."""
    category = Category(name="System Food", emoji="🍕", is_system=True)
    test_db.add(category)
    test_db.commit()
    test_db.refresh(category)
    return category


@pytest.fixture
def sample_subcategory(test_db: Session, sample_category: Category) -> Subcategory:
    """Create a sample subcategory for testing."""
    subcategory = Subcategory(
        category_id=sample_category.id,
        name="Dining Out",
        is_system=False
    )
    test_db.add(subcategory)
    test_db.commit()
    test_db.refresh(subcategory)
    return subcategory


class TestCategoryBasicOperations:
    """Test basic CRUD operations for categories."""

    def test_create_category(self, test_db: Session):
        """Test creating a new category."""
        category_data = CategoryCreate(name="Transport", emoji="🚗", color="#FF5733")
        category = category_service.create_category(test_db, category_data)
        
        assert category.id is not None
        assert category.name == "Transport"
        assert category.emoji == "🚗"
        assert category.color == "#FF5733"
        assert category.is_system is False

    def test_get_category(self, test_db: Session, sample_category: Category):
        """Test retrieving a category by ID."""
        category = category_service.get_category(test_db, sample_category.id)
        
        assert category is not None
        assert category.id == sample_category.id
        assert category.name == sample_category.name

    def test_get_category_not_found(self, test_db: Session):
        """Test retrieving a non-existent category."""
        category = category_service.get_category(test_db, 99999)
        assert category is None

    def test_get_categories(self, test_db: Session, sample_category: Category):
        """Test listing all categories."""
        categories = category_service.get_categories(test_db)
        
        assert len(categories) >= 1
        assert any(c.id == sample_category.id for c in categories)

    def test_update_category(self, test_db: Session, sample_category: Category):
        """Test updating a category."""
        update_data = CategoryUpdate(name="Updated Food", emoji="🍕")
        updated = category_service.update_category(test_db, sample_category.id, update_data)
        
        assert updated is not None
        assert updated.name == "Updated Food"
        assert updated.emoji == "🍕"

    def test_update_category_not_found(self, test_db: Session):
        """Test updating a non-existent category."""
        update_data = CategoryUpdate(name="Ghost")
        updated = category_service.update_category(test_db, 99999, update_data)
        assert updated is None

    def test_delete_category_simple(self, test_db: Session):
        """Test deleting a category without transactions."""
        category = Category(name="Temporary", emoji="⏱️", is_system=False)
        test_db.add(category)
        test_db.commit()
        test_db.refresh(category)
        
        deleted = category_service.delete_category(test_db, category.id)
        assert deleted is True
        
        # Verify it's gone
        category = category_service.get_category(test_db, category.id)
        assert category is None

    def test_delete_system_category_fails(self, test_db: Session, system_category: Category):
        """Test that system categories cannot be deleted."""
        with pytest.raises(ValueError, match="System categories cannot be deleted"):
            category_service.delete_category(test_db, system_category.id)
        
        # Verify it still exists
        category = category_service.get_category(test_db, system_category.id)
        assert category is not None


class TestSubcategoryBasicOperations:
    """Test basic CRUD operations for subcategories."""

    def test_create_subcategory(self, test_db: Session, sample_category: Category):
        """Test creating a new subcategory."""
        subcategory_data = SubcategoryCreate(name="Fast Food")
        subcategory = category_service.create_subcategory(test_db, sample_category.id, subcategory_data)
        
        assert subcategory is not None
        assert subcategory.name == "Fast Food"
        assert subcategory.category_id == sample_category.id
        assert subcategory.is_system is False

    def test_create_subcategory_invalid_category(self, test_db: Session):
        """Test creating a subcategory with invalid category ID."""
        subcategory_data = SubcategoryCreate(name="Ghost Sub")
        subcategory = category_service.create_subcategory(test_db, 99999, subcategory_data)
        assert subcategory is None

    def test_get_subcategory(self, test_db: Session, sample_subcategory: Subcategory):
        """Test retrieving a subcategory by ID."""
        subcategory = category_service.get_subcategory(test_db, sample_subcategory.id)
        
        assert subcategory is not None
        assert subcategory.id == sample_subcategory.id
        assert subcategory.name == sample_subcategory.name

    def test_update_subcategory(self, test_db: Session, sample_subcategory: Subcategory):
        """Test updating a subcategory."""
        update_data = SubcategoryUpdate(name="Updated Dining")
        updated = category_service.update_subcategory(test_db, sample_subcategory.id, update_data)
        
        assert updated is not None
        assert updated.name == "Updated Dining"

    def test_delete_subcategory_simple(self, test_db: Session, sample_category: Category):
        """Test deleting a subcategory without transactions."""
        subcategory = Subcategory(
            category_id=sample_category.id,
            name="Temporary Sub",
            is_system=False
        )
        test_db.add(subcategory)
        test_db.commit()
        test_db.refresh(subcategory)
        
        deleted = category_service.delete_subcategory(test_db, subcategory.id)
        assert deleted is True
        
        # Verify it's gone
        subcategory = category_service.get_subcategory(test_db, subcategory.id)
        assert subcategory is None


class TestCategoryDeletionWithReplacement:
    """Test category deletion with transaction replacement logic."""

    def test_delete_category_with_transactions_requires_replacement(
        self, test_db: Session, sample_category: Category, sample_wallet: Wallet
    ):
        """Test that deleting a category with transactions requires a replacement."""
        # Create a transaction with this category
        transaction = Transaction(
            date=date(2024, 1, 1),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("50.00"),
            classification=TransactionClassification.EXPENSE,
            category_id=sample_category.id,
            description="Test expense"
        )
        test_db.add(transaction)
        test_db.commit()
        
        # Attempt to delete without replacement should fail
        with pytest.raises(ValueError, match="replacement category"):
            category_service.delete_category(
                test_db, sample_category.id, replacement_category_id=None
            )

    def test_delete_category_with_replacement_category(
        self, test_db: Session, sample_category: Category, sample_wallet: Wallet
    ):
        """Test deleting a category and replacing transactions with another category."""
        # Create replacement category
        replacement = Category(name="Other", emoji="📦", is_system=False)
        test_db.add(replacement)
        test_db.commit()
        test_db.refresh(replacement)
        
        # Create transactions with the category to be deleted
        transaction1 = Transaction(
            date=date(2024, 1, 1),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("50.00"),
            classification=TransactionClassification.EXPENSE,
            category_id=sample_category.id,
            description="Test expense 1"
        )
        transaction2 = Transaction(
            date=date(2024, 1, 2),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("30.00"),
            classification=TransactionClassification.EXPENSE,
            category_id=sample_category.id,
            description="Test expense 2"
        )
        test_db.add_all([transaction1, transaction2])
        test_db.commit()
        
        # Delete with replacement
        deleted = category_service.delete_category(
            test_db, sample_category.id, replacement_category_id=replacement.id
        )
        
        assert deleted is True
        
        # Verify category is deleted
        assert category_service.get_category(test_db, sample_category.id) is None
        
        # Verify transactions are reassigned
        test_db.refresh(transaction1)
        test_db.refresh(transaction2)
        assert transaction1.category_id == replacement.id
        assert transaction2.category_id == replacement.id
        assert transaction1.subcategory_id is None
        assert transaction2.subcategory_id is None

    def test_delete_category_with_replacement_subcategory(
        self, test_db: Session, sample_category: Category, sample_wallet: Wallet
    ):
        """Test deleting a category and replacing transactions with a subcategory."""
        # Create replacement category and subcategory
        replacement_cat = Category(name="Other", emoji="📦", is_system=False)
        test_db.add(replacement_cat)
        test_db.commit()
        test_db.refresh(replacement_cat)
        
        replacement_sub = Subcategory(
            category_id=replacement_cat.id,
            name="Miscellaneous",
            is_system=False
        )
        test_db.add(replacement_sub)
        test_db.commit()
        test_db.refresh(replacement_sub)
        
        # Create transaction with the category to be deleted
        transaction = Transaction(
            date=date(2024, 1, 1),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("50.00"),
            classification=TransactionClassification.EXPENSE,
            category_id=sample_category.id,
            description="Test expense"
        )
        test_db.add(transaction)
        test_db.commit()
        
        # Delete with subcategory replacement
        deleted = category_service.delete_category(
            test_db,
            sample_category.id,
            replacement_category_id=replacement_cat.id,
            replacement_subcategory_id=replacement_sub.id
        )
        
        assert deleted is True
        
        # Verify transaction is reassigned to subcategory
        test_db.refresh(transaction)
        assert transaction.category_id == replacement_cat.id
        assert transaction.subcategory_id == replacement_sub.id

    def test_delete_subcategory_with_replacement(
        self, test_db: Session, sample_category: Category, sample_subcategory: Subcategory, sample_wallet: Wallet
    ):
        """Test deleting a subcategory and replacing transactions."""
        # Create replacement subcategory
        replacement_sub = Subcategory(
            category_id=sample_category.id,
            name="Takeout",
            is_system=False
        )
        test_db.add(replacement_sub)
        test_db.commit()
        test_db.refresh(replacement_sub)
        
        # Create transaction with the subcategory to be deleted
        transaction = Transaction(
            date=date(2024, 1, 1),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("50.00"),
            classification=TransactionClassification.EXPENSE,
            category_id=sample_category.id,
            subcategory_id=sample_subcategory.id,
            description="Test expense"
        )
        test_db.add(transaction)
        test_db.commit()
        
        # Delete with replacement
        deleted = category_service.delete_subcategory(
            test_db,
            sample_subcategory.id,
            replacement_category_id=sample_category.id,
            replacement_subcategory_id=replacement_sub.id
        )
        
        assert deleted is True
        
        # Verify transaction is reassigned
        test_db.refresh(transaction)
        assert transaction.subcategory_id == replacement_sub.id

    def test_delete_subcategory_with_category_only_replacement(
        self, test_db: Session, sample_category: Category, sample_subcategory: Subcategory, sample_wallet: Wallet
    ):
        """Test deleting a subcategory and replacing with just a category (no subcategory)."""
        # Create transaction with the subcategory to be deleted
        transaction = Transaction(
            date=date(2024, 1, 1),
            wallet_id=sample_wallet.id,
            direction=TransactionDirection.OUTFLOW,
            amount=Decimal("50.00"),
            classification=TransactionClassification.EXPENSE,
            category_id=sample_category.id,
            subcategory_id=sample_subcategory.id,
            description="Test expense"
        )
        test_db.add(transaction)
        test_db.commit()
        
        # Delete with category-only replacement
        deleted = category_service.delete_subcategory(
            test_db,
            sample_subcategory.id,
            replacement_category_id=sample_category.id,
            replacement_subcategory_id=None
        )
        
        assert deleted is True
        
        # Verify transaction is reassigned to category only
        test_db.refresh(transaction)
        assert transaction.category_id == sample_category.id
        assert transaction.subcategory_id is None

    def test_cannot_delete_system_category_even_with_replacement(
        self, test_db: Session, system_category: Category
    ):
        """Test that system categories cannot be deleted even with replacement."""
        replacement = Category(name="Other", emoji="📦", is_system=False)
        test_db.add(replacement)
        test_db.commit()
        
        with pytest.raises(ValueError, match="System categories cannot be deleted"):
            category_service.delete_category(
                test_db, system_category.id, replacement_category_id=replacement.id
            )
