import pytest
from sqlalchemy.orm import Session
from app.models.category import Category
from app.utils.seed_data import seed_categories
from app.services.category_service import delete_category

def test_system_categories_initialization(test_db: Session):
    """Test that system categories are initialized correctly."""
    # 1. Run seed on empty DB
    seed_categories(test_db)
    
    # 2. Verify "Miscellaneous" exists and is system
    misc_cat = test_db.query(Category).filter(Category.name == "Miscellaneous").first()
    assert misc_cat is not None
    assert misc_cat.is_system is True
    
    # 3. Verify "Unexpected expenses" exists and is system
    unexpected_cat = test_db.query(Category).filter(Category.name == "Unexpected expenses").first()
    assert unexpected_cat is not None
    assert unexpected_cat.is_system is True

def test_system_categories_cannot_be_deleted(test_db: Session):
    """Test that system categories cannot be deleted."""
    # 1. Seed
    seed_categories(test_db)
    
    # 2. Get Miscellaneous
    misc_cat = test_db.query(Category).filter(Category.name == "Miscellaneous").first()
    assert misc_cat is not None
    
    # 3. Attempt delete - should raise ValueError
    with pytest.raises(ValueError, match="System categories cannot be deleted"):
        delete_category(test_db, misc_cat.id)
    
    # 4. Verify it still exists
    misc_cat_check = test_db.query(Category).filter(Category.id == misc_cat.id).first()
    assert misc_cat_check is not None

def test_ensure_system_categories_updates_existing(test_db: Session):
    """Test that seeding updates existing categories to be system categories if they match names."""
    # 1. Create "Miscellaneous" manually as NON-system
    misc_cat = Category(
        name="Miscellaneous",
        emoji="❓",
        color="#000000",
        is_system=False
    )
    test_db.add(misc_cat)
    
    # Create "Unexpected expenses" manually as NON-system
    ue_cat = Category(
        name="Unexpected expenses",
        emoji="❗",
        color="#000000",
        is_system=False
    )
    test_db.add(ue_cat)
    test_db.commit()
    
    # 2. Run seed
    # Current implementation of seed_categories skips if ANY category exists.
    # We will modify it to properly handle this case.
    seed_categories(test_db)
    
    # 3. Refresh and Verify
    test_db.refresh(misc_cat)
    test_db.refresh(ue_cat)
    
    assert misc_cat.is_system is True
    assert ue_cat.is_system is True
