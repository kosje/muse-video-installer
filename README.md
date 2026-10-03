# Muse 视频工作台 — kosje 安全安装版

原始安装器：[yys9253462-gif/muse-video-installer](https://github.com/yys9253462-gif/muse-video-installer)。
基于审查提交 `63f6906a17e8fb185d2b711bda9e971645e693ce` 重写部署流程，保留 MIT 许可证。

原版将含 Key/Cookie 的整个安装目录通过 root HTTP 服务公开。本版移除此设计，
网页由 [安全后端](https://github.com/kosje/muse2api/tree/security/private-deployment) 的固定路由提供。

## 安装前

- 专用 Linux 服务器；建议 4 GiB 内存，10 GiB 可用磁盘。
- 自行从官方源安装 Docker Engine **28+** 和 Docker Compose v2、Python 3、git、curl、tar、flock。
- 当前自动化容器测试运行于 linux/amd64；其他架构需额外验证。
- 不执行 `curl | sh`，不自动修改宿主防火墙，也不安装 SSH 或计划任务。
- 必须下载完整仓库；`install.sh` 依赖同版本 `deploy/render.py` 和 `release.json`。

## 私有访问（默认）

```sh
git clone --branch security/private-deployment https://github.com/kosje/muse-video-installer.git
cd muse-video-installer
# 检查所用 commit 和 release.json；正式使用时固定到已验证的发布提交。
cat release.json
bash install.sh --dry-run
sudo bash install.sh
```

本版使用新目录 `/opt/mvw-secure`，不会接管旧版 `/opt/mvw`。
只映射 `127.0.0.1:18610`，**不要为此端口开放公网安全组**。
在自己的电脑执行：

```sh
ssh -N -L 18610:127.0.0.1:18610 用户@服务器
```

浏览器打开 `http://127.0.0.1:18610/`；管理页面为 `/admin`。
工作台现在支持“视频 / 图片”切换，可文生图或上传参考图生图；生成的图片和视频统一显示在管理页面的“生成文件”列表中。
在服务器自己的终端查看密钥：

```sh
sudo bash /opt/mvw-secure/installer/install.sh --credentials
```

- 管理员 Key：登录管理页面或导号工具；不要给普通客户端。
- 生成接口 Key：视频工作台和第三方客户端。
- 密钥默认不写日志、不在 `--status` 中显示、不放进 URL 或网页源码。
- 两把密钥持久化于 `data/auth.json`，轮换后重启和升级仍然有效。
- 导号工具可从管理页面下载，在本机使用同一个 SSH 隧道地址和管理员 Key。

## 域名 HTTPS（可选）

```sh
sudo bash install.sh --domain video.example.com
```

需提前将域名解析到服务器并允许公网 TCP 80/443，且端口没有被其他软件占用。
Caddy 同时代理网页、API、管理和媒体接口，后端仍仅映射到本机。
本版不修改已有 Caddy/Nginx 配置；若 80/443 已占用，请使用私有模式并自行配置现有反代。
安装完成后必须验证域名证书可用，再通过 HTTPS 导入 Cookie。
`--no-domain` 可切回私有模式；已有 TLS 数据保留。

## 升级、回滚和卸载

`release.json` 固定 `kosje/muse2api` 的完整 commit，Caddy 固定 digest。
安装器本身也应从经过审查的 commit 获取；不要盲目跟随分支或覆盖发布清单。

更新为经过审查的新安装器版本后运行 `sudo bash install.sh --upgrade`。
升级先下载/构建固定源码，再停止写入并备份数据，切换配置后检查健康状态。
失败时恢复旧配置和旧镜像；备份保留在安装目录的 `backups/`，请保护其中的明文 Cookie。

```sh
sudo bash /opt/mvw-secure/installer/install.sh --status
sudo bash /opt/mvw-secure/installer/install.sh --rollback
sudo bash /opt/mvw-secure/installer/install.sh --uninstall
```

回滚保留**当前**数据和密钥，不自动恢复备份，防止重新启用已撤销的 Key。
本次版本未引入账号数据格式迁移；未来涉及不兼容数据库变更时需单独迁移方案。
卸载只删除本项目容器，数据、配置、镜像和备份保留，不执行递归删除。
失败的 staging 目录保留用于诊断，管理员可在检查路径后手动清理。

## 从原版迁移

1. 停止旧版网页服务并关闭旧入口。默认是 `sudo systemctl disable --now mvw-web.service`；自定义安装需先核对实际服务名。
2. 原版若曾公网可访问，撤销 muse.ai 旧会话，轮换旧 API Key；修文件权限并不能撤销泄露的 Cookie。
3. 新目录安装安全版，重新登录并导号，不复制旧 `.env`、Key 或账号 Cookie。
4. 必要时停写后仅迁移 `data/media` 中的普通媒体文件，勿复制符号链接；目标文件归属 `10001:10001`，权限 `600`。
5. 验证新站生成流程后，再处理旧服务。安装器不会自动删除或停止你的旧部署。

## 验证与限制

`python3 -m unittest discover -s tests -v` 检查渲染、端口隔离和非法参数。
GitHub Actions 在临时 Linux 主机上测试新装、匿名读取、密钥轮换、升级备份、回滚和保留数据卸载。
后端 CI 还运行 SSRF/鉴权回归和离线 Chromium 测试。

这些测试不会登录你的 muse.ai 账号。部署验收仍需你在自己的浏览器里导入测试账号并生成一次视频。
固定版本不是永久安全保证，需要定期审查安全更新。Chromium 仍以 `--no-sandbox` 在非 root 容器中运行；
请使用专用服务器，不挂载其他业务目录。Debian/Chromium 包来自签名源，未完全锁定 OS 软件包快照。
