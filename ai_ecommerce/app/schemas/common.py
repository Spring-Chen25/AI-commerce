"""通用响应模型（Pydantic v2 泛型）。"""

from typing import Any, Generic, List, Optional, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class ResponseModel(BaseModel, Generic[T]):
    code: int = 200
    message: str = "success"
    data: Optional[T] = None


class PageData(BaseModel, Generic[T]):
    items: List[T]
    total: int
    page: int
    page_size: int


def ok(data: Any = None, message: str = "success") -> dict:
    """路由里快速构造成功响应（response_model 会再校验一层）。"""
    return {"code": 200, "message": message, "data": data}
