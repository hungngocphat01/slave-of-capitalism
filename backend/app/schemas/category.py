"""Category and Subcategory schemas for API validation."""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


# Subcategory schemas

class SubcategoryBase(BaseModel):
    """Base subcategory schema."""
    name: str = Field(..., min_length=1, max_length=100, description="Subcategory name")


class SubcategoryCreate(SubcategoryBase):
    """Schema for creating a subcategory."""
    pass


class SubcategoryUpdate(BaseModel):
    """Schema for updating a subcategory."""
    name: str | None = Field(None, min_length=1, max_length=100)


class SubcategoryResponse(SubcategoryBase):
    """Schema for subcategory response."""
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    category_id: int
    is_system: bool
    created_at: datetime
    updated_at: datetime


# Category schemas

class CategoryBase(BaseModel):
    """Base category schema."""
    name: str = Field(..., min_length=1, max_length=100, description="Category name")
    emoji: Optional[str] = Field(default=None, max_length=10, description="Emoji for visual distinction")
    color: Optional[str] = Field(default=None, pattern=r"^#[0-9A-Fa-f]{6}$", description="Hex color code")


class CategoryCreate(CategoryBase):
    """Schema for creating a category."""
    pass


class CategoryUpdate(BaseModel):
    """Schema for updating a category."""
    name: Optional[str] = Field(default=None, min_length=1, max_length=100)
    emoji: Optional[str] = Field(default=None, max_length=10)
    color: Optional[str] = Field(default=None, pattern=r"^#[0-9A-Fa-f]{6}$")


class CategoryResponse(CategoryBase):
    """Schema for category response."""
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    is_system: bool
    created_at: datetime
    updated_at: datetime


class CategoryWithSubcategories(CategoryResponse):
    """Schema for category with nested subcategories."""
    subcategories: list[SubcategoryResponse] = Field(default_factory=list)
