"""v10: add notifications, device_tokens, session_reminders

Adds:
  - notifications (recipient_id -> users.id, actor_id -> users.id nullable)
  - device_tokens (user_id -> users.id; fcm_token globally unique — see
    DeviceToken docstring in app/models/notification.py for why)
  - session_reminders (user_id -> users.id; session_id -> training_sessions.id)

No alterations to existing tables this time — message.reply_to_story_id
was already added in v9.

Revision ID: b98ba94dafb7
Revises: e2f012da2b38
Create Date: 2026-09-08 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b98ba94dafb7'
down_revision: Union[str, None] = 'e2f012da2b38'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── notifications ────────────────────────────────────────────────
    op.create_table(
        'notifications',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('recipient_id', sa.Integer(), nullable=False),
        sa.Column('actor_id', sa.Integer(), nullable=True),
        sa.Column('type', sa.String(length=30), nullable=False),
        sa.Column('title', sa.String(length=200), nullable=False),
        sa.Column('body', sa.Text(), nullable=False),
        sa.Column('data', sa.JSON(), nullable=False, server_default='{}'),
        sa.Column('is_read', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['recipient_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['actor_id'], ['users.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_notifications_recipient_id', 'notifications', ['recipient_id'])
    op.create_index('ix_notifications_type', 'notifications', ['type'])
    op.create_index('ix_notifications_is_read', 'notifications', ['is_read'])

    # ── device_tokens ────────────────────────────────────────────────
    op.create_table(
        'device_tokens',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('fcm_token', sa.String(length=500), nullable=False),
        sa.Column('platform', sa.String(length=10), nullable=False, server_default='android'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.UniqueConstraint('fcm_token', name='uq_device_tokens_fcm_token'),
    )
    op.create_index('ix_device_tokens_user_id', 'device_tokens', ['user_id'])
    op.create_index('ix_device_tokens_fcm_token', 'device_tokens', ['fcm_token'])

    # ── session_reminders ────────────────────────────────────────────
    op.create_table(
        'session_reminders',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('session_id', sa.Integer(), nullable=False),
        sa.Column('lead_time', sa.String(length=10), nullable=False),
        sa.Column('remind_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('sent', sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['session_id'], ['training_sessions.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_session_reminders_user_id', 'session_reminders', ['user_id'])
    op.create_index('ix_session_reminders_session_id', 'session_reminders', ['session_id'])
    op.create_index('ix_session_reminders_remind_at', 'session_reminders', ['remind_at'])
    op.create_index('ix_session_reminders_sent', 'session_reminders', ['sent'])


def downgrade() -> None:
    op.drop_index('ix_session_reminders_sent', table_name='session_reminders')
    op.drop_index('ix_session_reminders_remind_at', table_name='session_reminders')
    op.drop_index('ix_session_reminders_session_id', table_name='session_reminders')
    op.drop_index('ix_session_reminders_user_id', table_name='session_reminders')
    op.drop_table('session_reminders')

    op.drop_index('ix_device_tokens_fcm_token', table_name='device_tokens')
    op.drop_index('ix_device_tokens_user_id', table_name='device_tokens')
    op.drop_table('device_tokens')

    op.drop_index('ix_notifications_is_read', table_name='notifications')
    op.drop_index('ix_notifications_type', table_name='notifications')
    op.drop_index('ix_notifications_recipient_id', table_name='notifications')
    op.drop_table('notifications')
