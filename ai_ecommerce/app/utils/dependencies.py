"""公共依赖注入（骨架）：当前用户解析。

- get_current_user：从 Authorization: Bearer <token> 解析 JWT。
- 不在全局注册；业务路由按需 `Depends(get_current_user)`。
- 返回 payload dict；接真实用户体系时在 load_user 里扩展。
"""

from typing import Any, Dict

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.exceptions import UnauthorizedException
from app.utils.security import decode_access_token

_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> Dict[str, Any]:
    """解析 Bearer token 返回用户声明；缺失或无效抛 401。"""
    if credentials is None or not credentials.credentials:
        raise UnauthorizedException("缺少认证令牌")
    payload = decode_access_token(credentials.credentials)
    subject = payload.get("sub")
    if not subject:
        raise UnauthorizedException("令牌缺少 sub 声明")
    payload["user_id"] = subject
    return payload
