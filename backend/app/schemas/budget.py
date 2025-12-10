"""Budget schemas for API validation."""
from datetime import datetime as datetime_type
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class BudgetBase(BaseModel):
    """Base budget schema."""
    category_id: int = Field(..., gt=0, description="Category ID")
    year: int = Field(..., ge=2000, le=2100, description="Budget year")
    month: int = Field(..., ge=1, le=12, description="Budget month (1-12)")
    amount: Decimal = Field(..., ge=0, description="Budgeted amount")


class BudgetCreate(BudgetBase):
    """Schema for creating a budget."""
    pass


class BudgetUpdate(BaseModel):
    """Schema for updating a budget (all fields optional for partial updates)."""
    amount: Optional[Decimal] = Field(default=None, ge=0)


class BudgetResponse(BudgetBase):
    """Schema for budget response."""
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    created_at: datetime_type
    updated_at: datetime_type


class BudgetWithCategory(BudgetResponse):
    """Schema for budget response with category details."""
    category_name: Optional[str] = None
    category_emoji: Optional[str] = None


class SubcategorySummary(BaseModel):
    """Schema for subcategory monthly summary."""
    subcategory_id: int
    subcategory_name: str
    actual: float
    periods: list[float]

class CategorySummary(BaseModel):
    """Schema for category monthly summary."""
    category_id: int
    category_name: str
    emoji: Optional[str]
    budget: float
    actual: float
    percentage: float
    periods: list[float]
    subcategories: list[SubcategorySummary] = []

class MonthlySummaryResponse(BaseModel):
    """Schema for monthly summary with budget vs actual."""
    year: int
    month: int
    categories: list[CategorySummary]
    total_budget: Decimal
    total_actual: Decimal
    period_boundaries: list[int]  # e.g., [7, 14, 21, 31]
