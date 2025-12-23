from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict

from pydantic import BaseModel, ConfigDict


class BalanceAuditBase(BaseModel):
    date: date
    balances: Dict[str, float | None]  # Allow None for robustness
    debts: Decimal
    owed: Decimal
    net_position: Decimal


class BalanceAuditCreate(BaseModel):
    date: date
    # Fields are optional to support server-side calculation
    balances: Dict[str, float | None] | None = None
    debts: Decimal | None = None
    owed: Decimal | None = None
    net_position: Decimal | None = None


class BalanceAuditResponse(BalanceAuditBase):
    id: int
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
