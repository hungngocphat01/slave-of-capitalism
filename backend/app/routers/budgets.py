"""Budget API router."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.schemas.budget import (
    BudgetCreate,
    BudgetUpdate,
    BudgetResponse,
    BudgetWithCategory,
    MonthlySummaryResponse,
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
    "/summary/{year}/{month}",
    response_model=MonthlySummaryResponse,
    summary="Get monthly budget summary",
    description="""
    Calculates budget vs actual spending for all categories in a given month.
    
    **What it returns:**
    - Total budget vs total actual spending
    - Per-category breakdown (budget, actual, remaining, percentage used)
    - Period-by-period spending pace (to track if you're on track)
    
    **Period Boundaries:**
    Divides the month into periods to track spending pace. Default: "7,14,21,31"
    - Period 1: Days 1-7
    - Period 2: Days 8-14
    - Period 3: Days 15-21
    - Period 4: Days 22-31
    
    **Example:** If your food budget is ¥30,000/month and you spent ¥10,000 by day 7:
    - Expected: ¥7,500 (25% of month)
    - Actual: ¥10,000 (33% of month)
    - Status: Over pace by ¥2,500
    
    **Note:** Only counts EXPENSE transactions. Excludes TRANSFER, LEND, BORROW, DEBT_COLLECTION, LOAN_REPAYMENT.
    """,
    responses={
        200: {"description": "Monthly summary calculated successfully"},
        400: {"description": "Invalid period_boundaries format"}
    }
)
def get_monthly_summary(
    year: int,
    month: int,
    period_boundaries: str = Query("7,14,21,31", description="Comma-separated period boundaries"),
    db: Session = Depends(get_db),
):
    """
    Get monthly summary with budget vs actual for all categories.
    
    Args:
        year: Year (e.g., 2025)
        month: Month (1-12)
        period_boundaries: Comma-separated day numbers defining period boundaries
    
    Returns:
        MonthlySummaryResponse: Complete budget vs actual breakdown
    
    Example:
        GET /budgets/summary/2025/12?period_boundaries=7,14,21,31
    """
    # Parse period boundaries
    try:
        boundaries = [int(x.strip()) for x in period_boundaries.split(",")]
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid period_boundaries format. Use comma-separated integers."
        )
    
    summary = budget_service.calculate_monthly_summary(db, year, month, boundaries)
    return MonthlySummaryResponse(**summary)

