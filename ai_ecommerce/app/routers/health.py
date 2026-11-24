"""健康检查类式路由：供负载均衡、容器编排和人工排障使用。"""

from app.routers.base import BaseRouter
from app.schemas.common import ok
from app.utils.connectors import health_all


class HealthRouter(BaseRouter):
    """注册无需认证的服务存活和依赖就绪检查接口。"""

    tags = ["健康检查"]

    def _register_routes(self) -> None:
        """注册健康检查端点及 Swagger 说明。"""
        self.router.get(
            "/health", summary="服务存活探针",
            description="只要 API 进程能够响应即返回成功；不检查外部依赖。", tags=self.tags,
        )(self.health)
        self.router.get(
            "/ready", summary="服务就绪探针",
            description="并发检查已配置的外部连接器；依赖故障以 degraded 状态返回。", tags=self.tags,
        )(self.ready)

    def health(self) -> dict:
        """存活探针：进程正常运行即可返回 `ok`。"""
        return ok({"status": "ok"})

    async def ready(self) -> dict:
        """就绪探针：汇总外部依赖连接状态，不因单项故障直接中断响应。"""
        deps = await health_all()
        overall = "ready" if all(item["status"] != "error" for item in deps.values()) else "degraded"
        return ok({"status": overall, "dependencies": deps})


router = HealthRouter().router
