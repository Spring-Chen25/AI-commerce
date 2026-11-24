"""适配器层（utils 子包）。对外统一从这里导入。"""

from app.utils.adapter.base import AdapterRegistry, BaseAdapter, registry

__all__ = ["BaseAdapter", "AdapterRegistry", "registry"]
