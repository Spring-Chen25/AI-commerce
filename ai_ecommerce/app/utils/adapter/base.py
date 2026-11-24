"""适配器统一契约：把外部系统（第三方 API / 存储 / 协议）的差异收敛到实现内部。

业务层只依赖 BaseAdapter 抽象，不感知具体厂商；新增渠道 = 新增一个实现类 + 注册。
"""

from abc import ABC, abstractmethod
from typing import Any, Dict


class BaseAdapter(ABC):
    name: str = "base"

    @abstractmethod
    def call(self, action: str, **kwargs: Any) -> Any:
        """执行适配动作，由子类实现具体协议。"""
        raise NotImplementedError

    def health(self) -> Dict[str, Any]:
        """可选：适配器健康检查，子类可覆盖。"""
        return {"adapter": self.name, "status": "ok"}


class AdapterRegistry:
    """适配器注册表：按名称管理所有适配器实例。"""

    def __init__(self) -> None:
        self._adapters: Dict[str, BaseAdapter] = {}

    def register(self, adapter: BaseAdapter) -> None:
        self._adapters[adapter.name] = adapter

    def get(self, name: str) -> BaseAdapter:
        try:
            return self._adapters[name]
        except KeyError:
            raise KeyError(f"适配器未注册: {name}")

    def all(self) -> Dict[str, BaseAdapter]:
        return dict(self._adapters)


registry = AdapterRegistry()
