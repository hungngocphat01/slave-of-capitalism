"""Database configuration and session management."""
import os
from pathlib import Path
from sqlalchemy import create_engine, event
from sqlalchemy.orm import declarative_base, sessionmaker

# Database path - can be set via set_database_path() or DATABASE_PATH env var
DATABASE_PATH = os.getenv("DATABASE_PATH", "./expense.db")
_database_path = os.getenv("DATABASE_PATH", "./expense.db")
SQLALCHEMY_DATABASE_URL = f"sqlite:///{_database_path}"

# Create engine with check_same_thread=False for SQLite
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    echo=False,  # Set to True to see SQL queries in logs
)

# Enable foreign key constraints for SQLite
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_conn, connection_record):
    cursor = dbapi_conn.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()

# Session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def set_database_path(path: str) -> None:
    """
    Set the database path dynamically.
    
    This function reconfigures the database engine to use a different SQLite file.
    Should be called before init_db() and before any database operations.
    
    Args:
        path: Absolute or relative path to the SQLite database file
        
    Raises:
        ValueError: If path is invalid or parent directory doesn't exist
    """
    global engine, SessionLocal, SQLALCHEMY_DATABASE_URL, _database_path
    
    # Validate path
    db_path = Path(path).resolve()
    parent_dir = db_path.parent
    
    # Create parent directory if it doesn't exist
    if not parent_dir.exists():
        try:
            parent_dir.mkdir(parents=True, exist_ok=True)
            print(f"✓ Created database directory: {parent_dir}")
        except Exception as e:
            raise ValueError(f"Cannot create database directory {parent_dir}: {e}")
    
    if not parent_dir.is_dir():
        raise ValueError(f"Parent path is not a directory: {parent_dir}")
    
    # Update global variables
    _database_path = str(db_path)
    SQLALCHEMY_DATABASE_URL = f"sqlite:///{_database_path}"
    
    print(f"✓ Database path set to: {_database_path}")
    
    # Recreate engine with new path
    engine = create_engine(
        SQLALCHEMY_DATABASE_URL,
        connect_args={"check_same_thread": False},
        echo=False,
    )
    
    # Re-register SQLite pragma listener
    @event.listens_for(engine, "connect")
    def set_sqlite_pragma(dbapi_conn, connection_record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()
    
    # Recreate session factory
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_database_path() -> str:
    """
    Get the currently configured database path.
    
    Returns:
        str: Absolute path to the SQLite database file
    """
    return str(Path(_database_path).resolve())

# Base class for ORM models
Base = declarative_base()


def get_db():
    """
    Dependency function to get database session.
    
    Yields:
        Session: SQLAlchemy database session
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """
    Initialize database tables and check schema version.
    """
    from app.models import (
        wallet, category, subcategory, transaction, linked_entry, budget, system_metadata
    )
    
    # 1. Create all tables if they don't exist
    Base.metadata.create_all(bind=engine)
    
    # 2. Check SystemMetadata
    db = SessionLocal()
    try:
        from app.constants import APP_VERSION
        
        metadata = db.query(system_metadata.SystemMetadata).first()
        
        if not metadata:
            print("📝 Initializing new database metadata...")
            # New database, set initial version
            new_meta = system_metadata.SystemMetadata(
                app_version=APP_VERSION,
                schema_version=1
            )
            db.add(new_meta)
            db.commit()
            print(f"✅ Database initialized with schema version {new_meta.schema_version}")
            
        else:
            print(f"🔍 Found existing database (Schema v{metadata.schema_version})")
            # Verify version
            if metadata.schema_version != 1:
                # In real app, we would run migrations here
                error_msg = (
                    f"❌ Schema version mismatch! Expected 1, found {metadata.schema_version}. "
                    "Automatic migrations are not yet implemented."
                )
                print(error_msg)
                raise Exception(error_msg)
                
    except Exception as e:
        print(f"❌ Database initialization failed: {e}")
        raise e
    finally:
        db.close()
