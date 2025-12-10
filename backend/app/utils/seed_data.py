"""Seed data for initial categories and subcategories."""
from sqlalchemy.orm import Session

from app.models.category import Category
from app.models.subcategory import Subcategory


# Initial category structure as provided by user
# All amounts in JPY (Japanese Yen)
INITIAL_CATEGORIES = [
    {
        "name": "Food",
        "emoji": "🍔",
        "color": "#FF6B6B",
        "subcategories": [
            "Market groceries",
            "Combini coffee",
            "Combini breakfast",
            "Combini lunch/dinner",
            "Dining out",
            "Drinks & snacks",
        ],
    },
    {
        "name": "Shopping",
        "emoji": "🛍️",
        "color": "#4ECDC4",
        "subcategories": [
            "Clothing",
            "Supermarket – household",
            "Supermarket – other",
            "Amazon",
            "Otaku goods",
        ],
    },
    {
        "name": "Miscellaneous",
        "emoji": "📦",
        "color": "#95E1D3",
        "subcategories": [],
    },
    {
        "name": "Subscriptions",
        "emoji": "📺",
        "color": "#F38181",
        "subcategories": [],
    },
    {
        "name": "Rent",
        "emoji": "🏠",
        "color": "#AA96DA",
        "subcategories": [],
    },
    {
        "name": "Trips",
        "emoji": "✈️",
        "color": "#FCBAD3",
        "subcategories": [],
    },
    {
        "name": "Unexpected expenses",
        "emoji": "⚠️",
        "color": "#FFD93D",
        "subcategories": [],
    },
]


def seed_categories(db: Session) -> None:
    """
    Seed database with initial categories and subcategories.
    
    Ensures system categories (Miscellaneous, Unexpected expenses) always exist.
    Only seeds other initial categories if the database is empty.
    
    Args:
        db: Database session
    """
    # 1. Identify mandatory system categories
    SYSTEM_CATEGORY_NAMES = {"Miscellaneous", "Unexpected expenses"}
    
    # 2. Check if we should seed the general set (if DB is effectively empty)
    # We check this BEFORE adding missing system categories
    existing_count = db.query(Category).count()
    should_seed_general = existing_count == 0
    
    print("Checking system categories...")
    
    # 3. Ensure system categories exist and are correct
    for cat_data in INITIAL_CATEGORIES:
        if cat_data["name"] in SYSTEM_CATEGORY_NAMES:
            category = db.query(Category).filter(Category.name == cat_data["name"]).first()
            
            if category:
                # Update if exists but not system
                if not category.is_system:
                    print(f"  Fixing system flag for '{category.name}'")
                    category.is_system = True
                    db.add(category)
            else:
                # Create if missing
                print(f"  Creating missing system category '{cat_data['name']}'")
                category = Category(
                    name=cat_data["name"],
                    emoji=cat_data["emoji"],
                    color=cat_data["color"],
                    is_system=True
                )
                db.add(category)
                db.flush() # Flush to get ID for subcats (though system cats usually don't have initial subcats, but good practice)
                
                # Check for subcategories in initial data (Misc/Unexpected list is empty in definition, but generic logic)
                for subcat_name in cat_data["subcategories"]:
                    # Note: We don't check existence of subcats for system cats deeply here, 
                    # assuming system cats defined above don't have subcats in INITIAL list.
                    pass

    db.commit()

    # 4. Seed general categories only if DB was empty
    if should_seed_general:
        print("Seeding initial general categories...")
        for cat_data in INITIAL_CATEGORIES:
            # Skip if it's one of the system categories we already handled/checked
            if cat_data["name"] in SYSTEM_CATEGORY_NAMES:
                continue
                
            # Create category
            category = Category(
                name=cat_data["name"],
                emoji=cat_data["emoji"],
                color=cat_data["color"],
                # For general categories, we might want them to be user-deletable?
                # The original code set is_system=True for EVERYTHING.
                # User request only specified Misc/Unexpected as system.
                # I'll set others to is_system=False to allow flexibility, 
                # unless "Apple style" implies rigid safety. 
                # Let's set is_system=False for others for better UX.
                is_system=False 
            )
            db.add(category)
            db.flush()
            
            # Create subcategories
            for subcat_name in cat_data["subcategories"]:
                subcategory = Subcategory(
                    category_id=category.id,
                    name=subcat_name,
                    is_system=False
                )
                db.add(subcategory)
            
            print(f"  ✓ Created '{category.emoji} {category.name}'")
        
        db.commit()
        print("✓ Seed complete!")
    else:
        print("✓ System categories verified. Skipping general seed (data exists).")


def seed_sample_wallets(db: Session) -> None:
    """
    Seed sample wallets for testing.
    
    All amounts in JPY (Japanese Yen).
    
    Args:
        db: Database session
    """
    from app.services import wallet_service
    from app.schemas.wallet import WalletCreate
    from app.models.wallet import Wallet, WalletType
    from decimal import Decimal
    
    # Check if already seeded
    existing_count = db.query(Wallet).count()
    if existing_count > 0:
        print(f"Wallets already exist ({existing_count} found). Skipping wallet seed.")
        return
    
    print("Seeding sample wallets...")
    
    sample_wallets = [
        {
            "name": "Cash",
            "wallet_type": WalletType.NORMAL,
            "initial_balance": Decimal("10000.00"),
            "credit_limit": Decimal("0.00"),
        },
        {
            "name": "Bank Account",
            "wallet_type": WalletType.NORMAL,
            "initial_balance": Decimal("50000.00"),
            "credit_limit": Decimal("0.00"),
        },
        {
            "name": "PayPay",
            "wallet_type": WalletType.NORMAL,
            "initial_balance": Decimal("5000.00"),
            "credit_limit": Decimal("0.00"),
        },
        {
            "name": "Visa Card",
            "wallet_type": WalletType.CREDIT,
            "initial_balance": Decimal("0.00"),
            "credit_limit": Decimal("100000.00"),
        },
    ]
    
    for wallet_data in sample_wallets:
        wallet_create = WalletCreate(**wallet_data)
        wallet = wallet_service.create_wallet(db, wallet_create)
        
        if wallet.wallet_type == WalletType.CREDIT:
            print(f"  ✓ Created credit wallet '{wallet.name}' with ¥{wallet.credit_limit} limit")
        else:
            print(f"  ✓ Created wallet '{wallet.name}' with ¥{wallet_data['initial_balance']}")
    
    # Commit handled by create_wallet, but seed_categories does db.commit() at end.
    # create_wallet does explicit commit.
    print("✓ Wallet seed complete!")
