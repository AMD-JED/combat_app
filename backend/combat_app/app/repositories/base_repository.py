from typing import Generic, TypeVar, Type, Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update, delete
from app.core.database import Base

ModelType = TypeVar("ModelType", bound=Base)


class BaseRepository(Generic[ModelType]):
    """
    Generic repository implementing common CRUD operations.
    All specific repositories extend this class.
    """

    def __init__(self, model: Type[ModelType], db: AsyncSession):
        self.model = model
        self.db = db

    async def get_by_id(self, id: int) -> Optional[ModelType]:
        result = await self.db.execute(select(self.model).where(self.model.id == id))
        return result.scalar_one_or_none()

    async def get_all(self, skip: int = 0, limit: int = 20) -> List[ModelType]:
        result = await self.db.execute(select(self.model).offset(skip).limit(limit))
        return list(result.scalars().all())

    async def create(self, obj: ModelType) -> ModelType:
        self.db.add(obj)
        await self.db.flush()
        await self.db.refresh(obj)
        return obj

    async def update(self, id: int, data: dict) -> Optional[ModelType]:
        await self.db.execute(
            update(self.model).where(self.model.id == id).values(**data)
        )
        return await self.get_by_id(id)

    async def delete(self, id: int) -> bool:
        result = await self.db.execute(
            delete(self.model).where(self.model.id == id)
        )
        return result.rowcount > 0

    async def count(self) -> int:
        from sqlalchemy import func
        result = await self.db.execute(select(func.count()).select_from(self.model))
        return result.scalar_one()
