"""v8: add training sessions/exercise logs and AI coach conversations/messages

Adds:
  - training_sessions (user_id -> users.id; optional sport_id, gym_id,
    sparring_request_id anchors)
  - training_exercise_logs (session_id -> training_sessions.id, optional
    exercise_id -> exercises.id; includes a nullable analysis_job_id
    forward-compat hook for a future CV/pose-analysis microservice)
  - ai_coach_conversations (user_id -> users.id)
  - ai_coach_messages (conversation_id -> ai_coach_conversations.id,
    role as VARCHAR — same convention as SparringRequest.status)

No ALTER on existing tables here, so no batch_alter_table is needed —
these are all new tables.

Revision ID: c4f8a2b6d1e3
Revises: 9f4d2c7e1a8b
Create Date: 2026-09-04 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c4f8a2b6d1e3'
down_revision: Union[str, None] = '9f4d2c7e1a8b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── training_sessions ──────────────────────────────────────────────
    op.create_table(
        'training_sessions',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('sport_id', sa.Integer(), nullable=True),
        sa.Column('session_type', sa.String(length=30), nullable=False),
        sa.Column('duration_minutes', sa.Integer(), nullable=False),
        sa.Column('intensity', sa.Integer(), nullable=True),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('session_date', sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column('gym_id', sa.Integer(), nullable=True),
        sa.Column('sparring_request_id', sa.Integer(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['sport_id'], ['sports.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['gym_id'], ['gyms.id'], ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['sparring_request_id'], ['sparring_requests.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_training_sessions_user_id', 'training_sessions', ['user_id'])
    op.create_index('ix_training_sessions_sport_id', 'training_sessions', ['sport_id'])
    op.create_index('ix_training_sessions_session_type', 'training_sessions', ['session_type'])
    op.create_index('ix_training_sessions_gym_id', 'training_sessions', ['gym_id'])
    op.create_index('ix_training_sessions_sparring_request_id', 'training_sessions', ['sparring_request_id'])

    # ── training_exercise_logs ──────────────────────────────────────────
    op.create_table(
        'training_exercise_logs',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('session_id', sa.Integer(), nullable=False),
        sa.Column('exercise_id', sa.Integer(), nullable=True),
        sa.Column('sets', sa.Integer(), nullable=True),
        sa.Column('reps', sa.Integer(), nullable=True),
        sa.Column('weight_kg', sa.Float(), nullable=True),
        sa.Column('duration_seconds', sa.Integer(), nullable=True),
        sa.Column('order_index', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('notes', sa.Text(), nullable=True),
        sa.Column('analysis_job_id', sa.String(length=100), nullable=True),
        sa.ForeignKeyConstraint(['session_id'], ['training_sessions.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['exercise_id'], ['exercises.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_training_exercise_logs_session_id', 'training_exercise_logs', ['session_id'])
    op.create_index('ix_training_exercise_logs_exercise_id', 'training_exercise_logs', ['exercise_id'])
    op.create_index('ix_training_exercise_logs_analysis_job_id', 'training_exercise_logs', ['analysis_job_id'])

    # ── ai_coach_conversations ──────────────────────────────────────────
    op.create_table(
        'ai_coach_conversations',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('title', sa.String(length=150), nullable=False, server_default='محادثة جديدة'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_ai_coach_conversations_user_id', 'ai_coach_conversations', ['user_id'])

    # ── ai_coach_messages ────────────────────────────────────────────────
    op.create_table(
        'ai_coach_messages',
        sa.Column('id', sa.Integer(), primary_key=True, index=True),
        sa.Column('conversation_id', sa.Integer(), nullable=False),
        sa.Column('role', sa.String(length=10), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.ForeignKeyConstraint(['conversation_id'], ['ai_coach_conversations.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_ai_coach_messages_conversation_id', 'ai_coach_messages', ['conversation_id'])
    op.create_index('ix_ai_coach_messages_role', 'ai_coach_messages', ['role'])


def downgrade() -> None:
    op.drop_index('ix_ai_coach_messages_role', table_name='ai_coach_messages')
    op.drop_index('ix_ai_coach_messages_conversation_id', table_name='ai_coach_messages')
    op.drop_table('ai_coach_messages')

    op.drop_index('ix_ai_coach_conversations_user_id', table_name='ai_coach_conversations')
    op.drop_table('ai_coach_conversations')

    op.drop_index('ix_training_exercise_logs_analysis_job_id', table_name='training_exercise_logs')
    op.drop_index('ix_training_exercise_logs_exercise_id', table_name='training_exercise_logs')
    op.drop_index('ix_training_exercise_logs_session_id', table_name='training_exercise_logs')
    op.drop_table('training_exercise_logs')

    op.drop_index('ix_training_sessions_sparring_request_id', table_name='training_sessions')
    op.drop_index('ix_training_sessions_gym_id', table_name='training_sessions')
    op.drop_index('ix_training_sessions_session_type', table_name='training_sessions')
    op.drop_index('ix_training_sessions_sport_id', table_name='training_sessions')
    op.drop_index('ix_training_sessions_user_id', table_name='training_sessions')
    op.drop_table('training_sessions')
