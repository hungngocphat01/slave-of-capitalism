
"""Linked entry schemas for API validation."""
from datetime import date as date_type, datetime as datetime_type
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.linked_entry import LinkType, LinkStatus


# LinkedEntry schemas

class LinkedEntryBase(BaseModel):
    """Base linked entry schema."""
    link_type: LinkType = Field(..., description="Type of link")
    counterparty_name: str = Field(..., min_length=1, max_length=200, description="Counterparty name")
    total_amount: Decimal = Field(..., gt=0, description="Total amount")
    user_amount: Optional[Decimal] = Field(default=None, gt=0, description="User's share (for split payments)")
    notes: Optional[str] = Field(default=None, max_length=1000, description="Optional notes")


class LinkedEntryCreate(BaseModel):
    """Schema for creating a linked entry."""
    primary_transaction_id: int = Field(..., gt=0, description="Primary transaction ID")
    link_type: LinkType = Field(..., description="Type of link")
    counterparty_name: str = Field(..., min_length=1, max_length=200, description="Counterparty name")
    user_amount: Optional[Decimal] = Field(default=None, gt=0, description="User's share (for split payments only)")
    notes: Optional[str] = Field(default=None, max_length=1000, description="Optional notes")


class LinkedEntryUpdate(BaseModel):
    """Schema for updating a linked entry."""
    counterparty_name: Optional[str] = Field(default=None, min_length=1, max_length=200)
    user_amount: Optional[Decimal] = Field(default=None, gt=0)
    notes: Optional[str] = Field(default=None, max_length=1000)


class MarkAsSplitRequest(BaseModel):
    """Schema to mark a transaction as split payment."""
    counterparty_name: str = Field(..., min_length=1, max_length=200)
    user_amount: Decimal = Field(..., gt=0, description="Your share of the cost")
    notes: Optional[str] = Field(default=None, max_length=1000)


class MarkAsLoanRequest(BaseModel):
    """Schema to mark a transaction as a loan."""
    counterparty_name: str = Field(..., min_length=1, max_length=200)
    notes: Optional[str] = Field(default=None, max_length=1000)


class MarkAsDebtRequest(BaseModel):
    """Schema to mark a transaction as a debt."""
    counterparty_name: str = Field(..., min_length=1, max_length=200)
    notes: Optional[str] = Field(default=None, max_length=1000)



# LinkedTransaction schemas

class LinkTransactionRequest(BaseModel):
    """Request to link a transaction to an entry."""
    transaction_id: int = Field(..., gt=0, description="Transaction ID to link")


class LinkedTransactionResponse(BaseModel):
    """Schema for linked transaction response."""
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    linked_entry_id: int
    transaction_id: int
    amount: Decimal
    created_at: datetime_type
    date: Optional[date_type] = None
    description: Optional[str] = None



class LinkedEntryResponse(BaseModel):
    """Schema for linked entry response."""
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    link_type: LinkType
    primary_transaction_id: int
    counterparty_name: str
    total_amount: Decimal
    user_amount: Optional[Decimal]
    pending_amount: Decimal
    status: LinkStatus
    notes: Optional[str]
    created_at: datetime_type
    updated_at: datetime_type
    linked_transactions: list[LinkedTransactionResponse] = []


class LinkedEntryWithDetails(LinkedEntryResponse):
    """Schema for linked entry with transaction details."""
    primary_transaction_description: Optional[str] = None
    primary_transaction_date: Optional[str] = None
    linked_transactions: list[LinkedTransactionResponse] = []
    settled_amount: Decimal = Field(default=Decimal("0.00"), description="Total amount settled")
