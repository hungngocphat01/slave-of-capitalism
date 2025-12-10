"""Routers package - explicitly export all routers for PyInstaller."""
from . import (
    wallets,
    categories,
    transactions,
    linked_entries,
    budgets,
)

__all__ = [
    "wallets",
    "categories",
    "transactions",
    "linked_entries",
    "budgets",
]
