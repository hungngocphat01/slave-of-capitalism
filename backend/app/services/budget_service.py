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


def calculate_daily_summary(
    db: Session,
    year: int,
    month: int
) -> dict:
    """
    Calculate daily expenses for each category.
    Returns daily amounts day 1..N.
    """
    from calendar import monthrange
    from app.models.category import Category
    from app.models.transaction import Transaction, TransactionClassification
    from app.models.linked_entry import LinkedEntry, LinkType
    from app.models.budget import Budget
    from sqlalchemy.orm import joinedload
    from sqlalchemy import and_
    
    _, days_in_month = monthrange(year, month)
    
    # Pre-fetch categories with subcategories
    categories = db.query(Category).options(joinedload(Category.subcategories)).all()

    # Pre-fetch budgets for this month
    budgets = db.query(Budget).filter(
        and_(
            Budget.year == year,
            Budget.month == month
        )
    ).all()
    budget_map = {b.category_id: float(b.amount) for b in budgets}
    
    start_date = date(year, month, 1)
    if month == 12:
        end_date = date(year + 1, 1, 1)
    else:
        end_date = date(year, month + 1, 1)
        
    category_data = []
    
    for category in categories:
        # Array for days 1..N (index 0 is day 1)
        daily_amounts = [0.0] * days_in_month
        
        # Subcategory breakdown: {sub_id: [daily_array]}
        sub_daily = {}
        for sub in category.subcategories:
            sub_daily[sub.id] = [0.0] * days_in_month

        # 1. Regular Expenses
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
            day_idx = txn.date.day - 1
            if 0 <= day_idx < days_in_month:
                val = float(txn.amount)
                daily_amounts[day_idx] += val
                if txn.subcategory_id and txn.subcategory_id in sub_daily:
                    sub_daily[txn.subcategory_id][day_idx] += val
                
        # 2. Split Payments
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
                # Use primary transaction date
                txn_date = entry.primary_transaction.date
                day_idx = txn_date.day - 1
                if 0 <= day_idx < days_in_month:
                    daily_amounts[day_idx] += amount
                    # Split entries might track subcategory via primary txn?
                    # The LinkedEntry itself doesn't have subcategory_id usually, 
                    # but the primary transaction does.
                    sub_id = entry.primary_transaction.subcategory_id
                    if sub_id and sub_id in sub_daily:
                        sub_daily[sub_id][day_idx] += amount
        
        budget_val = budget_map.get(category.id, 0.0)
        total_spent = sum(daily_amounts)

        # Include if budget exists OR money spent
        if budget_val > 0 or total_spent > 0:
            # Format subcategories
            subs_formatted = []
            for sub in category.subcategories:
                s_amounts = sub_daily.get(sub.id)
                if s_amounts and sum(s_amounts) > 0:
                    subs_formatted.append({
                        "subcategory_id": sub.id,
                        "subcategory_name": sub.name,
                        "daily_amounts": s_amounts
                    })
            
            # Sort subcategories by spend
            subs_formatted.sort(key=lambda x: sum(x["daily_amounts"]), reverse=True)

            category_data.append({
                "category_id": category.id,
                "category_name": category.name,
                "emoji": category.emoji,
                "color": category.color,
                "budget": budget_val,
                "daily_amounts": daily_amounts,
                "subcategories": subs_formatted
            })
            
    # Sort by total amount descending
    category_data.sort(key=lambda x: sum(x["daily_amounts"]), reverse=True)
    
    return {
        "year": year,
        "month": month,
        "days_in_month": days_in_month,
        "categories": category_data
    }
