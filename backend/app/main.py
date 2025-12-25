"""FastAPI application entry point."""
import argparse
import os
import sys
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import database
from app.database import init_db, get_db, set_database_path, get_database_path
from app.constants import APP_VERSION
from app.routers import (
    wallets,
    categories,
    transactions,
    linked_entries,
    budgets,
    wallets_extra,
    transactions_extra,
)
from app.utils.seed_data import seed_categories, seed_sample_wallets


# Global flag for wallet seeding (set by CLI)
# Note: Using env var instead of global because lifespan runs before main()
def should_skip_wallet_seed():
    return os.getenv("SKIP_WALLET_SEED", "0") == "1"

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan manager.
    
    Handles startup and shutdown tasks:
    - Initialize database tables
    - Seed initial categories
    - Optionally seed sample wallets (can be disabled with --no-seed-wallets)
    """
    # Startup: Initialize database
    print("🚀 Starting Expense Manager Backend...")
    print(f"v{APP_VERSION}")
    print(f"📂 Using database: {get_database_path()}")
    init_db()
    
    # Seed data
    db = next(get_db())
    try:
        seed_categories(db)
        if not should_skip_wallet_seed():
            seed_sample_wallets(db)
        else:
            print("⏭️  Skipping wallet seed (--no-seed-wallets)")
    finally:
        db.close()
    
    print("✓ Backend ready!")
    
    yield
    
    # Shutdown
    print("👋 Shutting down...")


# Create FastAPI app
app = FastAPI(
    title="Expense Manager API",
    description="Local-only expense manager backend with on-behalf reimbursement tracking",
    version=APP_VERSION,
    lifespan=lifespan,
)

# Configure CORS for local frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:1420",  # Tauri default dev port
        "http://localhost:5173",  # Vite default dev port
        "http://localhost:3000",  # Alternative dev port
        "tauri://localhost",      # Tauri production
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers
app.include_router(wallets.router, prefix="/api/wallets", tags=["wallets"])
app.include_router(wallets_extra.router, prefix="/api/wallets", tags=["wallets-extra"])
app.include_router(categories.router, prefix="/api/categories", tags=["categories"])
app.include_router(transactions.router, prefix="/api/transactions", tags=["transactions"])
app.include_router(transactions_extra.router, prefix="/api/transactions", tags=["transactions-extra"])
app.include_router(linked_entries.router, prefix="/api/linked-entries", tags=["linked-entries"])
app.include_router(budgets.router, prefix="/api/budgets", tags=["budgets"])


@app.get("/")
async def root():
    """Health check endpoint."""
    return {
        "message": "Expense Manager API",
        "status": "running",
        "version": APP_VERSION,
    }


@app.get("/api/health")
async def health():
    """API health check."""
    return {"status": "healthy"}


def main():
    """
    Main entry point for the backend application.
    
    Parses command-line arguments and starts the Uvicorn server.
    """
    parser = argparse.ArgumentParser(description="Expense Manager Backend")
    parser.add_argument(
        "--database",
        type=str,
        help="Path to SQLite database file (default: from DATABASE_PATH env or ./expense.db)",
        default=os.getenv("DATABASE_PATH")
    )
    parser.add_argument(
        "--host",
        type=str,
        default=os.getenv("HOST", "127.0.0.1"),
        help="Host to bind to (default: 127.0.0.1)"
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.getenv("PORT", "8000")),
        help="Port to bind to (default: 8000)"
    )
    parser.add_argument(
        "--no-seed-wallets",
        action="store_true",
        help="Skip seeding sample wallets on startup (useful for integration tests)"
    )
    
    args = parser.parse_args()
    
    # Set environment variable for wallet seeding (checked in lifespan)
    if args.no_seed_wallets:
        os.environ["SKIP_WALLET_SEED"] = "1"
    
    # Set database path if provided
    if args.database:
        try:
            database.set_database_path(args.database)
        except ValueError as e:
            print(f"❌ Error setting database path: {e}", file=sys.stderr)
            sys.exit(1)
    
    # Run the server
    uvicorn.run(
        "app.main:app",
        host=args.host,
        port=args.port,
        reload=False,  # Don't reload in production
        log_level="info"
    )


if __name__ == "__main__":
    main()
