"""Balance Audit model."""
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Dict

from sqlalchemy import DECIMAL, Date, DateTime, Integer, JSON
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class BalanceAudit(Base):
    """
    Balance Audit model representing a snapshot of balances for all wallets.
    
    Attributes:
        id: Primary key
        date: Date of the audit (unique)
        balances: JSON of wallet balances {wallet_id: balance}
        debts: Total debts
        owed: Total owed
        created_at: Timestamp of creation
        updated_at: Timestamp of last update
    """
    
    __tablename__ = "balance_audits"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    date: Mapped[date] = mapped_column(Date, unique=True, nullable=False, index=True)
    
    # Store as plain JSON. 
    # Example: {"1": 100.50, "2": 200.00}
    # Using JSON type usually maps to JSON in specialized DBs or TEXT in SQLite.
    balances: Mapped[Dict[str, Any]] = mapped_column(JSON, nullable=False)
    
    debts: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=False
    )
    owed: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=False
    )
    net_position: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=20, scale=2),
        nullable=False,
        default=Decimal("0.00")
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        onupdate=datetime.utcnow, 
        nullable=False
    )
    
    def __repr__(self) -> str:
        return f"<BalanceAudit(date={self.date}, debts={self.debts}, owed={self.owed})>"
