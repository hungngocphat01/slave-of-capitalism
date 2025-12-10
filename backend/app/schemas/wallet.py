"""Wallet schemas for API validation."""
from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field

from app.models.wallet import WalletType


class WalletBase(BaseModel):
    """Base wallet schema with common fields."""
    name: str = Field(..., min_length=1, max_length=100, description="Wallet name")
    wallet_type: WalletType = Field(default=WalletType.NORMAL, description="Wallet type")
    credit_limit: Decimal = Field(default=Decimal("0.00"), ge=0, description="Credit limit (for credit wallets)")
    emoji: Optional[str] = Field(default=None, max_length=10, description="Wallet emoji icon")


class WalletCreate(WalletBase):
    """Schema for creating a new wallet."""
    initial_balance: Decimal = Field(default=Decimal("0.00"), ge=0, description="Initial balance (will create a transaction)")


class WalletUpdate(BaseModel):
    """Schema for updating a wallet."""
    name: Optional[str] = Field(default=None, min_length=1, max_length=100)
    wallet_type: Optional[WalletType] = None
    credit_limit: Optional[Decimal] = Field(default=None, ge=0)
    emoji: Optional[str] = Field(default=None, max_length=10)


class WalletResponse(WalletBase):
    """Schema for wallet response with all fields."""
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    created_at: datetime
    updated_at: datetime


class WalletWithBalance(WalletResponse):
    """Schema for wallet with calculated current balance."""
    current_balance: Decimal = Field(..., description="Calculated current balance")
    available_credit: Optional[Decimal] = Field(default=None, description="Available credit (for credit wallets)")


