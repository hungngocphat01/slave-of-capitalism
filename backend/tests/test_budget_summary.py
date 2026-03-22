"""Tests for GET /budgets/summary/{year}/{month} endpoint."""
from decimal import Decimal


def test_monthly_summary_empty(client):
    """Returns empty summary when no budgets exist."""
    resp = client.get("/api/budgets/summary/2026/3")
    assert resp.status_code == 200
    data = resp.json()
    assert data["year"] == 2026
    assert data["month"] == 3
    assert data["categories"] == []
    assert float(data["total_budget"]) == 0.0
    assert float(data["total_actual"]) == 0.0


def test_monthly_summary_with_budget_and_transactions(client, sample_wallet, sample_category):
    """Returns budget vs actual with category breakdown."""
    client.post("/api/budgets/", json={
        "category_id": sample_category.id,
        "year": 2026,
        "month": 3,
        "amount": 500.00,
    })
    client.post("/api/transactions/", json={
        "date": "2026-03-15",
        "wallet_id": sample_wallet.id,
        "direction": "outflow",
        "amount": 150.00,
        "classification": "expense",
        "category_id": sample_category.id,
    })
    resp = client.get("/api/budgets/summary/2026/3")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["categories"]) == 1
    cat = data["categories"][0]
    assert cat["category_id"] == sample_category.id
    assert float(cat["budget"]) == 500.0
    assert float(cat["actual"]) == 150.0


def test_monthly_summary_with_period_boundaries(client, sample_wallet, sample_category):
    """Period boundaries split spending into sub-period columns."""
    client.post("/api/budgets/", json={
        "category_id": sample_category.id,
        "year": 2026,
        "month": 3,
        "amount": 1000.00,
    })
    client.post("/api/transactions/", json={
        "date": "2026-03-05",
        "wallet_id": sample_wallet.id,
        "direction": "outflow",
        "amount": 100.00,
        "classification": "expense",
        "category_id": sample_category.id,
    })
    resp = client.get("/api/budgets/summary/2026/3?period_boundaries=7,14,21,31")
    assert resp.status_code == 200
    data = resp.json()
    assert data["period_boundaries"] == [7, 14, 21, 31]
    cat = data["categories"][0]
    assert len(cat["periods"]) == 4
    assert cat["periods"][0] == 100.0  # day 5 falls in period 1 (1-7)
