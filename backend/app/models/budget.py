"""Budget model for tracking monthly budgets by category."""
from datetime import datetime
from decimal import Decimal

from sqlalchemy import DECIMAL, DateTime, Integer, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Budget(Base):
    """
    Monthly budget per category.
    
    Attributes:
        id: Primary key
        category_id: Category this budget applies to
        year: Budget year
        month: Budget month (1-12)
        amount: Budgeted amount
        created_at: Timestamp of creation
        updated_at: Timestamp of last update
    """
    
    __tablename__ = "budgets"
    __table_args__ = (
        UniqueConstraint('category_id', 'year', 'month', name='uq_budget_category_month'),
    )
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    category_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("categories.id"),
        nullable=False,
        index=True
    )
    year: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    month: Mapped[int] = mapped_column(Integer, nullable=False, index=True)
    amount: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=False
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False
    )
    
    # Relationships
    category: Mapped["Category"] = relationship("Category", back_populates="budgets")
    
    def __repr__(self) -> str:
        return f"<Budget(id={self.id}, category={self.category_id}, {self.year}-{self.month:02d}, ¥{self.amount})>"
