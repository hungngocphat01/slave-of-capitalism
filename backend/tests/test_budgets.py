
import pytest
from decimal import Decimal
from datetime import date
from app.models.category import Category
from app.models.transaction import Transaction, TransactionDirection, TransactionClassification
from app.models.budget import Budget
from app.models.subcategory import Subcategory

class TestBudgetRouter:
    """Tests for budget router endpoints."""

    def test_daily_summary_calculation(self, client, test_db, sample_wallet):
        """Should calculate correct daily summary with budget and subcategories."""
        
        # 1. Setup Categories and Subcategories
        food = Category(name="Food", emoji="🍔", color="#FF3B30")
        test_db.add(food)
        test_db.commit()
        test_db.refresh(food)
        
        groceries = Subcategory(name="Groceries", category_id=food.id)
        eating_out = Subcategory(name="Eating Out", category_id=food.id)
        test_db.add_all([groceries, eating_out])
        test_db.commit()
        test_db.refresh(groceries)
        test_db.refresh(eating_out)

        # 2. Set Budget
        budget = Budget(
            category_id=food.id,
            year=2025,
            month=12,
            amount=Decimal("50000.00")
        )
        test_db.add(budget)
        test_db.commit()

        # 3. Add Transactions
        # Day 1: Groceries 5000
        t1 = Transaction(
            wallet_id=sample_wallet.id,
            category_id=food.id,
            subcategory_id=groceries.id,
            amount=Decimal("5000.00"),
            direction=TransactionDirection.OUTFLOW,
            classification=TransactionClassification.EXPENSE,
            date=date(2025, 12, 1),
            description="Supermarket"
        )
        # Day 5: Eating Out 3000
        t2 = Transaction(
            wallet_id=sample_wallet.id,
            category_id=food.id,
            subcategory_id=eating_out.id,
            amount=Decimal("3000.00"),
            direction=TransactionDirection.OUTFLOW,
            classification=TransactionClassification.EXPENSE,
            date=date(2025, 12, 5),
            description="Restaurant"
        )
        # Day 5: Groceries 2000
        t3 = Transaction(
            wallet_id=sample_wallet.id,
            category_id=food.id,
            subcategory_id=groceries.id,
            amount=Decimal("2000.00"),
            direction=TransactionDirection.OUTFLOW,
            classification=TransactionClassification.EXPENSE,
            date=date(2025, 12, 5),
            description="Corner store"
        )
        
        test_db.add_all([t1, t2, t3])
        test_db.commit()

        # 4. Call Daily Summary API
        response = client.get("/api/budgets/daily-summary/2025/12")
        assert response.status_code == 200
        data = response.json()

        # 5. Verify Response Structure
        assert data["year"] == 2025
        assert data["month"] == 12
        assert data["days_in_month"] == 31
        assert len(data["categories"]) >= 1

        # Find Food category
        food_data = next(c for c in data["categories"] if c["category_id"] == food.id)
        
        # Verify Basic Info
        assert food_data["category_name"] == "Food"
        assert food_data["budget"] == 50000.0
        assert food_data["color"] == "#FF3B30"
        
        # Verify Daily Amounts
        # Day 1 (index 0): 5000
        # Day 5 (index 4): 3000 + 2000 = 5000
        assert food_data["daily_amounts"][0] == 5000.0
        assert food_data["daily_amounts"][4] == 5000.0
        assert sum(food_data["daily_amounts"]) == 10000.0

        # Verify Subcategories
        assert len(food_data["subcategories"]) == 2
        
        # Check Groceries
        g_data = next(s for s in food_data["subcategories"] if s["subcategory_id"] == groceries.id)
        assert g_data["subcategory_name"] == "Groceries"
        assert g_data["daily_amounts"][0] == 5000.0
        assert g_data["daily_amounts"][4] == 2000.0
        assert sum(g_data["daily_amounts"]) == 7000.0

        # Check Eating Out
        e_data = next(s for s in food_data["subcategories"] if s["subcategory_id"] == eating_out.id)
        assert e_data["subcategory_name"] == "Eating Out"
        assert e_data["daily_amounts"][4] == 3000.0
        assert sum(e_data["daily_amounts"]) == 3000.0

