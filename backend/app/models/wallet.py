"""Wallet model."""
from datetime import datetime
from decimal import Decimal
from enum import Enum as PyEnum

from sqlalchemy import DECIMAL, DateTime, Enum, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class WalletType(PyEnum):
    """Wallet type enumeration."""
    NORMAL = "normal"  # Cash, bank account, e-wallet
    CREDIT = "credit"  # Credit card with credit limit


class Wallet(Base):
    """
    Wallet model representing a source of funds.
    
    Supports two types:
    - NORMAL: Regular wallet (cash, bank account, e-wallet). Balance = initial_balance + income - expenses
    - CREDIT: Credit card wallet. Has credit_limit. Available credit = credit_limit - current_balance
    
    Attributes:
        id: Primary key
        name: Unique wallet name (e.g., "Cash", "Bank Account", "Visa Card")
        wallet_type: NORMAL or CREDIT
        initial_balance: Starting balance for normal wallets (default 0)
        credit_limit: Credit limit for credit wallets (default 0)
        created_at: Timestamp of creation
        updated_at: Timestamp of last update
    """
    
    __tablename__ = "wallets"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    wallet_type: Mapped[WalletType] = mapped_column(
        Enum(WalletType),
        nullable=False,
        default=WalletType.NORMAL,
        index=True
    )
    credit_limit: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=False,
        default=Decimal("0.00")
    )
    emoji: Mapped[str | None] = mapped_column(String(10), nullable=True, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        onupdate=datetime.utcnow, 
        nullable=False
    )
    
    # Relationships
    transactions: Mapped[list["Transaction"]] = relationship(
        "Transaction", 
        back_populates="wallet",
        cascade="all, delete-orphan"
    )
    snapshots: Mapped[list["WalletSnapshot"]] = relationship(
        "WalletSnapshot",
        back_populates="wallet",
        cascade="all, delete-orphan"
    )
    
    def __repr__(self) -> str:
        return f"<Wallet(id={self.id}, name='{self.name}', type={self.wallet_type.value})>"
