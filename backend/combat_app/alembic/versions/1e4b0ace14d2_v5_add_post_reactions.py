"""v5: add post_reactions (rich reactions), drop post_likes

Replaces the plain like/unlike `post_likes` association table with
`post_reactions`, which stores one of 6 reaction types per (post, user)
pair — see ReactionType in app/models/post.py. Existing rows in
`post_likes` are preserved by migrating them into `post_reactions` as
'fire' reactions (the closest semantic equivalent to a plain "like")
before the old table is dropped.

Revision ID: 1e4b0ace14d2
Revises: 0b75a8b29c3c
Create Date: 2026-08-20 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '1e4b0ace14d2'
down_revision: Union[str, None] = '0b75a8b29c3c'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1) New table. reaction_type is a plain indexed VARCHAR (not a native
    # Postgres ENUM) — validated at the Pydantic layer instead, so adding a
    # 7th reaction type later never needs an ALTER TYPE migration.
    op.create_table(
        'post_reactions',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('post_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('reaction_type', sa.String(length=20), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['post_id'], ['posts.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('post_id', 'user_id', name='uq_post_reactions_post_user'),
    )
    op.create_index('ix_post_reactions_post_id', 'post_reactions', ['post_id'])
    op.create_index('ix_post_reactions_user_id', 'post_reactions', ['user_id'])

    # 2) Preserve existing likes as 'fire' reactions. `post_likes` only
    # exists if this DB actually has the old table (it always does at this
    # revision, since down_revision is the stamped baseline that included
    # it) — safe to reference directly.
    op.execute(
        """
        INSERT INTO post_reactions (post_id, user_id, reaction_type, created_at)
        SELECT post_id, user_id, 'fire', now()
        FROM post_likes
        ON CONFLICT (post_id, user_id) DO NOTHING
        """
    )

    # 3) Drop the old association table — post_reactions is now the single
    # source of truth for both the legacy /like endpoint and the new
    # /react endpoint.
    op.drop_table('post_likes')


def downgrade() -> None:
    op.create_table(
        'post_likes',
        sa.Column('user_id', sa.Integer(), primary_key=True),
        sa.Column('post_id', sa.Integer(), primary_key=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id']),
        sa.ForeignKeyConstraint(['post_id'], ['posts.id']),
    )
    op.execute(
        """
        INSERT INTO post_likes (post_id, user_id)
        SELECT DISTINCT post_id, user_id FROM post_reactions
        ON CONFLICT DO NOTHING
        """
    )
    op.drop_index('ix_post_reactions_user_id', table_name='post_reactions')
    op.drop_index('ix_post_reactions_post_id', table_name='post_reactions')
    op.drop_table('post_reactions')
