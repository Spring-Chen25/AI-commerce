"""类式路由的基础设施。

每个业务路由继承 :class:`BaseRouter`，在 ``_register_routes`` 内集中声明
HTTP 方法、路径、状态码和 Swagger 元数据。这样 ``main.py`` 只关心路由注册，
而一个业务模块的接口定义与处理函数会聚合在同一个类中。
"""

from abc import ABC, abstractmethod

from fastapi import APIRouter


class BaseRouter(ABC):
    """所有类式业务路由的抽象基类。"""

    tags: list[str] = []

    def __init__(self) -> None:
        self.router = APIRouter(tags=self.tags)
        self._register_routes()

    @abstractmethod
    def _register_routes(self) -> None:
        """注册当前模块的全部接口及其 OpenAPI/Swagger 元数据。"""

