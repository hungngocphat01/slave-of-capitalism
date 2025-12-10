"""Category service with business logic."""
from sqlalchemy.orm import Session, joinedload

from app.models.category import Category
from app.models.subcategory import Subcategory
from app.schemas.category import CategoryCreate, CategoryUpdate, SubcategoryCreate, SubcategoryUpdate


# Category operations

def get_category(db: Session, category_id: int) -> Category | None:
    """
    Get category by ID with subcategories loaded.
    
    Args:
        db: Database session
        category_id: Category ID
        
    Returns:
        Category or None
    """
    return (
        db.query(Category)
        .options(joinedload(Category.subcategories))
        .filter(Category.id == category_id)
        .first()
    )


def get_categories(db: Session, skip: int = 0, limit: int = 100) -> list[Category]:
    """
    Get all categories with subcategories loaded.
    
    Args:
        db: Database session
        skip: Number of records to skip
        limit: Maximum number of records to return
        
    Returns:
        List of categories with subcategories
    """
    return (
        db.query(Category)
        .options(joinedload(Category.subcategories))
        .offset(skip)
        .limit(limit)
        .all()
    )


def create_category(db: Session, category: CategoryCreate) -> Category:
    """
    Create a new category.
    
    Args:
        db: Database session
        category: Category creation data
        
    Returns:
        Created category
    """
    db_category = Category(**category.model_dump(), is_system=False)
    db.add(db_category)
    db.commit()
    db.refresh(db_category)
    return db_category


def update_category(db: Session, category_id: int, category: CategoryUpdate) -> Category | None:
    """
    Update an existing category.
    
    Args:
        db: Database session
        category_id: Category ID
        category: Category update data
        
    Returns:
        Updated category or None if not found
    """
    db_category = get_category(db, category_id)
    if not db_category:
        return None
    
    update_data = category.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_category, field, value)
    
    db.commit()
    db.refresh(db_category)
    return db_category


def delete_category(
    db: Session,
    category_id: int,
    replacement_category_id: int | None = None,
    replacement_subcategory_id: int | None = None
) -> bool:
    """
    Delete a category.

    Note: System categories cannot be deleted.
    If the category has transactions, replacement_category_id must be provided.

    Args:
        db: Database session
        category_id: Category ID
        replacement_category_id: Optional category ID to reassign transactions to
        replacement_subcategory_id: Optional subcategory ID to reassign transactions to

    Returns:
        True if deleted, False if not found or system category
        
    Raises:
        ValueError: If category has transactions but no replacement provided, or if system category
    """
    from app.models.transaction import Transaction
    
    db_category = get_category(db, category_id)
    if not db_category:
        return False

    # Prevent deletion of system categories
    if db_category.is_system:
        raise ValueError("System categories cannot be deleted")
    
    # Check if there are transactions using this category
    transaction_count = (
        db.query(Transaction)
        .filter(Transaction.category_id == category_id)
        .count()
    )
    
    if transaction_count > 0:
        # Transactions exist, replacement is required
        if replacement_category_id is None:
            raise ValueError(
                f"Cannot delete category with {transaction_count} transactions. "
                "A replacement category must be provided."
            )
        
        # Verify replacement category exists
        replacement_category = get_category(db, replacement_category_id)
        if not replacement_category:
            raise ValueError(f"Replacement category {replacement_category_id} not found")
        
        # If replacement subcategory is provided, verify it exists and belongs to replacement category
        if replacement_subcategory_id is not None:
            replacement_subcategory = get_subcategory(db, replacement_subcategory_id)
            if not replacement_subcategory:
                raise ValueError(f"Replacement subcategory {replacement_subcategory_id} not found")
            if replacement_subcategory.category_id != replacement_category_id:
                raise ValueError(
                    f"Replacement subcategory {replacement_subcategory_id} does not belong to "
                    f"replacement category {replacement_category_id}"
                )
        
        # Reassign all transactions to the replacement
        db.query(Transaction).filter(Transaction.category_id == category_id).update({
            "category_id": replacement_category_id,
            "subcategory_id": replacement_subcategory_id
        })

    db.delete(db_category)
    db.commit()
    return True


# Subcategory operations

def get_subcategory(db: Session, subcategory_id: int) -> Subcategory | None:
    """Get subcategory by ID."""
    return db.query(Subcategory).filter(Subcategory.id == subcategory_id).first()


def create_subcategory(
    db: Session, category_id: int, subcategory: SubcategoryCreate
) -> Subcategory | None:
    """
    Create a new subcategory under a category.
    
    Args:
        db: Database session
        category_id: Parent category ID
        subcategory: Subcategory creation data
        
    Returns:
        Created subcategory or None if category not found
    """
    # Verify category exists
    category = get_category(db, category_id)
    if not category:
        return None
    
    db_subcategory = Subcategory(
        category_id=category_id,
        **subcategory.model_dump(),
        is_system=False
    )
    db.add(db_subcategory)
    db.commit()
    db.refresh(db_subcategory)
    return db_subcategory


def update_subcategory(
    db: Session, subcategory_id: int, subcategory: SubcategoryUpdate
) -> Subcategory | None:
    """Update an existing subcategory."""
    db_subcategory = get_subcategory(db, subcategory_id)
    if not db_subcategory:
        return None
    
    update_data = subcategory.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_subcategory, field, value)
    
    db.commit()
    db.refresh(db_subcategory)
    return db_subcategory


def delete_subcategory(
    db: Session,
    subcategory_id: int,
    replacement_category_id: int | None = None,
    replacement_subcategory_id: int | None = None
) -> bool:
    """
    Delete a subcategory.

    Note: System subcategories cannot be deleted.
    If the subcategory has transactions, replacement_category_id must be provided.

    Args:
        db: Database session
        subcategory_id: Subcategory ID
        replacement_category_id: Optional category ID to reassign transactions to
        replacement_subcategory_id: Optional subcategory ID to reassign transactions to

    Returns:
        True if deleted, False if not found
        
    Raises:
        ValueError: If subcategory has transactions but no replacement provided, or if system subcategory
    """
    from app.models.transaction import Transaction
    
    db_subcategory = get_subcategory(db, subcategory_id)
    if not db_subcategory:
        return False

    if db_subcategory.is_system:
        raise ValueError("System subcategories cannot be deleted")
    
    # Check if there are transactions using this subcategory
    transaction_count = (
        db.query(Transaction)
        .filter(Transaction.subcategory_id == subcategory_id)
        .count()
    )
    
    if transaction_count > 0:
        # Transactions exist, replacement is required
        if replacement_category_id is None:
            raise ValueError(
                f"Cannot delete subcategory with {transaction_count} transactions. "
                "A replacement category must be provided."
            )
        
        # Verify replacement category exists
        replacement_category = get_category(db, replacement_category_id)
        if not replacement_category:
            raise ValueError(f"Replacement category {replacement_category_id} not found")
        
        # If replacement subcategory is provided, verify it exists and belongs to replacement category
        if replacement_subcategory_id is not None:
            replacement_subcategory = get_subcategory(db, replacement_subcategory_id)
            if not replacement_subcategory:
                raise ValueError(f"Replacement subcategory {replacement_subcategory_id} not found")
            if replacement_subcategory.category_id != replacement_category_id:
                raise ValueError(
                    f"Replacement subcategory {replacement_subcategory_id} does not belong to "
                    f"replacement category {replacement_category_id}"
                )
        
        # Reassign all transactions to the replacement
        db.query(Transaction).filter(Transaction.subcategory_id == subcategory_id).update({
            "category_id": replacement_category_id,
            "subcategory_id": replacement_subcategory_id
        })

    db.delete(db_subcategory)
    db.commit()
    return True
