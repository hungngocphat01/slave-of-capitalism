"""Updated transaction model with direction and classification."""
from datetime import date, datetime, timezone
from datetime import time as time_type
from decimal import Decimal
from enum import Enum as PyEnum

from sqlalchemy import Boolean, DECIMAL, Date, DateTime, Enum, ForeignKey, Integer, String, Time
from sqlalchemy import event as sa_event
from sqlalchemy.orm import Mapped, mapped_column, relationship, Session

from app.database import Base


class TransactionDirection(PyEnum):
    """Physical direction of money movement."""
    INFLOW = "inflow"    # Money enters wallet
    OUTFLOW = "outflow"  # Money leaves wallet
    RESERVED = "reserved"  # For future liabilities (Installment Plans) money movement


class TransactionClassification(PyEnum):
    """Financial classification of transaction."""
    EXPENSE = "expense"                    # Regular spending
    INCOME = "income"                      # Regular income
    LEND = "lend"                         # Lent money to someone
    BORROW = "borrow"                     # Borrowed money from someone
    DEBT_COLLECTION = "debt_collection"    # Receiving money back
    LOAN_REPAYMENT = "loan_repayment"      # Paying back borrowed money
    SPLIT_PAYMENT = "split_payment"        # Paid for others
    TRANSFER = "transfer"                  # Between own wallets
    INSTALLMENT = "installment"            # Installment plan placeholder
    INSTALLMT_CHRGE = "installmt_chrge"    # Actual installment charge


class Transaction(Base):
    """
    Core transaction model - tracks money movement.
    
    Separates physical direction (INFLOW/OUTFLOW) from financial classification
    (EXPENSE/INCOME/LEND/etc) to properly handle loans, transfers, and split payments.
    
    Attributes:
        id: Primary key
        date: Transaction date
        time: Optional transaction time
        wallet_id: Which wallet this affects
        direction: INFLOW (money in) or OUTFLOW (money out)
        amount: Transaction amount (always positive)
        classification: What this transaction means financially
        description: Transaction description
        category_id: Optional category
        subcategory_id: Optional subcategory
        paired_transaction_id: For wallet transfers (links to other half)
        created_at: Timestamp of creation
        updated_at: Timestamp of last update
    """
    
    __tablename__ = "transactions"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    date: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    time: Mapped[time_type | None] = mapped_column(Time, nullable=True)
    wallet_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("wallets.id"),
        nullable=False,
        index=True
    )
    
    # Money movement
    direction: Mapped[TransactionDirection] = mapped_column(
        Enum(TransactionDirection),
        nullable=False,
        index=True
    )
    amount: Mapped[Decimal] = mapped_column(
        DECIMAL(precision=12, scale=2),
        nullable=False
    )
    
    # Classification
    classification: Mapped[TransactionClassification] = mapped_column(
        Enum(TransactionClassification),
        nullable=False,
        index=True
    )
    
    # Description & categorization
    description: Mapped[str | None] = mapped_column(String(500), nullable=True, default="")
    category_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("categories.id"),
        nullable=True,
        index=True
    )
    subcategory_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("subcategories.id"),
        nullable=True,
        index=True
    )
    
    # For wallet transfers (links to paired transaction)
    paired_transaction_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("transactions.id"),
        nullable=True
    )
    
    # Special flags
    is_ignored: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        index=True,
        comment="If True, transaction is excluded from budget calculations"
    )
    is_calibration: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        index=True,
        comment="If True, transaction is a wallet balance calibration"
    )
    
    # Audit
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False
    )
    
    # Relationships
    wallet: Mapped["Wallet"] = relationship("Wallet", back_populates="transactions")
    category: Mapped["Category | None"] = relationship("Category", back_populates="transactions")
    subcategory: Mapped["Subcategory | None"] = relationship("Subcategory", back_populates="transactions")
    
    # Self-referential for paired transfers
    paired_transaction: Mapped["Transaction | None"] = relationship(
        "Transaction",
        remote_side=[id],
        foreign_keys=[paired_transaction_id]
    )
    
    # Linked entries (for splits, loans, debts)
    linked_entry_primary: Mapped["LinkedEntry | None"] = relationship(
        "LinkedEntry",
        back_populates="primary_transaction",
        foreign_keys="LinkedEntry.primary_transaction_id"
    )
    linked_transactions: Mapped[list["LinkedTransaction"]] = relationship(
        "LinkedTransaction",
        back_populates="transaction"
    )
    
    # Valid direction/classification combinations
    VALID_COMBINATIONS: dict[TransactionClassification, set[TransactionDirection]] = {
        TransactionClassification.EXPENSE: {TransactionDirection.OUTFLOW},
        TransactionClassification.INCOME: {TransactionDirection.INFLOW},
        TransactionClassification.LEND: {TransactionDirection.OUTFLOW},
        TransactionClassification.BORROW: {TransactionDirection.INFLOW},
        TransactionClassification.DEBT_COLLECTION: {TransactionDirection.INFLOW},
        TransactionClassification.LOAN_REPAYMENT: {TransactionDirection.OUTFLOW},
        TransactionClassification.SPLIT_PAYMENT: {TransactionDirection.OUTFLOW},
        TransactionClassification.TRANSFER: {TransactionDirection.INFLOW, TransactionDirection.OUTFLOW},
        TransactionClassification.INSTALLMENT: {TransactionDirection.RESERVED},
        TransactionClassification.INSTALLMT_CHRGE: {TransactionDirection.OUTFLOW},
    }

    def validate_direction_classification(self) -> None:
        """Validate that direction/classification combination is valid."""
        if self.direction is not None and self.classification is not None:
            valid_dirs = self.VALID_COMBINATIONS.get(self.classification)
            if valid_dirs and self.direction not in valid_dirs:
                raise ValueError(
                    f"Invalid combination: direction={self.direction.value} "
                    f"with classification={self.classification.value}"
                )

    def __repr__(self) -> str:
        return f"<Transaction(id={self.id}, {self.direction.value} ¥{self.amount}, {self.classification.value})>"


@sa_event.listens_for(Session, "before_flush")
def _validate_transactions_before_flush(session: Session, flush_context, instances):
    """Validate direction/classification on all new and dirty Transaction objects."""
    for obj in list(session.new) + list(session.dirty):
        if isinstance(obj, Transaction):
            obj.validate_direction_classification()
