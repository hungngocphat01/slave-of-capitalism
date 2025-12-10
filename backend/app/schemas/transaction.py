"""Transaction schemas for API validation."""
from datetime import date as date_type
from datetime import datetime as datetime_type
from datetime import time as time_type
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.transaction import TransactionDirection, TransactionClassification
from app.schemas.linked_entry import LinkedEntryResponse


class TransactionBase(BaseModel):
    """Base transaction schema."""
    date: date_type = Field(..., description="Transaction date")
    time: Optional[time_type] = Field(default=None, description="Transaction time (optional)")
    wallet_id: int = Field(..., gt=0, description="Wallet ID")
    direction: TransactionDirection = Field(..., description="INFLOW or OUTFLOW")
    amount: Decimal = Field(..., gt=0, description="Transaction amount")
    classification: TransactionClassification = Field(..., description="Financial classification")
    description: Optional[str] = Field(default="", max_length=500, description="Description")
    category_id: Optional[int] = Field(default=None, gt=0, description="Category ID (optional)")
    subcategory_id: Optional[int] = Field(default=None, gt=0, description="Subcategory ID (optional)")
    paired_transaction_id: Optional[int] = Field(default=None, gt=0, description="Paired transaction for transfers")
    is_ignored: bool = Field(default=False, description="Exclude from budget calculations")
    is_calibration: bool = Field(default=False, description="Wallet balance calibration")


class TransactionCreate(TransactionBase):
    """Schema for creating a transaction."""
    allow_large_cache_rebuild: bool = Field(default=False, description="Allow rebuilding large transaction cache safely")


class TransactionUpdate(BaseModel):
    """Schema for updating a transaction (all fields optional for partial updates)."""
    date: Optional[date_type] = None
    time: Optional[time_type] = None
    wallet_id: Optional[int] = Field(default=None, gt=0)
    direction: Optional[TransactionDirection] = None
    amount: Optional[Decimal] = Field(default=None, gt=0)
    classification: Optional[TransactionClassification] = None
    description: Optional[str] = Field(default=None, max_length=500)
    category_id: Optional[int] = Field(default=None, gt=0)
    subcategory_id: Optional[int] = Field(default=None, gt=0)
    paired_transaction_id: Optional[int] = Field(default=None, gt=0)
    is_ignored: Optional[bool] = None
    is_calibration: Optional[bool] = None
    allow_large_cache_rebuild: Optional[bool] = Field(default=False, description="Allow rebuilding large transaction cache safely")


class TransactionResponse(TransactionBase):
    """Schema for transaction response."""
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    created_at: datetime_type
    updated_at: datetime_type


class TransactionWithDetails(TransactionResponse):
    """Schema for transaction response with nested category/wallet details."""
    wallet_name: Optional[str] = None
    category_name: Optional[str] = None
    subcategory_name: Optional[str] = None
    has_linked_entry: bool = Field(default=False, description="Whether this has a linked entry")
    is_linked_to_entry: bool = Field(default=False, description="Whether this is linked to an entry")
    linked_entry: Optional[LinkedEntryResponse] = Field(default=None, description="The linked entry details if any")


class ReclassifyRequest(BaseModel):
    """Request to reclassify a transaction."""
    classification: TransactionClassification = Field(..., description="New classification")


class WalletTransferRequest(BaseModel):
    """Request to create a wallet transfer."""
    from_wallet_id: int = Field(..., gt=0, description="Source wallet ID")
    to_wallet_id: int = Field(..., gt=0, description="Destination wallet ID")
    amount: Decimal = Field(..., gt=0, description="Transfer amount")
    description: str = Field(..., min_length=1, max_length=500, description="Description")
    date: date_type = Field(..., description="Transfer date")
    time: Optional[time_type] = Field(default=None, description="Transfer time")


class WalletTransferResponse(BaseModel):
    """Response for wallet transfer."""
    outflow_transaction: TransactionResponse
    inflow_transaction: TransactionResponse


class BulkActionRequest(BaseModel):
    """Request for bulk actions on transactions."""
    transaction_ids: list[int] = Field(..., min_length=1, description="List of transaction IDs")


class BulkLinkRequest(BaseModel):
    """Request for bulk linking transactions to an entry."""
    transaction_ids: list[int] = Field(..., min_length=1, description="List of transaction IDs")
    linked_entry_id: int = Field(..., gt=0, description="Target linked entry ID")


class TransactionMergeRequest(BaseModel):
    """Request for merging multiple transactions."""
    transaction_ids: list[int] = Field(..., min_length=2, description="List of transaction IDs to merge")
    date: date_type = Field(..., description="Date for the merged transaction")
    description: str = Field(..., max_length=500, description="Description for the merged transaction")
    category_id: Optional[int] = Field(default=None, gt=0, description="Category ID")
    subcategory_id: Optional[int] = Field(default=None, gt=0, description="Subcategory ID")


class BulkImportRequest(BaseModel):
    """Request for bulk importing transactions and transfers."""
    # We use a union here. Pydantic will match based on structure.
    # WalletTransferRequest has 'from_wallet_id', TransactionCreate has 'wallet_id'.
    items: list[TransactionCreate | WalletTransferRequest]
