"""Budget service for managing monthly budgets."""
from datetime import date
from decimal import Decimal
from typing import Optional

from sqlalchemy import and_
from sqlalchemy.orm import Session

from app.models.budget import Budget
from app.models.category import Category
from app.models.transaction import Transaction, TransactionClassification, TransactionDirection
from app.models.linked_entry import LinkedEntry, LinkType
from app.schemas.budget import BudgetCreate, BudgetUpdate


class BudgetError(Exception):
    """Custom exception for budget-related errors."""
    pass


def get_budgets(
    db: Session,
    year: Optional[int] = None,
    month: Optional[int] = None,
    category_id: Optional[int] = None
) -> list[Budget]:
    """Get budgets with optional filtering."""
    query = db.query(Budget)
    
    if year is not None:
        query = query.filter(Budget.year == year)
    if month is not None:
        query = query.filter(Budget.month == month)
    if category_id is not None:
        query = query.filter(Budget.category_id == category_id)
    
    return query.all()


def get_budget(db: Session, budget_id: int) -> Optional[Budget]:
    """Get a specific budget by ID."""
    return db.query(Budget).filter(Budget.id == budget_id).first()


def create_budget(db: Session, budget: BudgetCreate) -> Budget:
    """Create a new budget."""
    # Check if budget already exists for this category/month
    existing = db.query(Budget).filter(
        and_(
            Budget.category_id == budget.category_id,
            Budget.year == budget.year,
            Budget.month == budget.month
        )
    ).first()
    
    if existing:
        raise BudgetError(
            f"Budget already exists for category {budget.category_id} "
            f"in {budget.year}-{budget.month:02d}"
        )
    
    # Verify category exists
    category = db.query(Category).filter(Category.id == budget.category_id).first()
    if not category:
        raise BudgetError(f"Category {budget.category_id} not found")
    
    db_budget = Budget(**budget.model_dump())
    db.add(db_budget)
    db.commit()
    db.refresh(db_budget)
    return db_budget


def update_budget(db: Session, budget_id: int, budget: BudgetUpdate) -> Optional[Budget]:
    """Update an existing budget."""
    db_budget = get_budget(db, budget_id)
    if not db_budget:
        return None
    
    update_data = budget.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(db_budget, field, value)
    
    db.commit()
    db.refresh(db_budget)
    return db_budget


def delete_budget(db: Session, budget_id: int) -> bool:
    """Delete a budget."""
    db_budget = get_budget(db, budget_id)
    if not db_budget:
        return False
    
    db.delete(db_budget)
    db.commit()
    return True


def upsert_budget(db: Session, category_id: int, year: int, month: int, amount: Decimal) -> Budget:
    """Create or update a budget for a category/month."""
    existing = db.query(Budget).filter(
        and_(
            Budget.category_id == category_id,
            Budget.year == year,
            Budget.month == month
        )
    ).first()
    
    if existing:
        existing.amount = amount
        db.commit()
        db.refresh(existing)
        return existing
    else:
        db_budget = Budget(
            category_id=category_id,
            year=year,
            month=month,
            amount=amount
        )
        db.add(db_budget)
        db.commit()
        db.refresh(db_budget)
        return db_budget


def calculate_monthly_summary(
    db: Session,
    year: int,
    month: int,
    period_boundaries: list[int] = [7, 14, 21, 31]
) -> dict:
    """
    Calculate monthly summary with budget vs actual for each category.
    
    Returns a dictionary with:
    - categories: list of category summaries with budget, actual, and period breakdowns
    - total_budget: sum of all budgets
    - total_actual: sum of all actual expenses
    """
    from sqlalchemy.orm import joinedload
    
    # Get all categories with subcategories loaded
    categories = db.query(Category).options(joinedload(Category.subcategories)).all()
    
    # Get all budgets for this month
    budgets = db.query(Budget).filter(
        and_(Budget.year == year, Budget.month == month)
    ).all()
    budget_map = {b.category_id: b.amount for b in budgets}
    
    # Calculate date range for the month
    start_date = date(year, month, 1)
    if month == 12:
        end_date = date(year + 1, 1, 1)
    else:
        end_date = date(year, month + 1, 1)
    
    category_summaries = []
    total_budget = Decimal("0")
    total_actual = Decimal("0")
    
    def get_period_index(d: date) -> int:
        day = d.day
        for i, boundary in enumerate(period_boundaries):
            if day <= boundary:
                return i
        return len(period_boundaries) - 1

    for category in categories:
        budget_amount = budget_map.get(category.id, Decimal("0"))
        
        # Initialize subcategory aggregators
        # Map subcategory_id -> {actual: 0.0, periods: [0.0, ...]}
        sub_map = {
            sub.id: {
                "name": sub.name, 
                "actual": 0.0, 
                "periods": [0.0] * len(period_boundaries)
            } 
            for sub in category.subcategories
        }
        
        # Category aggregators
        cat_actual = 0.0
        cat_periods = [0.0] * len(period_boundaries)
        
        # 1. Fetch regular EXPENSE transactions
        # Exclude ignored transactions
        expense_txns = db.query(Transaction).filter(
            and_(
                Transaction.category_id == category.id,
                Transaction.date >= start_date,
                Transaction.date < end_date,
                Transaction.classification == TransactionClassification.EXPENSE,
                Transaction.is_ignored == False
            )
        ).all()
        
        for txn in expense_txns:
            amount = float(txn.amount)
            p_idx = get_period_index(txn.date)
            
            # Add to category total
            cat_actual += amount
            cat_periods[p_idx] += amount
            
            # Add to subcategory total if applicable
            if txn.subcategory_id and txn.subcategory_id in sub_map:
                sub_map[txn.subcategory_id]["actual"] += amount
                sub_map[txn.subcategory_id]["periods"][p_idx] += amount

        # 2. Fetch SPLIT_PAYMENT user shares
        split_entries = db.query(LinkedEntry).join(
            Transaction, LinkedEntry.primary_transaction_id == Transaction.id
        ).filter(
            and_(
                Transaction.category_id == category.id,
                Transaction.date >= start_date,
                Transaction.date < end_date,
                LinkedEntry.link_type == LinkType.SPLIT_PAYMENT,
                Transaction.is_ignored == False
            )
        ).all()
        
        for entry in split_entries:
            if entry.user_amount:
                amount = float(entry.user_amount)
                # Date comes from the primary transaction
                # Accessing entry.primary_transaction should be safe if joined, 
                # but explicit join above ensures filtering. 
                # Ideally check if relationship is loaded, or use primary_transaction from join context if possible.
                # entry.primary_transaction is lazy loaded if not eager.
                # Using the date from filter query implies we should load it or it's implicitly available.
                # Use entry.primary_transaction.date
                txn_date = entry.primary_transaction.date
                p_idx = get_period_index(txn_date)
                
                cat_actual += amount
                cat_periods[p_idx] += amount
                
                sub_id = entry.primary_transaction.subcategory_id
                if sub_id and sub_id in sub_map:
                    sub_map[sub_id]["actual"] += amount
                    sub_map[sub_id]["periods"][p_idx] += amount

        # Build subcategories list response
        subcategories_list = []
        for sub_id, data in sub_map.items():
            # Only include if there's activity? Or always?
            # User wants to expand to see details. Usually show all or only active.
            # Showing all might be cluttered if many empty ones.
            # But "details of the subcategories" suggests seeing the breakdown.
            # Let's show all for now, or filter by actual > 0?
            # "Excel-like" usually shows strict hierarchy. Let's show all.
            subcategories_list.append({
                "subcategory_id": sub_id,
                "subcategory_name": data["name"],
                "actual": data["actual"],
                "periods": data["periods"]
            })
        
        # Sort subcategories by name
        subcategories_list.sort(key=lambda x: x["subcategory_name"])

        percentage = 0.0
        if budget_amount > 0:
            percentage = (cat_actual / float(budget_amount)) * 100
        
        category_summaries.append({
            "category_id": category.id,
            "category_name": category.name,
            "emoji": category.emoji,
            "budget": float(budget_amount),
            "actual": cat_actual,
            "percentage": percentage,
            "periods": cat_periods,
            "subcategories": subcategories_list
        })
        
        total_budget += budget_amount
        total_actual += Decimal(str(cat_actual)) # Convert back to Decimal for precise total sum safe-ish
    
    return {
        "year": year,
        "month": month,
        "categories": category_summaries,
        "total_budget": total_budget,
        "total_actual": total_actual,
        "period_boundaries": period_boundaries
    }
