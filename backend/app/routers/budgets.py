"""Budget API router."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.budget import (
    BudgetCreate,
    BudgetUpdate,
    BudgetResponse,
    BudgetWithCategory,
    BudgetWithCategory,
    MonthlySummaryResponse,
    DailySummaryResponse,
)
from app.services import budget_service

router = APIRouter()


@router.get("/", response_model=list[BudgetWithCategory])
def list_budgets(
    year: int | None = Query(None, description="Filter by year"),
    month: int | None = Query(None, ge=1, le=12, description="Filter by month (1-12)"),
    category_id: int | None = Query(None, description="Filter by category ID"),
    db: Session = Depends(get_db),
):
    """List budgets with optional filtering."""
    budgets = budget_service.get_budgets(db, year=year, month=month, category_id=category_id)
    
    # Enrich with category details
    enriched = []
    for budget in budgets:
        budget_dict = BudgetResponse.model_validate(budget).model_dump()
        budget_dict["category_name"] = budget.category.name if budget.category else None
        budget_dict["category_emoji"] = budget.category.emoji if budget.category else None
        enriched.append(BudgetWithCategory(**budget_dict))
    
    return enriched


@router.get("/{budget_id}", response_model=BudgetWithCategory)
def get_budget(budget_id: int, db: Session = Depends(get_db)):
    """Get a specific budget by ID."""
    budget = budget_service.get_budget(db, budget_id)
    if not budget:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Budget {budget_id} not found"
        )
    
    budget_dict = BudgetResponse.model_validate(budget).model_dump()
    budget_dict["category_name"] = budget.category.name if budget.category else None
    budget_dict["category_emoji"] = budget.category.emoji if budget.category else None
    
    return BudgetWithCategory(**budget_dict)


@router.post("/", response_model=BudgetResponse, status_code=status.HTTP_201_CREATED)
def create_budget(budget: BudgetCreate, db: Session = Depends(get_db)):
    """Create a new budget."""
    try:
        db_budget = budget_service.create_budget(db, budget)
        return BudgetResponse.model_validate(db_budget)
    except budget_service.BudgetError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )


@router.put("/{budget_id}", response_model=BudgetResponse)
def update_budget(
    budget_id: int, budget: BudgetUpdate, db: Session = Depends(get_db)
):
    """Update an existing budget."""
    db_budget = budget_service.update_budget(db, budget_id, budget)
    if not db_budget:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Budget {budget_id} not found"
        )
    return BudgetResponse.model_validate(db_budget)


@router.delete("/{budget_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_budget(budget_id: int, db: Session = Depends(get_db)):
    """Delete a budget."""
    deleted = budget_service.delete_budget(db, budget_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Budget {budget_id} not found"
        )
    return None


@router.get(
    "/daily-summary/{year}/{month}",
    response_model=DailySummaryResponse,
    summary="Get daily summary for chart",
)
def get_daily_summary(
    year: int,
    month: int,
    db: Session = Depends(get_db),
):
    """
    Get daily expense data for all categories.
    Used for plotting area charts.
    """
    summary = budget_service.calculate_daily_summary(db, year, month)
    return DailySummaryResponse(**summary)

