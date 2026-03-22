"""add snapshot unique constraint for existing databases

Revision ID: 8686665af780
Revises: dab26c86f09e
Create Date: 2026-03-22 18:17:54.352838

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '8686665af780'
down_revision: Union[str, Sequence[str], None] = 'dab26c86f09e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add unique constraint on (wallet_id, snapshot_date).

    For existing databases that may have duplicate snapshots, we first
    deduplicate by keeping only the most recent snapshot per wallet+date,
    then apply the constraint.
    """
    conn = op.get_bind()

    # 1. Remove duplicate snapshots (keep the one with highest id)
    conn.execute(sa.text("""
        DELETE FROM wallet_snapshots
        WHERE id NOT IN (
            SELECT MAX(id)
            FROM wallet_snapshots
            GROUP BY wallet_id, snapshot_date
        )
    """))

    # 2. Add the unique constraint via batch (required for SQLite)
    with op.batch_alter_table('wallet_snapshots', schema=None) as batch_op:
        batch_op.create_unique_constraint(
            'uq_wallet_snapshot_date', ['wallet_id', 'snapshot_date']
        )


def downgrade() -> None:
    """Remove the unique constraint."""
    with op.batch_alter_table('wallet_snapshots', schema=None) as batch_op:
        batch_op.drop_constraint('uq_wallet_snapshot_date', type_='unique')
