"""Database configuration and session management."""
import os
from pathlib import Path
from sqlalchemy import create_engine, event
from sqlalchemy.orm import declarative_base, sessionmaker
from sqlalchemy.pool import StaticPool

# Base class for ORM models (must be defined before any model imports)
Base = declarative_base()

# Internal state
_database_path: str = os.getenv("DATABASE_PATH", "./expense.db")
_engine = None
_SessionLocal = None


def _make_engine(path: str):
    """Create a SQLAlchemy engine for the given SQLite path."""
    url = f"sqlite:///{path}" if path != ":memory:" else "sqlite:///:memory:"
    kwargs = {
        "connect_args": {"check_same_thread": False},
        "echo": False,
    }
    if path == ":memory:":
        kwargs["poolclass"] = StaticPool

    eng = create_engine(url, **kwargs)

    @event.listens_for(eng, "connect")
    def _set_sqlite_pragma(dbapi_conn, connection_record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    return eng


def _get_engine():
    """Lazy-initialize and return the current engine."""
    global _engine
    if _engine is None:
        _engine = _make_engine(_database_path)
    return _engine


def _get_session_factory():
    """Lazy-initialize and return the current session factory."""
    global _SessionLocal
    if _SessionLocal is None:
        _SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_get_engine())
    return _SessionLocal


def set_database_path(path: str) -> None:
    """
    Set the database path dynamically.

    Reconfigures the database engine to use a different SQLite file.
    Should be called before init_db() and before any database operations.
    """
    global _database_path, _engine, _SessionLocal

    if path == ":memory:":
        _database_path = ":memory:"
        print("✓ Database set to in-memory mode")
    else:
        db_path = Path(path).resolve()
        parent_dir = db_path.parent

        if not parent_dir.exists():
            try:
                parent_dir.mkdir(parents=True, exist_ok=True)
                print(f"✓ Created database directory: {parent_dir}")
            except Exception as e:
                raise ValueError(f"Cannot create database directory {parent_dir}: {e}")

        if not parent_dir.is_dir():
            raise ValueError(f"Parent path is not a directory: {parent_dir}")

        _database_path = str(db_path)
        print(f"✓ Database path set to: {_database_path}")

    # Reset so they are recreated on next access
    _engine = _make_engine(_database_path)
    _SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_engine)


def get_database_path() -> str:
    """Get the currently configured database path."""
    return str(Path(_database_path).resolve())


def get_db():
    """
    Dependency function to get database session.

    Yields:
        Session: SQLAlchemy database session
    """
    session_factory = _get_session_factory()
    db = session_factory()
    try:
        yield db
    finally:
        db.close()


def _run_alembic_migrations(engine):
    """Run pending Alembic migrations.

    For existing databases without an alembic_version table, stamps at the
    initial schema revision (since tables already exist) then applies any
    subsequent migrations.
    """
    try:
        from alembic.config import Config
        from alembic import command
        from sqlalchemy import inspect, text

        inspector = inspect(engine)
        existing_tables = inspector.get_table_names()
        has_alembic = "alembic_version" in existing_tables
        has_app_tables = "transactions" in existing_tables

        if has_app_tables and not has_alembic:
            # Existing production DB without Alembic tracking.
            # Stamp at initial schema (tables already exist), then upgrade.
            print("📌 Existing database detected — stamping Alembic baseline...")
            alembic_cfg = Config("alembic.ini")
            command.stamp(alembic_cfg, "dab26c86f09e")  # initial schema revision
            print("✓ Stamped at initial schema")
            # Now apply any subsequent migrations (e.g. snapshot unique constraint)
            command.upgrade(alembic_cfg, "head")
            print("✓ Applied pending migrations")
        elif has_alembic:
            # Already tracked — just upgrade
            alembic_cfg = Config("alembic.ini")
            command.upgrade(alembic_cfg, "head")
            print("✓ Alembic migrations up to date")
        # else: brand new DB — create_all handles it, stamp after

    except ImportError:
        print("⚠️  Alembic not installed — skipping migrations")
    except Exception as e:
        print(f"⚠️  Alembic migration warning: {e}")
        # Non-fatal: the app can still run with create_all tables


def init_db():
    """Initialize database tables and check schema version."""
    from app.models import (
        wallet, category, subcategory, transaction, linked_entry, budget, system_metadata
    )

    current_engine = _get_engine()
    session_factory = _get_session_factory()

    # Run Alembic migrations for existing databases
    _run_alembic_migrations(current_engine)

    # create_all is idempotent — creates only missing tables
    Base.metadata.create_all(bind=current_engine)

    db = session_factory()
    try:
        from app.constants import APP_VERSION

        metadata = db.query(system_metadata.SystemMetadata).first()

        if not metadata:
            print("📝 Initializing new database metadata...")
            new_meta = system_metadata.SystemMetadata(
                app_version=APP_VERSION,
                schema_version=2
            )
            db.add(new_meta)
            db.commit()
            print(f"✅ Database initialized with schema version {new_meta.schema_version}")

            # Stamp new DB at latest Alembic revision
            try:
                from alembic.config import Config
                from alembic import command
                alembic_cfg = Config("alembic.ini")
                command.stamp(alembic_cfg, "head")
                print("✓ Alembic stamped at head")
            except (ImportError, Exception):
                pass

        else:
            print(f"🔍 Found existing database (Schema v{metadata.schema_version})")
            if metadata.schema_version not in [1, 2]:
                error_msg = (
                    f"❌ Schema version mismatch! Expected 1 or 2, found {metadata.schema_version}. "
                    "Please run migration script."
                )
                print(error_msg)
                raise Exception(error_msg)
            elif metadata.schema_version == 1:
                print("⚠️  Schema version 1 detected. Consider running migration to v2.")

    except Exception as e:
        print(f"❌ Database initialization failed: {e}")
        raise e
    finally:
        db.close()
