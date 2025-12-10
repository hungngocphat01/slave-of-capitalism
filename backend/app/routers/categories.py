"""Category API router."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.category import (
    CategoryCreate,
    CategoryResponse,
    CategoryUpdate,
    CategoryWithSubcategories,
    SubcategoryCreate,
    SubcategoryResponse,
    SubcategoryUpdate,
)
from app.services import category_service

router = APIRouter()


# Category endpoints

@router.get("/", response_model=list[CategoryWithSubcategories])
def list_categories(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    """List all categories with subcategories."""
    categories = category_service.get_categories(db, skip=skip, limit=limit)
    return [CategoryWithSubcategories.model_validate(cat) for cat in categories]


@router.get("/{category_id}", response_model=CategoryWithSubcategories)
def get_category(category_id: int, db: Session = Depends(get_db)):
    """Get a specific category by ID."""
    category = category_service.get_category(db, category_id)
    if not category:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Category {category_id} not found"
        )
    return CategoryWithSubcategories.model_validate(category)


@router.post("/", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
def create_category(category: CategoryCreate, db: Session = Depends(get_db)):
    """Create a new category."""
    try:
        db_category = category_service.create_category(db, category)
        return CategoryResponse.model_validate(db_category)
    except Exception as e:
        if "UNIQUE constraint failed" in str(e):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Category with name '{category.name}' already exists"
            )
        raise


@router.put("/{category_id}", response_model=CategoryResponse)
def update_category(
    category_id: int, category: CategoryUpdate, db: Session = Depends(get_db)
):
    """Update an existing category."""
    db_category = category_service.update_category(db, category_id, category)
    if not db_category:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Category {category_id} not found"
        )
    return CategoryResponse.model_validate(db_category)


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_category(
    category_id: int,
    replacement_category_id: int | None = None,
    replacement_subcategory_id: int | None = None,
    db: Session = Depends(get_db)
):
    """
    Delete a category.
    
    If the category has transactions, replacement_category_id must be provided.
    Optionally, replacement_subcategory_id can be provided to assign transactions to a specific subcategory.
    """
    try:
        deleted = category_service.delete_category(
            db, category_id, replacement_category_id, replacement_subcategory_id
        )
        if not deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Category {category_id} not found"
            )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    return None


# Subcategory endpoints

@router.post("/{category_id}/subcategories", response_model=SubcategoryResponse, status_code=status.HTTP_201_CREATED)
def create_subcategory(
    category_id: int, subcategory: SubcategoryCreate, db: Session = Depends(get_db)
):
    """Create a new subcategory under a category."""
    try:
        db_subcategory = category_service.create_subcategory(db, category_id, subcategory)
        if not db_subcategory:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Category {category_id} not found"
            )
        return SubcategoryResponse.model_validate(db_subcategory)
    except Exception as e:
        if "UNIQUE constraint failed" in str(e):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Subcategory '{subcategory.name}' already exists in this category"
            )
        raise


@router.put("/subcategories/{subcategory_id}", response_model=SubcategoryResponse)
def update_subcategory(
    subcategory_id: int, subcategory: SubcategoryUpdate, db: Session = Depends(get_db)
):
    """Update an existing subcategory."""
    db_subcategory = category_service.update_subcategory(db, subcategory_id, subcategory)
    if not db_subcategory:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Subcategory {subcategory_id} not found"
        )
    return SubcategoryResponse.model_validate(db_subcategory)


@router.delete("/subcategories/{subcategory_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_subcategory(
    subcategory_id: int,
    replacement_category_id: int | None = None,
    replacement_subcategory_id: int | None = None,
    db: Session = Depends(get_db)
):
    """
    Delete a subcategory.
    
    If the subcategory has transactions, replacement_category_id must be provided.
    Optionally, replacement_subcategory_id can be provided to assign transactions to a specific subcategory.
    """
    try:
        deleted = category_service.delete_subcategory(
            db, subcategory_id, replacement_category_id, replacement_subcategory_id
        )
        if not deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Subcategory {subcategory_id} not found"
            )
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    return None

