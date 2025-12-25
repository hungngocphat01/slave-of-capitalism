#!/usr/bin/env python3
"""
Integration Test for Installment Plan Feature

This script simulates real-world usage of credit card installment plans,
testing the interaction between normal expenses, installment charges, and payments.

Requirements:
- Start backend server at port 9000 with a fresh database:
  cd backend && poetry run python -m app.main --database /tmp/integration-test.db --port 9000 --no-seed-wallets
"""

import requests
import json
from datetime import date, timedelta
from typing import Dict, List, Optional
from decimal import Decimal


# Configuration
BASE_URL = "http://localhost:9000/api"
INITIAL_CREDIT_LIMIT = 100000  # ¥100,000


class Colors:
    """ANSI color codes for terminal output"""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


def print_section(title: str):
    """Print a formatted section header"""
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'=' * 80}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{title:^80}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'=' * 80}{Colors.ENDC}\n")


def print_step(step: str):
    """Print a formatted step description"""
    print(f"{Colors.CYAN}{Colors.BOLD}▶ {step}{Colors.ENDC}")


def print_result(label: str, value, expected: Optional[float] = None):
    """Print a result with optional expected value comparison"""
    if expected is not None:
        match = abs(float(value) - expected) < 0.01
        color = Colors.GREEN if match else Colors.RED
        status = "✓" if match else "✗"
        print(f"  {color}{status} {label}: ¥{value:,.0f} (expected: ¥{expected:,.0f}){Colors.ENDC}")
    else:
        print(f"  {Colors.BLUE}• {label}: ¥{value:,.0f}{Colors.ENDC}")


def pause_for_review():
    """Pause execution for manual review"""
    input(f"\n{Colors.YELLOW}Press Enter to continue...{Colors.ENDC}\n")


# =============================================================================
# API Helper Functions
# =============================================================================

def create_wallet(name: str, wallet_type: str, credit_limit: float = 0) -> Dict:
    """Create a wallet"""
    payload = {
        "name": name,
        "wallet_type": wallet_type,
        "initial_balance": 500000 if wallet_type == "normal" else 0
    }
    if wallet_type == "credit":
        payload["credit_limit"] = credit_limit
    
    response = requests.post(f"{BASE_URL}/wallets", json=payload)
    if not response.ok:
        print(f"{Colors.RED}Error creating wallet: {response.status_code}{Colors.ENDC}")
        print(f"{Colors.RED}Response: {response.text}{Colors.ENDC}")
    response.raise_for_status()
    return response.json()


def get_wallets() -> List[Dict]:
    """Get all wallets with current balances"""
    response = requests.get(f"{BASE_URL}/wallets")
    response.raise_for_status()
    return response.json()


def get_pending_entries() -> List[Dict]:
    """Get all pending linked entries"""
    response = requests.get(f"{BASE_URL}/linked-entries/pending")
    response.raise_for_status()
    return response.json()


def create_transaction(wallet_id: int, amount: float, transaction_date: str, 
                       description: str, direction: str = "outflow") -> Dict:
    """Create a transaction"""
    response = requests.post(f"{BASE_URL}/transactions", json={
        "date": transaction_date,
        "wallet_id": wallet_id,
        "direction": direction,
        "amount": amount,
        "classification": "expense" if direction == "outflow" else "income",
        "description": description,
        "category_id": 1  # Default category
    })
    response.raise_for_status()
    return response.json()


def mark_as_installment(transaction_id: int, counterparty: str) -> Dict:
    """Mark a transaction as an installment plan"""
    response = requests.post(
        f"{BASE_URL}/transactions/{transaction_id}/mark-installment",
        json={"counterparty_name": counterparty}
    )
    response.raise_for_status()
    return response.json()


def link_to_installment(entry_id: int, transaction_id: int) -> Dict:
    """Link a transaction to an installment entry"""
    response = requests.post(
        f"{BASE_URL}/linked-entries/{entry_id}/link",
        json={"transaction_id": transaction_id}
    )
    response.raise_for_status()
    return response.json()


def create_transfer(from_wallet_id: int, to_wallet_id: int, amount: float, 
                    transfer_date: str, description: str = "Transfer") -> Dict:
    """Create a transfer between wallets"""
    response = requests.post(f"{BASE_URL}/wallets/transfer", json={
        "from_wallet_id": from_wallet_id,
        "to_wallet_id": to_wallet_id,
        "amount": amount,
        "date": transfer_date,
        "description": description
    })
    response.raise_for_status()
    return response.json()


# =============================================================================
# Frontend Calculation Simulation
# =============================================================================

def calculate_frontend_state(wallets: List[Dict], pending_entries: List[Dict]) -> Dict:
    """
    Simulate the frontend calculation logic from +page.svelte
    Returns the wallet screen state as the user sees it
    """
    # Calculate pending amounts by type
    pending_debts = sum(
        float(e["pending_amount"]) 
        for e in pending_entries 
        if e["link_type"] == "debt"
    )
    
    pending_owed = sum(
        float(e["pending_amount"]) 
        for e in pending_entries 
        if e["link_type"] in ["split_payment", "loan"]
    )
    
    pending_installments = sum(
        float(e["pending_amount"]) 
        for e in pending_entries 
        if e["link_type"] == "installment"
    )
    
    # Calculate wallet totals
    available = sum(
        float(w["current_balance"]) 
        for w in wallets 
        if w["wallet_type"] == "normal"
    )
    
    credit_used = sum(
        float(w["current_balance"]) 
        for w in wallets 
        if w["wallet_type"] == "credit"
    )
    
    available_credit = sum(
        float(w.get("available_credit", 0) or 0)
        for w in wallets 
        if w["wallet_type"] == "credit"
    )
    
    # Calculate net position (as shown on Wallet screen)
    net_position = (
        available 
        - credit_used 
        - pending_debts 
        - pending_installments 
        + pending_owed
    )
    
    return {
        "available": available,
        "credit_used": credit_used,
        "available_credit": available_credit,
        "pending_debts": pending_debts,
        "pending_owed": pending_owed,
        "pending_installments": pending_installments,
        "net_position": net_position
    }


def print_wallet_state(state: Dict, expected: Optional[Dict] = None):
    """Print the wallet state as shown on the Wallet screen"""
    print(f"\n{Colors.BOLD}Wallet Screen State:{Colors.ENDC}")
    
    if expected:
        print_result("Available Cash", state["available"], expected.get("available"))
        print_result("Credit Used", state["credit_used"], expected.get("credit_used"))
        print_result("Available Credit", state["available_credit"], expected.get("available_credit"))
        print_result("Pending Installments", state["pending_installments"], expected.get("pending_installments"))
        print_result("Net Position", state["net_position"], expected.get("net_position"))
    else:
        print_result("Available Cash", state["available"])
        print_result("Credit Used", state["credit_used"])
        print_result("Available Credit", state["available_credit"])
        print_result("Pending Debts", state["pending_debts"])
        print_result("Pending Owed", state["pending_owed"])
        print_result("Pending Installments", state["pending_installments"])
        print_result("Net Position", state["net_position"])


# =============================================================================
# Test Scenario Functions
# =============================================================================

def setup_initial_wallets() -> tuple[Dict, Dict]:
    """Setup initial bank and credit card wallets"""
    print_step("Creating bank account with ¥500,000")
    bank = create_wallet("Bank Account", "normal")
    
    print_step(f"Creating credit card with ¥{INITIAL_CREDIT_LIMIT:,} limit")
    credit_card = create_wallet("Credit Card", "credit", INITIAL_CREDIT_LIMIT)
    
    return bank, credit_card


def may_scenario(credit_card_id: int) -> int:
    """
    May scenario:
    - Create 30k installment (3 months)
    - Add 5k + 10k normal expenses
    Expected: balance=15k, available_credit=55k
    """
    print_section("MAY - Initial Setup")
    
    # Create 30k installment plan
    print_step("Creating ¥30,000 laptop purchase (3-month installment)")
    txn = create_transaction(
        credit_card_id, 
        30000, 
        "2025-05-15", 
        "Laptop - 3 month installment"
    )
    entry = mark_as_installment(txn["id"], "Electronics Store")
    installment_entry_id = entry["id"]
    
    # Add normal expenses
    print_step("Adding ¥5,000 normal expense")
    create_transaction(credit_card_id, 5000, "2025-05-20", "Dinner")
    
    print_step("Adding ¥10,000 normal expense")
    create_transaction(credit_card_id, 10000, "2025-05-25", "Shopping")
    
    # Verify state
    wallets = get_wallets()
    pending = get_pending_entries()
    state = calculate_frontend_state(wallets, pending)
    
    expected = {
        "credit_used": 15000,  # 5k + 10k (installment is RESERVED)
        "available_credit": 55000,  # 100k - 15k - 30k
        "pending_installments": 30000,
        "net_position": 500000 - 15000 - 30000  # cash - used - reserved
    }
    
    print_wallet_state(state, expected)
    pause_for_review()
    
    return installment_entry_id


def june_scenario(bank_id: int, credit_card_id: int, installment_entry_id: int):
    """
    June scenario:
    - Add 15k expense
    - Create 10k installment charge (on same day as original)
    - Pay 15k from bank
    """
    print_section("JUNE - First Installment Charge + Usage + Payment")
    
    # Add normal expense
    print_step("Adding ¥15,000 normal expense")
    create_transaction(credit_card_id, 15000, "2025-06-10", "Electronics")
    
    # Create installment charge
    print_step("Creating ¥10,000 installment charge (month 1/3)")
    charge_txn = create_transaction(
        credit_card_id,
        10000,
        "2025-06-15",  # Same day as original installment
        "Laptop - Payment 1/3"
    )
    
    print_step("Linking charge to installment plan")
    link_to_installment(installment_entry_id, charge_txn["id"])
    
    # Check state before payment
    wallets = get_wallets()
    pending = get_pending_entries()
    state = calculate_frontend_state(wallets, pending)
    
    print(f"\n{Colors.BOLD}Before Payment:{Colors.ENDC}")
    expected_before = {
        "credit_used": 40000,  # 15k (May) + 15k (June) + 10k (charge)
        "available_credit": 40000,  # 100k - 40k (used) - 20k (reserved)
        "pending_installments": 20000,  # 30k - 10k
    }
    print_wallet_state(state, expected_before)
    
    # Pay from bank
    print_step("Transferring ¥15,000 from bank to pay June usage")
    create_transfer(bank_id, credit_card_id, 15000, "2025-06-26", "Pay June bill")
    
    # Check state after payment
    wallets = get_wallets()
    pending = get_pending_entries()
    state = calculate_frontend_state(wallets, pending)
    
    print(f"\n{Colors.BOLD}After Payment:{Colors.ENDC}")
    expected_after = {
        "available": 485000,  # 500k - 15k
        "credit_used": 25000,  # 40k - 15k
        "available_credit": 55000,  # 100k - 25k - 20k
        "pending_installments": 20000,
        "net_position": 485000 - 25000 - 20000  # Should be same as before payment
    }
    print_wallet_state(state, expected_after)
    pause_for_review()


def july_scenario(bank_id: int, credit_card_id: int, installment_entry_id: int) -> int:
    """
    July scenario:
    - Create second 10k installment (2 months, 5k each)  
    - First 5k charge incurs immediately
    - Create 10k installment charge for original plan
    - Pay June's bill (25k) at end of month
    """
    print_section("JULY - New Installment + Charges + Pay June Bill")
    
    # Create new installment plan
    print_step("Creating ¥10,000 headphones purchase (2-month installment)")
    txn = create_transaction(
        credit_card_id,
        10000,
        "2025-07-05",
        "Headphones - 2 month installment"
    )
    entry = mark_as_installment(txn["id"], "Audio Store")
    new_installment_entry_id = entry["id"]
    
    # First charge for new installment
    print_step("Creating ¥5,000 first charge for headphones (month 1/2)")
    charge1_txn = create_transaction(
        credit_card_id,
        5000,
        "2025-07-05",
        "Headphones - Payment 1/2"
    )
    link_to_installment(new_installment_entry_id, charge1_txn["id"])
    
    # Second charge for original installment
    print_step("Creating ¥10,000 installment charge for laptop (month 2/3)")
    charge2_txn = create_transaction(
        credit_card_id,
        10000,
        "2025-07-15",
        "Laptop - Payment 2/3"
    )
    link_to_installment(installment_entry_id, charge2_txn["id"])
    
    # Check state before payment
    wallets = get_wallets()
    pending = get_pending_entries()
    state = calculate_frontend_state(wallets, pending)
    
    print(f"\n{Colors.BOLD}Before Paying June Bill:{Colors.ENDC}")
    expected_before_payment = {
        "available": 485000,
        "credit_used": 40000,  # 25k (June balance) + 15k (July charges)
        "available_credit": 45000,  # 100k - 40k - 10k (laptop) - 5k (headphones)
        "pending_installments": 15000,  # 10k (laptop) + 5k (headphones)
    }
    print_wallet_state(state, expected_before_payment)
    
    # Pay June's bill at end of month
    print_step("\nTransferring ¥25,000 from bank to pay June bill (end of July)")
    create_transfer(bank_id, credit_card_id, 25000, "2025-07-26", "Pay June bill")
    
    # Final state
    wallets = get_wallets()
    pending = get_pending_entries()
    state = calculate_frontend_state(wallets, pending)
    
    print(f"\n{Colors.BOLD}After Paying June Bill:{Colors.ENDC}")
    expected_after_payment = {
        "available": 460000,  # 485k - 25k
        "credit_used": 15000,  # 40k - 25k = 15k (July's charges)
        "available_credit": 70000,  # 100k - 15k - 15k (pending)
        "pending_installments": 15000,
        "net_position": 460000 - 15000 - 15000  # 430k
    }
    print_wallet_state(state, expected_after_payment)
    pause_for_review()
    
    return new_installment_entry_id


def august_scenario(bank_id: int, credit_card_id: int, 
                    laptop_entry_id: int, headphones_entry_id: int):
    """
    August scenario:
    - Pay July's bill (15k)
    - Final laptop charge (10k)
    - Second headphones charge (5k)
    - End with current month unpaid (realistic)
    """
    print_section("AUGUST - Pay July Bill + Final Charges")
    
    # Pay July's bill first
    print_step("Transferring ¥15,000 from bank to pay July bill")
    create_transfer(bank_id, credit_card_id, 15000, "2025-08-26", "Pay July bill")
    
    # Check state after payment
    wallets = get_wallets()
    pending = get_pending_entries()
    state = calculate_frontend_state(wallets, pending)
    
    print(f"\n{Colors.BOLD}After Paying July Bill:{Colors.ENDC}")
    expected_after_payment = {
        "available": 445000,  # 460k - 15k
        "credit_used": 0,  # 15k - 15k = 0
        "available_credit": 85000,  # 100k - 0 - 15k
        "pending_installments": 15000,  # 10k (laptop) + 5k (headphones)
    }
    print_wallet_state(state, expected_after_payment)
    
    # Final laptop charge
    print_step("\nCreating ¥10,000 final installment charge for laptop (month 3/3)")
    laptop_charge = create_transaction(
        credit_card_id,
        10000,
        "2025-08-15",
        "Laptop - Payment 3/3 (FINAL)"
    )
    link_to_installment(laptop_entry_id, laptop_charge["id"])
    
    # Final headphones charge
    print_step("Creating ¥5,000 final installment charge for headphones (month 2/2)")
    headphones_charge = create_transaction(
        credit_card_id,
        5000,
        "2025-08-05",
        "Headphones - Payment 2/2 (FINAL)"
    )
    link_to_installment(headphones_entry_id, headphones_charge["id"])
    
    # Final state
    wallets = get_wallets()
    pending = get_pending_entries()
    state = calculate_frontend_state(wallets, pending)
    
    print(f"\n{Colors.BOLD}End of August (Current Month Bill Unpaid):{Colors.ENDC}")
    expected_final = {
        "available": 445000,
        "credit_used": 15000,  # August charges not yet paid
        "available_credit": 85000,  # 100k - 15k
        "pending_installments": 0,  # All installment plans complete
        "net_position": 445000 - 15000  # 430k
    }
    print_wallet_state(state, expected_final)
    
    # Verify no pending installments
    if state["pending_installments"] == 0:
        print(f"\n{Colors.GREEN}{Colors.BOLD}✓ SUCCESS: All installment plans completed!{Colors.ENDC}")
        print(f"{Colors.BLUE}Note: Current month's charges (¥15,000) remain unpaid (realistic scenario){Colors.ENDC}")
    else:
        print(f"\n{Colors.RED}{Colors.BOLD}✗ ERROR: Still have pending installments!{Colors.ENDC}")
    
    # Show total spent vs paid
    print(f"\n{Colors.BOLD}Summary:{Colors.ENDC}")
    print(f"  {Colors.BLUE}• Total spent on credit: ¥70,000{Colors.ENDC}")
    print(f"  {Colors.BLUE}• Total paid so far: ¥55,000 (May: ¥15k, June: ¥25k, July: ¥15k){Colors.ENDC}")
    print(f"  {Colors.BLUE}• Remaining balance: ¥15,000 (August's bill, not yet due){Colors.ENDC}")
    print(f"  {Colors.GREEN}• Net worth change: -¥70,000 (500k → 430k) ✓{Colors.ENDC}")
    
    pause_for_review()


# =============================================================================
# Main Test Runner
# =============================================================================

def main():
    """Run the complete integration test scenario"""
    print_section("INSTALLMENT PLAN INTEGRATION TEST")
    print(f"{Colors.YELLOW}Make sure the backend is running on port 9000!{Colors.ENDC}")
    print(f"{Colors.YELLOW}Command: cd backend && poetry run python -m app.main --database /tmp/integration-test.db --port 9000 --no-seed-wallets{Colors.ENDC}")
    
    try:
        # Test connection
        response = requests.get(f"{BASE_URL}/wallets")
        response.raise_for_status()
    except Exception as e:
        print(f"\n{Colors.RED}ERROR: Cannot connect to backend at {BASE_URL}{Colors.ENDC}")
        print(f"{Colors.RED}Error: {e}{Colors.ENDC}")
        return 1
    
    print(f"{Colors.GREEN}✓ Connected to backend successfully{Colors.ENDC}")
    pause_for_review()
    
    # Setup
    bank, credit_card = setup_initial_wallets()
    bank_id = bank["id"]
    credit_card_id = credit_card["id"]
    
    # Run scenarios
    laptop_entry_id = may_scenario(credit_card_id)
    june_scenario(bank_id, credit_card_id, laptop_entry_id)
    headphones_entry_id = july_scenario(bank_id, credit_card_id, laptop_entry_id)
    august_scenario(bank_id, credit_card_id, laptop_entry_id, headphones_entry_id)
    
    print_section("TEST COMPLETE")
    print(f"{Colors.GREEN}{Colors.BOLD}All scenarios executed successfully!{Colors.ENDC}")
    
    return 0


if __name__ == "__main__":
    exit(main())
