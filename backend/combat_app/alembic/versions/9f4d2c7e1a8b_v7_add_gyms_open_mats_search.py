"""v7: add gyms, open_mats, and link sparring_requests to them

Adds:
  - gyms (owner_id -> users.id, sports as JSON/JSONB list)
  - gym_memberships (gym_id + user_id unique, role as VARCHAR)
  - open_mats (gym_id -> gyms.id, one-time OR recurring schedule shape)
  - open_mat_rsvps (open_mat_id + user_id unique)
  - sparring_requests.gym_id / sparring_requests.open_mat_id (nullable
    FKs) — closing the loop promised in the v6 migration docstring, now
    that these tables exist.

No unified-search table/index is added here — GET /search is plain
per-table ILIKE (see app/repositories/search_repository.py), so it needs
no schema of its own.

`sports` on gyms and `attributes` on user_sport_profiles use the same
JSONB(Postgres)/JSON(SQLite) pattern via FlexibleJSON — see
app/models/sport.py. Alembic can't reference that Python-level
with_variant() object directly in a migration, so this migration issues
the dialect-appropriate column type directly (JSONB row on the batch,
falling back cleanly since `sa.JSON()` renders correctly on both
Postgres and SQLite).

Revision ID: 9f4d2c7e1a8b
Revises: 7c2f9a3d1b6e
Create Date: 2026-08-30 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '9f4d2c7e1a8b'
down_revision: Union[str, None] = '7c2f9a3d1b6e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── gyms ──────────────────────────────────────────────
    op.create_table(
        'gyms',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('owner_id', sa.Integer(), nullable=True),
        sa.Column('name', sa.String(length=150), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('location', sa.String(length=200), nullable=True),
        sa.Column('sports', sa.JSON(), nullable=False, server_default='[]'),
        sa.Column('contact_phone', sa.String(length=30), nullable=True),
        sa.Column('contact_email', sa.String(length=255), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_gyms_owner_id', 'gyms', ['owner_id'])
    op.create_index('ix_gyms_name', 'gyms', ['name'])

    # ── gym_memberships ──────────────────────────────────────────────
    op.create_table(
        'gym_memberships',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('gym_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('role', sa.String(length=20), nullable=False, server_default='member'),
        sa.Column('joined_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['gym_id'], ['gyms.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('gym_id', 'user_id', name='uq_gym_user'),
    )
    op.create_index('ix_gym_memberships_gym_id', 'gym_memberships', ['gym_id'])
    op.create_index('ix_gym_memberships_user_id', 'gym_memberships', ['user_id'])
    op.create_index('ix_gym_memberships_role', 'gym_memberships', ['role'])

    # ── open_mats ──────────────────────────────────────────────
    op.create_table(
        'open_mats',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('gym_id', sa.Integer(), nullable=False),
        sa.Column('created_by', sa.Integer(), nullable=True),
        sa.Column('title', sa.String(length=150), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('is_recurring', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('event_datetime', sa.DateTime(timezone=True), nullable=True),
        sa.Column('recurrence_day', sa.String(length=10), nullable=True),
        sa.Column('start_time', sa.Time(), nullable=True),
        sa.Column('end_time', sa.Time(), nullable=True),
        sa.Column('location_override', sa.String(length=200), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['gym_id'], ['gyms.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['created_by'], ['users.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_open_mats_gym_id', 'open_mats', ['gym_id'])

    # ── open_mat_rsvps ──────────────────────────────────────────────
    op.create_table(
        'open_mat_rsvps',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('open_mat_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['open_mat_id'], ['open_mats.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('open_mat_id', 'user_id', name='uq_open_mat_user'),
    )
    op.create_index('ix_open_mat_rsvps_open_mat_id', 'open_mat_rsvps', ['open_mat_id'])
    op.create_index('ix_open_mat_rsvps_user_id', 'open_mat_rsvps', ['user_id'])

    # ── sparring_requests: link to gym / open_mat (v6 promise, closed now) ──
    # batch_alter_table: on Postgres this just issues the ALTER directly;
    # SQLite has no native ALTER ADD CONSTRAINT, so it needs the
    # copy-recreate-swap strategy batch mode provides. Using it here
    # keeps this migration runnable on both dialects, not just Postgres.
    with op.batch_alter_table('sparring_requests') as batch_op:
        batch_op.add_column(sa.Column('gym_id', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('open_mat_id', sa.Integer(), nullable=True))
        batch_op.create_index('ix_sparring_requests_gym_id', ['gym_id'])
        batch_op.create_index('ix_sparring_requests_open_mat_id', ['open_mat_id'])
        batch_op.create_foreign_key(
            'fk_sparring_requests_gym_id', 'gyms', ['gym_id'], ['id'], ondelete='SET NULL'
        )
        batch_op.create_foreign_key(
            'fk_sparring_requests_open_mat_id', 'open_mats', ['open_mat_id'], ['id'], ondelete='SET NULL'
        )


def downgrade() -> None:
    with op.batch_alter_table('sparring_requests') as batch_op:
        batch_op.drop_constraint('fk_sparring_requests_open_mat_id', type_='foreignkey')
        batch_op.drop_constraint('fk_sparring_requests_gym_id', type_='foreignkey')
        batch_op.drop_index('ix_sparring_requests_open_mat_id')
        batch_op.drop_index('ix_sparring_requests_gym_id')
        batch_op.drop_column('open_mat_id')
        batch_op.drop_column('gym_id')

    op.drop_index('ix_open_mat_rsvps_user_id', table_name='open_mat_rsvps')
    op.drop_index('ix_open_mat_rsvps_open_mat_id', table_name='open_mat_rsvps')
    op.drop_table('open_mat_rsvps')

    op.drop_index('ix_open_mats_gym_id', table_name='open_mats')
    op.drop_table('open_mats')

    op.drop_index('ix_gym_memberships_role', table_name='gym_memberships')
    op.drop_index('ix_gym_memberships_user_id', table_name='gym_memberships')
    op.drop_index('ix_gym_memberships_gym_id', table_name='gym_memberships')
    op.drop_table('gym_memberships')

    op.drop_index('ix_gyms_name', table_name='gyms')
    op.drop_index('ix_gyms_owner_id', table_name='gyms')
    op.drop_table('gyms')
