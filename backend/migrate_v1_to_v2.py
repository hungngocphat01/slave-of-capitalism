#!/usr/bin/env python3
"""
Database Migration Script: v1 (0.1.0) → v2 (0.2.0)

Simple migration that updates version metadata and invalidates cached snapshots.
No data transformations needed - validates that production data is correct.

Usage:
    python migrate_v1_to_v2.py --database <path> [--dry-run]
"""

import argparse
import sqlite3
import sys
from datetime import datetime
from decimal import Decimal
from pathlib import Path
import shutil


def log(message: str, level: str = "INFO"):
    """Log a message with timestamp."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {level}: {message}")


def validate_split_payment_math(conn: sqlite3.Connection) -> bool:
    """
    Validate that split payment pending amounts are calculated correctly.
    
    Formula: pending_amount = (total_amount - user_amount) - settled_amount
    """
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT 
            le.id,
            le.total_amount,
            le.user_amount,
            le.pending_amount,
            COALESCE(SUM(t.amount), 0) as settled_amount
        FROM linked_entries le
        LEFT JOIN linked_transactions lt ON le.id = lt.linked_entry_id
        LEFT JOIN transactions t ON lt.transaction_id = t.id
        WHERE le.link_type = 'SPLIT_PAYMENT'
        GROUP BY le.id
    """)
    
    all_correct = True
    for row in cursor.fetchall():
        entry_id = row[0]
        total = Decimal(str(row[1]))
        user = Decimal(str(row[2]))
        pending = Decimal(str(row[3]))
        settled = Decimal(str(row[4]))
        
        expected = (total - user) - settled
        
        if abs(pending - expected) > Decimal("0.01"):
            log(f"ERROR: Entry {entry_id} has incorrect pending_amount", "ERROR")
            log(f"  Expected: {expected}, Actual: {pending}", "ERROR")
            all_correct = False
        else:
            log(f"  Entry {entry_id}: ✓ pending_amount correct")
    
    return all_correct


def validate_database(conn: sqlite3.Connection) -> bool:
    """Run all validation checks."""
    log("Validating database...")
    cursor = conn.cursor()
    
    # Check schema version
    metadata = cursor.execute("SELECT * FROM system_metadata").fetchone()
    if not metadata:
        log("ERROR: No system_metadata record found", "ERROR")
        return False
    
    schema_version = metadata[2]
    app_version = metadata[1]
    
    log(f"  Current schema version: {schema_version}")
    log(f"  Current app version: {app_version}")
    
    if schema_version != 1:
        log(f"ERROR: Expected schema version 1, found {schema_version}", "ERROR")
        return False
    
    # Validate split payment math
    log("Validating split payment calculations...")
    if not validate_split_payment_math(conn):
        return False
    
    log("✓ All validations passed", "INFO")
    return True


def migrate_database(db_path: str, dry_run: bool = False) -> bool:
    """Perform the migration."""
    
    log("="*80)
    log("DATABASE MIGRATION: v1 → v2")
    log("="*80)
    log(f"Database: {db_path}")
    log(f"Mode: {'DRY-RUN' if dry_run else 'MIGRATION'}")
    log("")
    
    # Validate database exists
    if not Path(db_path).exists():
        log(f"ERROR: Database not found: {db_path}", "ERROR")
        return False
    
    # Create backup (unless dry-run)
    if not dry_run:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = f"{db_path}.backup_{timestamp}"
        log(f"Creating backup: {backup_path}")
        shutil.copy2(db_path, backup_path)
        log(f"✓ Backup created")
        log("")
    
    # Connect and validate
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    try:
        if not validate_database(conn):
            log("Validation failed - cannot proceed", "ERROR")
            return False
        
        if dry_run:
            log("")
            log("Dry-run complete - no changes made")
            return True
        
        # Perform migration
        log("")
        log("Performing migration...")
        
        cursor.execute("BEGIN TRANSACTION")
        
        # Update system_metadata
        log("  Updating system metadata...")
        cursor.execute("""
            UPDATE system_metadata
            SET schema_version = 2,
                app_version = '0.2.0'
            WHERE id = 1
        """)
        log("    ✓ schema_version: 1 → 2")
        log("    ✓ app_version: 0.1.0 → 0.2.0")
        
        # Invalidate snapshots
        log("  Invalidating wallet snapshots...")
        cursor.execute("SELECT COUNT(*) FROM wallet_snapshots")
        count = cursor.fetchone()[0]
        
        cursor.execute("DELETE FROM wallet_snapshots")
        log(f"    ✓ Deleted {count} cached snapshots")
        log(f"    ✓ App will recalculate balances on next run")
        
        # Commit
        conn.commit()
        log("")
        log("✓ Migration completed successfully!")
        
        # Verify
        log("")
        log("Verifying migration...")
        metadata = cursor.execute("SELECT * FROM system_metadata WHERE id = 1").fetchone()
        log(f"  Schema version: {metadata[2]}")
        log(f"  App version: {metadata[1]}")
        
        return True
        
    except Exception as e:
        if not dry_run:
            conn.rollback()
            log(f"ERROR: Migration failed: {e}", "ERROR")
        return False
        
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser(
        description="Migrate expense manager database from v1 to v2"
    )
    
    parser.add_argument(
        '--database',
        required=True,
        help='Path to the database file'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Validate only, do not modify database'
    )
    
    args = parser.parse_args()
    
    # Expand path
    db_path = str(Path(args.database).expanduser().resolve())
    
    # Run migration
    success = migrate_database(db_path, dry_run=args.dry_run)
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
