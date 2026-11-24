"""平台 API 凭据的静态加密工具，不向接口响应暴露明文。"""

import base64
import hashlib

from app.config import settings


def _fernet():
    from cryptography.fernet import Fernet

    source = settings.CREDENTIAL_ENCRYPTION_KEY or settings.JWT_SECRET_KEY
    key = base64.urlsafe_b64encode(hashlib.sha256(source.encode("utf-8")).digest())
    return Fernet(key)


def encrypt_secret(value: str) -> str:
    return _fernet().encrypt(value.encode("utf-8")).decode("ascii")


def decrypt_secret(value: str) -> str:
    return _fernet().decrypt(value.encode("ascii")).decode("utf-8")
