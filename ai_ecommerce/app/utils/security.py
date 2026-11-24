"""JWT 令牌工具（骨架）：签发与解析 access token。

- 依赖 PyJWT：延迟导入，未安装时调用才报错，不影响应用启动。
- 仅提供能力，不全局挂载；路由按需用 get_current_user 依赖。
"""

from datetime import datetime, timedelta, timezone
from typing import Any, Dict

# 明确从 PyJWT 的公开 API 导入，避免运行期动态导入到同名第三方 ``jwt`` 包时，
# 在登录成功后才因缺少 encode/decode 而返回 500。
from jwt import ExpiredSignatureError, InvalidTokenError, decode as jwt_decode, encode as jwt_encode

from app.config import settings


def hash_password(password: str) -> str:
    """使用 Argon2id 保存口令摘要，绝不保存明文。"""
    from argon2 import PasswordHasher

    return PasswordHasher().hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    """校验口令摘要；摘要格式错误同样视为校验失败。"""
    from argon2 import PasswordHasher
    from argon2.exceptions import InvalidHashError, VerificationError

    try:
        return PasswordHasher().verify(password_hash, password)
    except (InvalidHashError, VerificationError):
        return False


def create_access_token(
    subject: str, extras: Dict[str, Any] | None = None
) -> str:
    """签发令牌：sub + 自定义声明 + iat/exp。"""
    now = datetime.now(timezone.utc)
    payload: Dict[str, Any] = {
        "sub": subject,
        "iat": now,
        "exp": now + timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES),
    }
    if extras:
        payload.update(extras)
    return jwt_encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> Dict[str, Any]:
    """解析并校验令牌；失败抛 UnauthorizedException。"""
    from app.exceptions import UnauthorizedException

    try:
        return jwt_decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
    except ExpiredSignatureError:
        raise UnauthorizedException("令牌已过期")
    except InvalidTokenError:
        raise UnauthorizedException("令牌无效")
