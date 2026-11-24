"""业务异常体系：业务层抛类型化异常，全局 handler 统一转结构化响应。

code 为业务码，http_status 为 HTTP 状态码。
"""

from typing import Any, Optional


class AppException(Exception):
    """所有业务异常的基类。"""

    code: int = 400
    message: str = "请求错误"
    http_status: int = 400

    def __init__(
        self,
        message: Optional[str] = None,
        code: Optional[int] = None,
        data: Any = None,
    ) -> None:
        if message is not None:
            self.message = message
        if code is not None:
            self.code = code
        self.data = data
        super().__init__(self.message)


# --- 通用业务异常 ---
class NotFoundException(AppException):
    code = 404
    message = "资源不存在"
    http_status = 404


class ValidationException(AppException):
    code = 422
    message = "参数校验失败"
    http_status = 422


class ConflictException(AppException):
    code = 409
    message = "资源冲突"
    http_status = 409


class UnauthorizedException(AppException):
    code = 401
    message = "未授权"
    http_status = 401


class ForbiddenException(AppException):
    code = 403
    message = "禁止访问"
    http_status = 403


class InternalException(AppException):
    code = 500
    message = "服务内部错误"
    http_status = 500


# --- 基础设施 / 外部依赖异常（公共层连接器、认证、幂等使用）---
class ConnectionException(AppException):
    """外部连接不可用（MySQL/PG/Redis/MinIO/Milvus 等）。"""

    code = 503
    message = "服务依赖不可用"
    http_status = 503


class ExternalServiceException(AppException):
    """外部服务调用失败（非连接层，如第三方 API 返回异常）。"""

    code = 502
    message = "外部服务调用失败"
    http_status = 502
