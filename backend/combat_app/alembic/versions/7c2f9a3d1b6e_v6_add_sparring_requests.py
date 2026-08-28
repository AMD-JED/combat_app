"""v6: add sparring_requests

Adds the sparring matching system: manual request/accept between two
users plus scheduling fields (scheduled_at, location). `status` is a
plain indexed VARCHAR (not a native Postgres ENUM) — same convention as
post_reactions.reaction_type — so adding a new status later never needs
an ALTER TYPE migration.

gym_id / open_mat_id are intentionally NOT added here — they'll be added
by a v7 migration once the gyms / open_mats tables exist (see
app/models/sparring.py docstring). `location` is free text for now.

Revision ID: 7c2f9a3d1b6e
Revises: 1e4b0ace14d2
Create Date: 2026-08-27 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7c2f9a3d1b6e'
down_revision: Union[str, None] = '1e4b0ace14d2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'sparring_requests',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('requester_id', sa.Integer(), nullable=False),
        sa.Column('recipient_id', sa.Integer(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
        sa.Column('message', sa.Text(), nullable=True),
        sa.Column('scheduled_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('location', sa.String(length=200), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['requester_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['recipient_id'], ['users.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_sparring_requests_requester_id', 'sparring_requests', ['requester_id'])
    op.create_index('ix_sparring_requests_recipient_id', 'sparring_requests', ['recipient_id'])
    op.create_index('ix_sparring_requests_status', 'sparring_requests', ['status'])


def downgrade() -> None:
    op.drop_index('ix_sparring_requests_status', table_name='sparring_requests')
    op.drop_index('ix_sparring_requests_recipient_id', table_name='sparring_requests')
    op.drop_index('ix_sparring_requests_requester_id', table_name='sparring_requests')
    op.drop_table('sparring_requests')
