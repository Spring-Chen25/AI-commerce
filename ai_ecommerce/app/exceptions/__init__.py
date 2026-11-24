"""类型化异常体系：业务层抛具体异常，由全局 handler 统一转结构化响应。"""

from app.exceptions.base import (
    AppException,
    ConflictException,
    ConnectionException,
    ExternalServiceException,
    ForbiddenException,
    InternalException,
    NotFoundException,
    UnauthorizedException,
    ValidationException,
)

__all__ = [
    "AppException",
    "NotFoundException",
    "ValidationException",
    "ConflictException",
    "UnauthorizedException",
    "ForbiddenException",
    "InternalException",
    "ConnectionException",
    "ExternalServiceException",
]
