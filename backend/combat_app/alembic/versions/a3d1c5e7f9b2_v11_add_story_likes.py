"""v11: add story_likes

Adds:
  - story_likes (story_id -> stories.id, user_id -> users.id), unique per
    (story, user) so the like endpoint is a clean toggle.

No existing table is altered, so this runs identically on SQLite and
PostgreSQL (plain create_table / create_index, no batch mode needed).

Revision ID: a3d1c5e7f9b2
Revises: b98ba94dafb7
Create Date: 2026-10-06 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a3d1c5e7f9b2'
down_revision: Union[str, None] = 'b98ba94dafb7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'story_likes',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('story_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['story_id'], ['stories.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('story_id', 'user_id', name='uq_story_likes_story_user'),
    )
    op.create_index('ix_story_likes_story_id', 'story_likes', ['story_id'])
    op.create_index('ix_story_likes_user_id', 'story_likes', ['user_id'])


def downgrade() -> None:
    op.drop_index('ix_story_likes_user_id', table_name='story_likes')
    op.drop_index('ix_story_likes_story_id', table_name='story_likes')
    op.drop_table('story_likes')
