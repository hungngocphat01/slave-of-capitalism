"""Wallet snapshot model for optimizing balance calculations."""
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import DECIMAL, Date, DateTime, ForeignKey, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class WalletSnapshot(Base):
    """
    Snapshot of a wallet's balance at the end of a specific date.
    
    Used to optimize balance calculations by providing a checkpoint.
    Current Balance = Snapshot Balance + Sum(Transactions since Snapshot).
    
    Attributes:
        id: Primary key
        wallet_id: The wallet this snapshot belongs to
        balance: The balance at the end of snapshot_date (23:59:59)
        snapshot_date: The date this snapshot represents
        created_at: When the snapshot was created/cached
    """
    
    __tablename__ = "wallet_snapshots"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    wallet_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("wallets.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    balance: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=False
    )
    snapshot_date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    wallet: Mapped["Wallet"] = relationship("Wallet", back_populates="snapshots")
    
    def __repr__(self) -> str:
        return f"<WalletSnapshot(wallet_id={self.wallet_id}, date={self.snapshot_date}, balance={self.balance})>"
