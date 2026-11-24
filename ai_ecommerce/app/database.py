"""多数据库 ORM 基础设施（SQLAlchemy 2.0，引擎惰性创建）。

- 默认库 default：绑定 settings.DATABASE_URL，走同步驱动
  （postgresql+psycopg / mysql+pymysql / sqlite）。
- 额外库：register_database(name, url) 注册；get_session(name) 按名取会话。
- 惰性：engine 在首次取会话时才创建并缓存——未装驱动 / 未配置时 import 不报错，
  契合"纯净开发环境、依赖按需安装"；真正用库时才需要对应驱动。
- 建表由 Alembic 迁移管理；create_all() 仅显式调用，启动流程不自动建表。
- 分工：utils/connectors 负责"连接能力"，本模块负责 ORM engine/session，两者独立。
"""

from typing import Dict, Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings


class Base(DeclarativeBase):
    """所有 ORM 模型的声明基类（多库共用 metadata，分库靠 __bind_key__ 约定）。"""


# 库名 -> 连接串（注册时写入）；引擎与会话工厂均惰性创建
_DB_URLS: Dict[str, str] = {"default": settings.DATABASE_URL}
_ENGINES: Dict[str, object] = {}
_FACTORIES: Dict[str, sessionmaker] = {}


def _make_engine(url: str):
    """按连接串创建同步引擎；SQLite 需关闭 check_same_thread。"""
    is_sqlite = url.startswith("sqlite")
    return create_engine(
        url,
        connect_args={"check_same_thread": False} if is_sqlite else {},
        pool_pre_ping=True,
        echo=False,
    )


def _get_factory(name: str = "default") -> sessionmaker:
    """按库名取 sessionmaker（惰性创建并缓存）；未知库抛 KeyError。"""
    if name not in _DB_URLS:
        raise KeyError(f"数据库未注册: {name}")
    if name not in _FACTORIES:
        engine = _make_engine(_DB_URLS[name])
        _ENGINES[name] = engine
        _FACTORIES[name] = sessionmaker(
            bind=engine, autoflush=False, autocommit=False, expire_on_commit=False
        )
    return _FACTORIES[name]


def register_database(name: str, url: str) -> None:
    """注册命名数据库（同名覆盖）；仅存连接串，引擎延迟到首次使用时创建。"""
    _DB_URLS[name] = url
    _FACTORIES.pop(name, None)
    _ENGINES.pop(name, None)


def get_session_factory(name: str = "default") -> sessionmaker:
    """按库名取 sessionmaker。"""
    return _get_factory(name)


def get_session(name: str = "default") -> Session:
    """按库名创建一个会话（调用方负责 close，建议用 with）。"""
    return _get_factory(name)()


def get_db() -> Generator[Session, None, None]:
    """FastAPI 依赖：默认库每请求一个会话，用后关闭。"""
    db = _get_factory("default")()
    try:
        yield db
    finally:
        db.close()


def get_engine(name: str = "default"):
    """按库名取引擎（惰性创建），供 Alembic / 原生 SQL 复用。"""
    _get_factory(name)
    return _ENGINES[name]


def create_all() -> None:
    """显式建表（仅开发/测试；生产用 Alembic）。启动流程不自动调用。"""
    import app.models  # noqa: F401  确保模型注册到 metadata

    Base.metadata.create_all(bind=get_engine("default"))
