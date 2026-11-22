# Hermes Devbox

[English](README.en.md)

> [!WARNING]
> 本项目包含 AI 生成的内容，使用前请自行核查。

定制化的 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 环境：基于官方镜像
`nousresearch/hermes-agent:stable`（Debian 13）构建派生镜像，额外提供 Go、Rust、
Blender LTS、GitHub CLI、uv 以及常用系统 / 网络诊断工具，同时完整保留官方的
s6 监管树、`hermes` 运行时用户（UID 10000）与 `/opt/data` 数据目录约定。

官方镜像已自带：Python 3.14、Node.js 26（npm / npx / pnpm）、uv 管理的依赖环境、
Git、ripgrep、FFmpeg、Chromium、tmux、gcc / g++ / make / cmake、Docker CLI。

## 快速开始

```bash
# 首次：构建（或拉取）镜像并运行设置向导，配置 API key / 消息平台
docker compose run --rm hermes setup

# 常驻 gateway（Telegram / Discord / Slack 等，由 s6 监管、崩溃自动重启）
docker compose up -d

# 进入容器
docker compose exec hermes hermes     # 交互式 CLI
docker compose exec hermes bash       # shell（devbox 工具链均可用）
```

所有 Hermes 状态（`.env`、`config.yaml`、SOUL.md、sessions、memories、skills、
cron、logs）都保存在命名卷 `data` 挂载的 `/opt/data` 中，镜像升级不丢数据。
官方强烈建议保持命名卷而非跨 VM 的 bind mount（后者会破坏 SQLite WAL，
参见上游文档 “Filesystem requirements for state.db”）。

> [!IMPORTANT]
> - 不要在 compose 中设置 `init: true` 或覆盖 `entrypoint:`——s6 必须持有 PID 1，
>   否则会失去服务监管与僵尸进程回收。
> - 不要以 root 运行 gateway（官方镜像默认拒绝）。
> - 同一数据目录不要同时跑两个 gateway 容器。

## 可选服务端口

默认不发布任何端口。按需取消 `compose.yaml` 中 environment 与 ports 的注释：

| 端口 | 服务 | 开启条件 |
|---|---|---|
| 8642 | gateway 的 OpenAI 兼容 API server | `API_SERVER_ENABLED=true`，非本机访问必须设置 `API_SERVER_KEY` |
| 9119 | Web dashboard | `HERMES_DASHBOARD=1`，非回环绑定必须配置认证（如 `HERMES_DASHBOARD_BASIC_AUTH_USERNAME/_PASSWORD`） |

可复制 `.env.example` 为 `.env` 管理这些变量。面向公网暴露端口前请先阅读官方
安全文档（2026 年 6 月曾有未认证 dashboard 被扫描利用的案例）。

## 升级

```bash
docker compose build --pull     # 重新构建派生镜像（拉取新的 stable 基础镜像）
docker compose up -d --force-recreate
```

数据卷保持不变；容器启动时会自动执行 config 迁移（迁移前自动备份
`config.yaml` / `.env`）。

## 本地构建

```bash
docker build --pull -t hermes-devbox:local .
HERMES_IMAGE=hermes-devbox:local docker compose up -d --pull never
```

基础镜像可用构建参数固定（含 digest 精确锁定）：

```bash
docker build --build-arg HERMES_IMAGE=nousresearch/hermes-agent:stable -t hermes-devbox:local .
```

## 附加工具

| 工具 | 来源 | 位置 |
|---|---|---|
| Go（最新 stable） | go.dev 官方 JSON API + SHA256 校验 | `/usr/local/go` |
| Rust（stable，rustup） | sh.rustup.rs 官方脚本 | `/opt/rustup`、`/opt/rust-cargo`（全局只读） |
| Blender LTS | download.blender.org 官方 tarball + SHA256 校验 | `/opt/blender` |
| GitHub CLI | cli.github.com 官方 apt 源 | apt |
| uv（最新 stable） | astral.sh 官方安装脚本 | `/usr/local/bin/uv`、`uvx` |
| 网络工具 | Debian apt | ping / traceroute(tracert) / mtr / telnet / dig / nc / tcpdump / iperf3 等 |
| 其他 | Debian apt | gh / jq / vim / nano / htop / btop / nvtop / sudo / build-essential |

定制原则（与上游文档一致）：

- 不覆盖 `/usr/local/bin` 下由官方 PM 管理的符号链接（`python3`、`node`、`npm`、`npx`、`pnpm`、`ffmpeg`、`rg`）。
- 不预装 uv 托管的 CPython，避免覆盖官方 `python3`；需要其他 Python 版本时以运行用户执行 `uv python install <version>`。
- 不修改 `/opt/hermes` 安装树；需要更多系统级工具时改 Dockerfile 重新构建，而不是运行期安装。

## CI

GitHub Actions（`.github/workflows/docker.yml`）在 push / PR / 每周一构建派生镜像，
在容器内验证 Hermes 入口链、devbox 工具链与运行时用户权限后，将镜像推送到
`ghcr.io/<owner>/<repo>`（镜像名自动跟随仓库名）。

## 许可

MIT — 见 [LICENSE](LICENSE)。Hermes Agent 本体为 Nous Research 的 MIT 许可项目，
本项目仅为其派生环境，不修改上游代码。
