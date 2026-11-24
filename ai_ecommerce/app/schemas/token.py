"""认证相关 Pydantic 模型（骨架）。"""

from pydantic import BaseModel


class TokenOut(BaseModel):
    """登录/换取令牌的响应结构。"""

    access_token: str
    token_type: str = "bearer"


class TokenPayload(BaseModel):
    """令牌声明的最小结构。"""

    sub: str
    user_id: str | None = None
