from datetime import datetime, timezone
from typing import List, Optional

from sqlalchemy import select, and_, or_, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.story import Story, StoryView, Highlight, HighlightStory
from app.repositories.base_repository import BaseRepository


def _now():
    return datetime.now(timezone.utc)


class StoryRepository(BaseRepository[Story]):

    def __init__(self, db: AsyncSession):
        super().__init__(Story, db)

    async def create_story(
        self,
        author_id: int,
        content_type: str,
        media_url: Optional[str],
        text_content: Optional[str],
        background_color: Optional[str],
        visibility: str,
    ) -> Story:
        story = Story(
            author_id=author_id,
            content_type=content_type,
            media_url=media_url,
            text_content=text_content,
            background_color=background_color,
            visibility=visibility,
        )
        self.db.add(story)
        await self.db.flush()
        await self.db.refresh(story)
        return story

    async def get_active_by_id(self, story_id: int) -> Optional[Story]:
        """Active = not expired. Callers who need to see an expired story
        anyway (e.g. via a Highlight) should use get_by_id (inherited)."""
        result = await self.db.execute(
            select(Story)
            .options(selectinload(Story.author))
            .where(Story.id == story_id, Story.expires_at > _now())
        )
        return result.scalar_one_or_none()

    async def get_active_feed(
        self, viewer_id: int, following_ids: List[int], skip: int = 0, limit: int = 50
    ) -> List[Story]:
        """
        Active stories visible to `viewer_id`:
          - not expired
          - AND (public) OR (followers-only AND author is followed) OR (author is me)
        `following_ids` should NOT include viewer_id (handled explicitly below,
        mirroring the caller-builds-the-list convention used in posts.py's
        get_feed, but kept independent here since Stories' visibility rule is
        author-scoped, not "any post from anyone I follow").
        """
        result = await self.db.execute(
            select(Story)
            .options(selectinload(Story.author), selectinload(Story.views))
            .where(
                Story.expires_at > _now(),
                or_(
                    Story.author_id == viewer_id,
                    Story.visibility == "public",
                    and_(Story.visibility == "followers", Story.author_id.in_(following_ids or [-1])),
                ),
            )
            .order_by(Story.created_at.desc())
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def record_view(self, story_id: int, viewer_id: int) -> bool:
        """Insert a StoryView if one doesn't already exist. Returns True if
        this call newly recorded a view, False if already viewed."""
        existing = await self.db.execute(
            select(StoryView).where(
                and_(StoryView.story_id == story_id, StoryView.viewer_id == viewer_id)
            )
        )
        if existing.scalar_one_or_none():
            return False
        self.db.add(StoryView(story_id=story_id, viewer_id=viewer_id))
        await self.db.flush()
        return True

    async def get_views_count(self, story_id: int) -> int:
        result = await self.db.execute(
            select(func.count()).select_from(StoryView).where(StoryView.story_id == story_id)
        )
        return result.scalar_one()

    async def viewed_by(self, story_id: int, viewer_id: int) -> bool:
        result = await self.db.execute(
            select(StoryView.id).where(
                and_(StoryView.story_id == story_id, StoryView.viewer_id == viewer_id)
            )
        )
        return result.scalar_one_or_none() is not None

    async def get_viewers(self, story_id: int) -> List[StoryView]:
        result = await self.db.execute(
            select(StoryView)
            .options(selectinload(StoryView.viewer))
            .where(StoryView.story_id == story_id)
            .order_by(StoryView.viewed_at.desc())
        )
        return list(result.scalars().all())

    async def delete_story(self, story_id: int) -> bool:
        """
        Deliberately does NOT use BaseRepository.delete() (a bulk core
        DELETE), because that bypasses SQLAlchemy's ORM-level cascades —
        and on SQLite, `ondelete="CASCADE"` FK options are only enforced
        if `PRAGMA foreign_keys=ON` has been set on the connection, which
        this project does not currently do (see app/core/database.py).
        Loading the Story with its `highlight_entries`/`views`
        relationships and calling `session.delete()` makes SQLAlchemy
        itself cascade the child deletes in Python, so "deleting a story
        removes it from any Highlights" (confirmed v9 decision) holds on
        SQLite in tests exactly as it will on PostgreSQL in production.
        """
        result = await self.db.execute(
            select(Story)
            .options(selectinload(Story.highlight_entries), selectinload(Story.views))
            .where(Story.id == story_id)
        )
        story = result.scalar_one_or_none()
        if not story:
            return False
        await self.db.delete(story)
        await self.db.flush()
        return True


class HighlightRepository(BaseRepository[Highlight]):

    def __init__(self, db: AsyncSession):
        super().__init__(Highlight, db)

    async def create_with_stories(
        self, user_id: int, title: str, story_ids: Optional[List[int]]
    ) -> Highlight:
        highlight = Highlight(user_id=user_id, title=title)
        self.db.add(highlight)
        await self.db.flush()

        for idx, sid in enumerate(story_ids or []):
            self.db.add(HighlightStory(highlight_id=highlight.id, story_id=sid, order_index=idx))

        await self.db.flush()
        await self.db.refresh(highlight)
        return highlight

    async def get_user_highlights(self, user_id: int) -> List[Highlight]:
        result = await self.db.execute(
            select(Highlight)
            .options(
                selectinload(Highlight.items).selectinload(HighlightStory.story).selectinload(Story.author)
            )
            .where(Highlight.user_id == user_id)
            .order_by(Highlight.created_at.desc())
        )
        return list(result.scalars().all())

    async def get_with_stories(self, highlight_id: int) -> Optional[Highlight]:
        result = await self.db.execute(
            select(Highlight)
            .options(
                selectinload(Highlight.items).selectinload(HighlightStory.story).selectinload(Story.author)
            )
            .where(Highlight.id == highlight_id)
        )
        return result.scalar_one_or_none()

    async def add_stories(self, highlight_id: int, story_ids: List[int]) -> None:
        # Skip any story already pinned (unique constraint would otherwise raise)
        existing = await self.db.execute(
            select(HighlightStory.story_id).where(HighlightStory.highlight_id == highlight_id)
        )
        already = {row[0] for row in existing.all()}

        count_result = await self.db.execute(
            select(func.count()).select_from(HighlightStory).where(HighlightStory.highlight_id == highlight_id)
        )
        next_index = count_result.scalar_one()

        for sid in story_ids:
            if sid in already:
                continue
            self.db.add(HighlightStory(highlight_id=highlight_id, story_id=sid, order_index=next_index))
            next_index += 1
        await self.db.flush()

    async def remove_story(self, highlight_id: int, story_id: int) -> bool:
        result = await self.db.execute(
            select(HighlightStory).where(
                and_(HighlightStory.highlight_id == highlight_id, HighlightStory.story_id == story_id)
            )
        )
        item = result.scalar_one_or_none()
        if not item:
            return False
        await self.db.delete(item)
        return True

    async def delete_highlight(self, highlight_id: int) -> bool:
        """Explicit ORM-level delete (loads `items` first) so the junction
        rows are cleaned up via cascade regardless of SQLite FK pragma
        support — same reasoning as StoryRepository.delete_story."""
        result = await self.db.execute(
            select(Highlight)
            .options(selectinload(Highlight.items))
            .where(Highlight.id == highlight_id)
        )
        highlight = result.scalar_one_or_none()
        if not highlight:
            return False
        await self.db.delete(highlight)
        await self.db.flush()
        return True
