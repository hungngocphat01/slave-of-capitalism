"""Linked entry models for splits, loans, and debts."""
from datetime import datetime
from decimal import Decimal
from enum import Enum as PyEnum

from sqlalchemy import DECIMAL, DateTime, Enum, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class LinkType(PyEnum):
    """Type of link between transactions."""
    SPLIT_PAYMENT = "split_payment"  # Pay on behalf, expect reimbursement
    LOAN = "loan"                    # Lent money, expect payback
    DEBT = "debt"                    # Borrowed money, must repay
    INSTALLMENT = "installment"      # Credit card installment plan


class LinkStatus(PyEnum):
    """Status of linked entry."""
    PENDING = "pending"    # Waiting for linked transaction(s)
    PARTIAL = "partial"    # Partially settled
    SETTLED = "settled"    # Fully settled


class LinkedEntry(Base):
    """
    Unified model for all linked transactions.
    
    Supports:
    - Split payments: User pays for others, expects reimbursement
    - Loans: User lends money, expects payback (can be partial)
    - Debts: User borrows money, must repay (can be partial)
    
    Attributes:
        id: Primary key
        link_type: SPLIT_PAYMENT, LOAN, or DEBT
        primary_transaction_id: The initial transaction (unique)
        counterparty_name: Who owes/is owed
        total_amount: Total amount involved
        user_amount: User's share (for SPLIT_PAYMENT only)
        pending_amount: Amount still pending
        status: PENDING, PARTIAL, or SETTLED
        notes: Optional notes
        created_at: Timestamp of creation
        updated_at: Timestamp of last update
    """
    
    __tablename__ = "linked_entries"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    link_type: Mapped[LinkType] = mapped_column(
        Enum(LinkType),
        nullable=False,
        index=True
    )
    
    # Primary transaction (the first one)
    primary_transaction_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("transactions.id"),
        nullable=False,
        unique=True,  # One entry per primary transaction
        index=True
    )
    
    # Counterparty
    counterparty_name: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    
    # Amounts
    total_amount: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=False
    )
    user_amount: Mapped[Decimal | None] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=True  # Only for SPLIT_PAYMENT
    )
    pending_amount: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=False
    )
    
    # Status
    status: Mapped[LinkStatus] = mapped_column(
        Enum(LinkStatus),
        nullable=False,
        default=LinkStatus.PENDING,
        index=True
    )
    
    # Notes
    notes: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    
    # Audit
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False
    )
    
    # Relationships
    primary_transaction: Mapped["Transaction"] = relationship(
        "Transaction",
        back_populates="linked_entry_primary",
        foreign_keys=[primary_transaction_id]
    )
    linked_transactions: Mapped[list["LinkedTransaction"]] = relationship(
        "LinkedTransaction",
        back_populates="linked_entry",
        cascade="all, delete-orphan"
    )
    
    def __repr__(self) -> str:
        return f"<LinkedEntry(id={self.id}, {self.link_type.value}, {self.counterparty_name}, pending=¥{self.pending_amount})>"


class LinkedTransaction(Base):
    """
    Links a transaction to a LinkedEntry.
    Supports partial repayments/reimbursements.
    
    The amount settled is derived from the linked transaction's amount,
    eliminating redundancy since transaction_id has a unique constraint.
    
    Attributes:
        id: Primary key
        linked_entry_id: Which LinkedEntry this belongs to
        transaction_id: The linked transaction (payback, reimbursement, etc.)
        created_at: Timestamp of creation
    """
    
    __tablename__ = "linked_transactions"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    linked_entry_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("linked_entries.id"),
        nullable=False,
        index=True
    )
    transaction_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("transactions.id"),
        nullable=False,
        unique=True,  # One transaction can only be linked once
        index=True
    )
    
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, nullable=False)
    
    # Relationships
    linked_entry: Mapped[LinkedEntry] = relationship(
        "LinkedEntry",
        back_populates="linked_transactions"
    )
    transaction: Mapped["Transaction"] = relationship(
        "Transaction",
        back_populates="linked_transactions"
    )
    
    @property
    def amount(self) -> Decimal:
        """Get the amount from the linked transaction."""
        return self.transaction.amount
    
    def __repr__(self) -> str:
        return f"<LinkedTransaction(id={self.id}, entry={self.linked_entry_id}, txn={self.transaction_id})>"
