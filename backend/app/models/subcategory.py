"""Subcategory model."""
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Subcategory(Base):
    """
    Subcategory model for fine-grained expense categorization.
    
    Subcategories belong to a parent category. The combination of
    category_id and name must be unique (e.g., "Food > Dining out").
    
    Attributes:
        id: Primary key
        category_id: Foreign key to parent category
        name: Subcategory name (unique within category)
        is_system: True for pre-initialized subcategories
        created_at: Timestamp of creation
        updated_at: Timestamp of last update
    """
    
    __tablename__ = "subcategories"
    __table_args__ = (
        UniqueConstraint("category_id", "name", name="uq_category_subcategory"),
    )
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    category_id: Mapped[int] = mapped_column(
        Integer, 
        ForeignKey("categories.id", ondelete="CASCADE"), 
        nullable=False,
        index=True
    )
    name: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    is_system: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, 
        default=datetime.utcnow, 
        onupdate=datetime.utcnow, 
        nullable=False
    )
    
    # Relationships
    category: Mapped["Category"] = relationship("Category", back_populates="subcategories")
    transactions: Mapped[list["Transaction"]] = relationship(
        "Transaction",
        back_populates="subcategory"
    )
    
    def __repr__(self) -> str:
        return f"<Subcategory(id={self.id}, category_id={self.category_id}, name='{self.name}')>"
