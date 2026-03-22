"""Tests for GET /linked-entries/transaction/{transaction_id} endpoint."""


def test_get_linked_entry_by_transaction_not_found(client):
    """Returns 404 when transaction has no linked entry."""
    resp = client.get("/api/linked-entries/transaction/99999")
    assert resp.status_code == 404


def test_get_linked_entry_by_transaction(client, sample_wallet, sample_category):
    """Returns linked entry for a transaction that has one."""
    # Create a transaction
    tx_resp = client.post("/api/transactions/", json={
        "date": "2026-03-15",
        "wallet_id": sample_wallet.id,
        "direction": "outflow",
        "amount": 200.00,
        "classification": "expense",
        "category_id": sample_category.id,
    })
    tx_id = tx_resp.json()["id"]

    # Mark it as split
    split_resp = client.post(f"/api/transactions/{tx_id}/mark-split", json={
        "counterparty_name": "Alice",
        "user_amount": 100.00,
    })
    assert split_resp.status_code == 200

    # Look up by transaction ID
    resp = client.get(f"/api/linked-entries/transaction/{tx_id}")
    assert resp.status_code == 200
    data = resp.json()
    assert data["primary_transaction_id"] == tx_id
    assert data["counterparty_name"] == "Alice"
