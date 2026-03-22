# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec for the Expense Manager backend binary."""

import os
import importlib

block_cipher = None

# Collect alembic data files (templates, ini)
alembic_path = os.path.dirname(importlib.import_module("alembic").__file__)

a = Analysis(
    ["app/main.py"],
    pathex=[],
    binaries=[],
    datas=[
        # Include alembic migration files and config
        ("alembic", "alembic"),
        ("alembic.ini", "."),
        # Include alembic package data (templates)
        (alembic_path, "alembic_pkg"),
    ],
    hiddenimports=[
        # FastAPI and dependencies
        "uvicorn",
        "uvicorn.logging",
        "uvicorn.loops",
        "uvicorn.loops.auto",
        "uvicorn.protocols",
        "uvicorn.protocols.http",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.websockets",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.lifespan",
        "uvicorn.lifespan.on",
        "fastapi",
        "starlette",
        "starlette.middleware",
        "starlette.middleware.cors",
        # SQLAlchemy + SQLite
        "sqlalchemy",
        "sqlalchemy.sql.default_comparator",
        "sqlalchemy.ext.baked",
        # Alembic
        "alembic",
        "alembic.config",
        "alembic.command",
        "alembic.runtime.migration",
        # Pydantic
        "pydantic",
        "pydantic_core",
        # App modules
        "app",
        "app.main",
        "app.database",
        "app.constants",
        "app.models",
        "app.models.wallet",
        "app.models.category",
        "app.models.subcategory",
        "app.models.transaction",
        "app.models.linked_entry",
        "app.models.budget",
        "app.models.balance_audit",
        "app.models.snapshot",
        "app.models.system_metadata",
        "app.routers",
        "app.routers.wallets",
        "app.routers.wallets_extra",
        "app.routers.categories",
        "app.routers.transactions",
        "app.routers.transactions_extra",
        "app.routers.linked_entries",
        "app.routers.budgets",
        "app.schemas",
        "app.schemas.wallet",
        "app.schemas.category",
        "app.schemas.transaction",
        "app.schemas.linked_entry",
        "app.schemas.budget",
        "app.schemas.balance_audit",
        "app.services",
        "app.services.wallet_service",
        "app.services.transaction_service",
        "app.services.linked_entry_service",
        "app.services.snapshot_service",
        "app.services.budget_service",
        "app.services.category_service",
        "app.utils",
        "app.utils.seed_data",
        # Standard library modules sometimes missed
        "multiprocessing",
        "email.mime.multipart",
        "email.mime.text",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Exclude test/dev dependencies
        "pytest",
        "httpx",
        "freezegun",
        "tkinter",
        "_tkinter",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="expense-manager-backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
