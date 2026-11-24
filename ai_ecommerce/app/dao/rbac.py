"""RBAC 数据访问层：只处理租户作用域内的持久化查询。"""

from typing import Any, TypeVar

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.rbac import AuditFields

T = TypeVar("T", bound=AuditFields)


class OrgRepository:
    def __init__(self, db: Session, model: type[T], org_id: int):
        self.db = db
        self.model = model
        self.org_id = org_id

    def list(self) -> list[T]:
        return list(
            self.db.scalars(
                select(self.model)
                .where(self.model.org_id == self.org_id, self.model.deleted.is_(False))
                .order_by(self.model.id)
            ).all()
        )

    def get(self, record_id: int) -> T | None:
        return self.db.scalar(
            select(self.model).where(
                self.model.id == record_id,
                self.model.org_id == self.org_id,
                self.model.deleted.is_(False),
            )
        )

    def create(self, values: dict[str, Any], actor_id: int) -> T:
        record = self.model(org_id=self.org_id, created_by=actor_id, updated_by=actor_id, **values)
        self.db.add(record)
        self.db.flush()
        return record

    def update(self, record: T, values: dict[str, Any], actor_id: int) -> T:
        for key, value in values.items():
            setattr(record, key, value)
        record.updated_by = actor_id
        self.db.flush()
        return record

    def delete(self, record: T, actor_id: int) -> None:
        record.deleted = True
        record.updated_by = actor_id
        self.db.flush()
