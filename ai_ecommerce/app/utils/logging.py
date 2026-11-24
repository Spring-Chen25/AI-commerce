"""日志配置：stdout + 按大小轮转的文件（logs/ 目录），级别来自环境变量。

- setup_logging() 在 main.py 启动时调用一次（force=True 幂等）。
- get_logger(name) 供各模块获取 logger。
- 文件未创建时自动建 logs/ 目录；磁盘不可写时降级为仅 stdout。
"""

import logging
import os
import sys
from logging.handlers import RotatingFileHandler

from app.config import settings

_FORMAT = "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"


def setup_logging() -> None:
    """配置根 logger：控制台 + 轮转文件。"""
    root = logging.getLogger()
    root.setLevel(getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO))
    root.handlers.clear()

    formatter = logging.Formatter(_FORMAT)

    # 控制台
    console = logging.StreamHandler(sys.stdout)
    console.setFormatter(formatter)
    root.addHandler(console)

    # 文件（按大小轮转）；目录不可写时降级为仅控制台
    try:
        os.makedirs(settings.LOG_DIR, exist_ok=True)
        file_handler = RotatingFileHandler(
            os.path.join(settings.LOG_DIR, "app.log"),
            maxBytes=settings.LOG_MAX_BYTES,
            backupCount=settings.LOG_BACKUP_COUNT,
            encoding="utf-8",
        )
        file_handler.setFormatter(formatter)
        root.addHandler(file_handler)
    except OSError as exc:
        root.warning("日志文件不可写，降级为仅控制台输出: %s", exc)


def get_logger(name: str) -> logging.Logger:
    """获取模块级 logger。"""
    return logging.getLogger(name)
