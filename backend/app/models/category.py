"""Category model."""
from datetime import datetime

from sqlalchemy import Boolean, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Category(Base):
    """
    Category model for expense categorization.
    
    Categories can contain subcategories. If a category has subcategories,
    transactions should be assigned to subcategories. Otherwise, transactions
    are assigned directly to the category.
    
    Attributes:
        id: Primary key
        name: Unique category name
        emoji: Emoji for visual distinction (e.g., "🍔" for Food)
        color: Optional hex color for UI display
        is_system: True for pre-initialized categories that can't be deleted
        created_at: Timestamp of creation
        updated_at: Timestamp of last update
    """
    
    __tablename__ = "categories"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(100), unique=True, nullable=False, index=True)
    emoji: Mapped[str | None] = mapped_column(String(10), nullable=True)  # Emoji character
    color: Mapped[str | None] = mapped_column(String(7), nullable=True)  # Hex color like "#FF5733"
    is_system: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        onupdate=datetime.utcnow, 
        nullable=False
    )
    
    # Relationships
    subcategories: Mapped[list["Subcategory"]] = relationship(
        "Subcategory",
        back_populates="category",
        cascade="all, delete-orphan"
    )
    transactions: Mapped[list["Transaction"]] = relationship(
        "Transaction",
        back_populates="category"
    )
    budgets: Mapped[list["Budget"]] = relationship(
        "Budget",
        back_populates="category",
        cascade="all, delete-orphan"
    )
    
    def __repr__(self) -> str:
        return f"<Category(id={self.id}, name='{self.name}', emoji='{self.emoji}', system={self.is_system})>"
