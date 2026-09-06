"""v9: add stories, story_views, highlights, highlight_stories, reels,
reel_likes; alter comments (nullable post_id + new reel_id + CHECK
constraint) and messages (new reply_to_story_id)

Adds:
  - stories (author_id -> users.id)
  - story_views (story_id -> stories.id, viewer_id -> users.id)
  - highlights (user_id -> users.id)
  - highlight_stories (highlight_id -> highlights.id, story_id -> stories.id)
  - reels (author_id -> users.id; optional sport_id -> sports.id;
    includes a nullable analysis_job_id forward-compat hook, same
    convention as training_exercise_logs.analysis_job_id)
  - reel_likes (reel_id -> reels.id, user_id -> users.id)

Alters (batch_alter_table — SQLite has no native ALTER for loosening a
NOT NULL column or adding a CHECK constraint, so batch mode's
copy-recreate-swap strategy is required to stay runnable on both
dialects, same convention as v7's sparring_requests alteration):
  - comments: post_id becomes nullable, new nullable reel_id column +
    FK + index, new CHECK constraint ck_comments_exactly_one_target
    ensuring exactly one of (post_id, reel_id) is set.
  - messages: new nullable reply_to_story_id column + FK + index.

Revision ID: e2f012da2b38
Revises: c4f8a2b6d1e3
Create Date: 2026-09-06 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e2f012da2b38'
down_revision: Union[str, None] = 'c4f8a2b6d1e3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── stories ──────────────────────────────────────────────────────
    op.create_table(
        'stories',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('author_id', sa.Integer(), nullable=False),
        sa.Column('content_type', sa.String(length=10), nullable=False),
        sa.Column('media_url', sa.String(length=500), nullable=True),
        sa.Column('text_content', sa.Text(), nullable=True),
        sa.Column('background_color', sa.String(length=20), nullable=True),
        sa.Column('visibility', sa.String(length=20), nullable=False, server_default='public'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(['author_id'], ['users.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_stories_author_id', 'stories', ['author_id'])
    op.create_index('ix_stories_content_type', 'stories', ['content_type'])
    op.create_index('ix_stories_visibility', 'stories', ['visibility'])
    op.create_index('ix_stories_expires_at', 'stories', ['expires_at'])

    # ── story_views ──────────────────────────────────────────────────
    op.create_table(
        'story_views',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('story_id', sa.Integer(), nullable=False),
        sa.Column('viewer_id', sa.Integer(), nullable=False),
        sa.Column('viewed_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['story_id'], ['stories.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['viewer_id'], ['users.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('story_id', 'viewer_id', name='uq_story_views_story_viewer'),
    )
    op.create_index('ix_story_views_story_id', 'story_views', ['story_id'])
    op.create_index('ix_story_views_viewer_id', 'story_views', ['viewer_id'])

    # ── highlights ───────────────────────────────────────────────────
    op.create_table(
        'highlights',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('title', sa.String(length=50), nullable=False),
        sa.Column('cover_media_url', sa.String(length=500), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_highlights_user_id', 'highlights', ['user_id'])

    # ── highlight_stories ────────────────────────────────────────────
    op.create_table(
        'highlight_stories',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('highlight_id', sa.Integer(), nullable=False),
        sa.Column('story_id', sa.Integer(), nullable=False),
        sa.Column('order_index', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('added_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['highlight_id'], ['highlights.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['story_id'], ['stories.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('highlight_id', 'story_id', name='uq_highlight_stories_highlight_story'),
    )
    op.create_index('ix_highlight_stories_highlight_id', 'highlight_stories', ['highlight_id'])
    op.create_index('ix_highlight_stories_story_id', 'highlight_stories', ['story_id'])

    # ── reels ────────────────────────────────────────────────────────
    op.create_table(
        'reels',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('author_id', sa.Integer(), nullable=False),
        sa.Column('media_url', sa.String(length=500), nullable=False),
        sa.Column('thumbnail_url', sa.String(length=500), nullable=True),
        sa.Column('caption', sa.Text(), nullable=True),
        sa.Column('sport_id', sa.Integer(), nullable=True),
        sa.Column('duration_seconds', sa.Integer(), nullable=True),
        sa.Column('view_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('analysis_job_id', sa.String(length=100), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['author_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['sport_id'], ['sports.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_reels_author_id', 'reels', ['author_id'])
    op.create_index('ix_reels_sport_id', 'reels', ['sport_id'])
    op.create_index('ix_reels_analysis_job_id', 'reels', ['analysis_job_id'])

    # ── reel_likes ───────────────────────────────────────────────────
    op.create_table(
        'reel_likes',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('reel_id', sa.Integer(), nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['reel_id'], ['reels.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('reel_id', 'user_id', name='uq_reel_likes_reel_user'),
    )
    op.create_index('ix_reel_likes_reel_id', 'reel_likes', ['reel_id'])
    op.create_index('ix_reel_likes_user_id', 'reel_likes', ['user_id'])

    # ── comments: post_id -> nullable, + reel_id, + CHECK constraint ──
    # batch_alter_table: SQLite has no native ALTER COLUMN / ADD CONSTRAINT,
    # so it needs the copy-recreate-swap strategy batch mode provides.
    with op.batch_alter_table('comments') as batch_op:
        batch_op.alter_column('post_id', existing_type=sa.Integer(), nullable=True)
        batch_op.add_column(sa.Column('reel_id', sa.Integer(), nullable=True))
        batch_op.create_index('ix_comments_post_id', ['post_id'])
        batch_op.create_index('ix_comments_reel_id', ['reel_id'])
        batch_op.create_foreign_key(
            'fk_comments_reel_id', 'reels', ['reel_id'], ['id'], ondelete='CASCADE'
        )
        batch_op.create_check_constraint(
            'ck_comments_exactly_one_target',
            '(post_id IS NOT NULL) != (reel_id IS NOT NULL)',
        )

    # ── messages: + reply_to_story_id ─────────────────────────────────
    with op.batch_alter_table('messages') as batch_op:
        batch_op.add_column(sa.Column('reply_to_story_id', sa.Integer(), nullable=True))
        batch_op.create_index('ix_messages_reply_to_story_id', ['reply_to_story_id'])
        batch_op.create_foreign_key(
            'fk_messages_reply_to_story_id', 'stories', ['reply_to_story_id'], ['id'], ondelete='SET NULL'
        )


def downgrade() -> None:
    with op.batch_alter_table('messages') as batch_op:
        batch_op.drop_constraint('fk_messages_reply_to_story_id', type_='foreignkey')
        batch_op.drop_index('ix_messages_reply_to_story_id')
        batch_op.drop_column('reply_to_story_id')

    with op.batch_alter_table('comments') as batch_op:
        batch_op.drop_constraint('ck_comments_exactly_one_target', type_='check')
        batch_op.drop_constraint('fk_comments_reel_id', type_='foreignkey')
        batch_op.drop_index('ix_comments_reel_id')
        batch_op.drop_index('ix_comments_post_id')
        batch_op.drop_column('reel_id')
        batch_op.alter_column('post_id', existing_type=sa.Integer(), nullable=False)

    op.drop_index('ix_reel_likes_user_id', table_name='reel_likes')
    op.drop_index('ix_reel_likes_reel_id', table_name='reel_likes')
    op.drop_table('reel_likes')

    op.drop_index('ix_reels_analysis_job_id', table_name='reels')
    op.drop_index('ix_reels_sport_id', table_name='reels')
    op.drop_index('ix_reels_author_id', table_name='reels')
    op.drop_table('reels')

    op.drop_index('ix_highlight_stories_story_id', table_name='highlight_stories')
    op.drop_index('ix_highlight_stories_highlight_id', table_name='highlight_stories')
    op.drop_table('highlight_stories')

    op.drop_index('ix_highlights_user_id', table_name='highlights')
    op.drop_table('highlights')

    op.drop_index('ix_story_views_viewer_id', table_name='story_views')
    op.drop_index('ix_story_views_story_id', table_name='story_views')
    op.drop_table('story_views')

    op.drop_index('ix_stories_expires_at', table_name='stories')
    op.drop_index('ix_stories_visibility', table_name='stories')
    op.drop_index('ix_stories_content_type', table_name='stories')
    op.drop_index('ix_stories_author_id', table_name='stories')
    op.drop_table('stories')
