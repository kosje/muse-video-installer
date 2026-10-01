#!/usr/bin/env bash
# Secure personal deployment. Requires Linux, Docker Engine >=28, Compose v2,
# Python 3, curl, git, tar, flock. No downloaded shell installers are executed.
set -Eeuo pipefail
umask 077
SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_DIR=/opt/mvw-secure
PORT=18610
DOMAIN=''
ACTION=install
PORT_SET=0
DOMAIN_SET=0
ACTION_SET=0
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Muse 安全部署（Linux / Docker >=28）
sudo bash install.sh [--dir /opt/mvw-secure] [--api-port 18610] [--domain video.example.com]
默认只开放 127.0.0.1:18610；通过 SSH 隧道访问网页与 API。
--status        查看运行状态，不显示密钥
--credentials   本机管理员查看持久化的两把密钥
--upgrade       安装此脚本附带 release.json 固定的版本
--rollback      恢复上一次部署配置和镜像（保留当前数据及密钥）
--uninstall     停止并删除本项目容器，保留数据、备份和配置
--no-domain     切回本机访问模式
--dry-run       输出计划，不修改系统、不访问网络
--render DIR    在指定目录生成供审查的配置，不安装（CI 使用）
安装依赖请按官方文档操作：https://docs.docker.com/engine/install/
EOF
}
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --dir) [[ $# -ge 2 ]] || die '--dir 缺少参数'; INSTALL_DIR=$2; shift ;;
    --api-port) [[ $# -ge 2 ]] || die '--api-port 缺少参数'; PORT=$2; PORT_SET=1; shift ;;
    --domain) [[ $# -ge 2 ]] || die '--domain 缺少参数'; DOMAIN=$2; DOMAIN_SET=1; shift ;;
    --no-domain) DOMAIN=''; DOMAIN_SET=1 ;;
    --status|--credentials|--upgrade|--rollback|--uninstall|--dry-run|--render)
      [[ $ACTION_SET == 0 ]] || die '操作参数不能同时使用'; ACTION=${1#--}; ACTION_SET=1
      if [[ $ACTION == render ]]; then [[ $# -ge 2 ]] || die '--render 缺少路径'; RENDER_DIR=$2; shift; fi ;;
    --yes|-y) : ;; # no interactive destructive operation; data is never deleted
    *) die "不支持的参数：$1" ;;
  esac
  shift
done
command -v python3 >/dev/null || die '需要 Python 3'
[[ -f "$SELF_DIR/release.json" && -f "$SELF_DIR/deploy/render.py" ]] || die '请下载完整仓库，不能只下载 install.sh'
# No source/eval of state files. Reject symlinked, broad, or shell-sensitive paths.
python3 "$SELF_DIR/deploy/render.py" validate "$INSTALL_DIR" "$PORT" "$DOMAIN"
if [[ $ACTION == dry-run ]]; then
  printf '目录：%s\n本机端口：%s\n域名：%s\n' "$INSTALL_DIR" "$PORT" "${DOMAIN:-无（SSH 隧道）}"
  cat "$SELF_DIR/release.json"
  printf '\n依赖需预装；凭据与账号数据不进入网站目录；升级会备份并检查健康状态。\n'
  exit 0
fi
if [[ $ACTION == render ]]; then
  python3 "$SELF_DIR/deploy/render.py" render "$SELF_DIR/release.json" "$INSTALL_DIR" "$PORT" "$DOMAIN" "$RENDER_DIR"
  exit 0
fi
[[ $(id -u) == 0 ]] || die '此操作需要 sudo'
[[ $(uname -s) == Linux ]] || die '部署目标必须为 Linux'
for tool in docker git curl tar flock; do command -v "$tool" >/dev/null || die "缺少依赖：$tool"; done
docker compose version >/dev/null || die '需要 Docker Compose v2'
docker_version="$(docker version --format '{{.Server.Version}}')"
[[ ${docker_version%%.*} =~ ^[0-9]+$ ]] && (( ${docker_version%%.*} >= 28 )) || die '需要 Docker >=28，确保 localhost 端口隔离'

if [[ -e "$INSTALL_DIR" ]]; then
  [[ -f "$INSTALL_DIR/.mvw-secure" ]] || die '目录不是本安全版创建的；请使用新的专用目录'
  [[ $(stat -c %u "$INSTALL_DIR") == 0 ]] || die '安装目录必须归 root 所有'
else
  [[ $ACTION == install ]] || die '尚未安装'
  install -d -m 700 "$INSTALL_DIR"
  printf 'mvw-secure-v1\n' > "$INSTALL_DIR/.mvw-secure"
fi
exec 9>"$INSTALL_DIR/.lock"
flock -n 9 || die '另一个安装或升级任务正在运行'
PROJECT="mvw-$(printf '%s' "$INSTALL_DIR" | sha256sum | cut -c1-12)"
dc() { docker compose --project-name "$PROJECT" --project-directory "$INSTALL_DIR" -f "$INSTALL_DIR/compose.yml" "$@"; }
if [[ -f "$INSTALL_DIR/deployment.json" ]]; then
  if [[ $PORT_SET == 0 ]]; then PORT="$(python3 "$SELF_DIR/deploy/render.py" get "$INSTALL_DIR/deployment.json" port)"; fi
  if [[ $DOMAIN_SET == 0 ]]; then DOMAIN="$(python3 "$SELF_DIR/deploy/render.py" get "$INSTALL_DIR/deployment.json" domain)"; fi
fi
python3 "$SELF_DIR/deploy/render.py" validate "$INSTALL_DIR" "$PORT" "$DOMAIN"
case "$ACTION" in
  status) dc ps; exit ;;
  credentials) python3 "$SELF_DIR/deploy/render.py" credentials "$INSTALL_DIR/data/auth.json"; exit ;;
  uninstall) dc down --remove-orphans; printf '服务已移除。数据和备份保留在 %s\n' "$INSTALL_DIR"; exit ;;
esac

healthy() {
  local i
  for ((i=0;i<45;i++)); do
    if dc exec -T api python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:18610/readyz',timeout=2)" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}
restore() {
  [[ -f "$INSTALL_DIR/previous/compose.yml" ]] || return 1
  cp "$INSTALL_DIR/previous/compose.yml" "$INSTALL_DIR/compose.yml"
  cp "$INSTALL_DIR/previous/Caddyfile" "$INSTALL_DIR/Caddyfile"
  cp "$INSTALL_DIR/previous/deployment.json" "$INSTALL_DIR/deployment.json"
  dc up -d --no-build --pull never --remove-orphans --force-recreate && healthy
}
if [[ $ACTION == rollback ]]; then restore || die '回滚失败，请检查 docker compose 日志'; printf '已恢复上一次部署，当前账号数据和密钥保留。\n'; exit 0; fi

REF="$(python3 "$SELF_DIR/deploy/render.py" get "$SELF_DIR/release.json" backend_commit)"
REPO="$(python3 "$SELF_DIR/deploy/render.py" get "$SELF_DIR/release.json" backend_repo)"
[[ $REF =~ ^[a-f0-9]{40}$ && $REPO == kosje/muse2api ]] || die '发布清单中的仓库或 commit 无效'
install -d -m 700 "$INSTALL_DIR/releases" "$INSTALL_DIR/backups"
RELEASE="$INSTALL_DIR/releases/$REF"
STAGE="$(mktemp -d "$INSTALL_DIR/releases/staging.XXXXXX")"
# Deliberately preserve failed staging directories for diagnosis; no recursive rm.
trap 'printf "操作失败。数据未删除，诊断目录：%s\n" "${STAGE:-}" >&2' ERR
if [[ ! -d "$RELEASE" ]]; then
  git -c core.hooksPath=/dev/null init -q "$STAGE/repo"
  git -C "$STAGE/repo" -c core.hooksPath=/dev/null fetch -q --depth 1 "https://github.com/$REPO.git" "$REF"
  [[ $(git -C "$STAGE/repo" rev-parse FETCH_HEAD) == "$REF" ]] || die 'Git commit 校验失败'
  mkdir "$STAGE/source"
  git -C "$STAGE/repo" archive FETCH_HEAD | tar -x -C "$STAGE/source"
  mv "$STAGE/source" "$RELEASE"
fi
python3 "$SELF_DIR/deploy/render.py" render "$SELF_DIR/release.json" "$INSTALL_DIR" "$PORT" "$DOMAIN" "$STAGE"
docker compose --project-name "$PROJECT" --project-directory "$INSTALL_DIR" -f "$STAGE/compose.yml" config --quiet
docker compose --project-name "$PROJECT" --project-directory "$INSTALL_DIR" -f "$STAGE/compose.yml" build api
if [[ -n $DOMAIN ]]; then docker compose --project-name "$PROJECT" --project-directory "$INSTALL_DIR" -f "$STAGE/compose.yml" pull proxy; fi

HAD_PREVIOUS=0
ROLLBACK_NEEDED=0
on_failure() {
  local rc=$?
  trap - ERR INT TERM
  if [[ $ROLLBACK_NEEDED == 1 ]]; then
    printf '部署中断，尝试恢复上一个配置。\n' >&2
    restore || printf '自动恢复失败，请检查服务日志。\n' >&2
  fi
  exit "${rc:-1}"
}
trap on_failure ERR
trap 'false' INT TERM
if [[ -f "$INSTALL_DIR/compose.yml" ]]; then
  # Stop writers before backing up JSON data. Keep the old image for rollback.
  install -d -m 700 "$INSTALL_DIR/previous"
  for file in compose.yml Caddyfile deployment.json; do cp "$INSTALL_DIR/$file" "$INSTALL_DIR/previous/$file"; done
  HAD_PREVIOUS=1
  ROLLBACK_NEEDED=1
  dc stop
  backup="$(mktemp "$INSTALL_DIR/backups/data-$(date -u +%Y%m%dT%H%M%S)-XXXXXX.tar.gz")"
  if ! tar -czf "$backup" -C "$INSTALL_DIR" data; then
    restore || true; die '备份失败，已尝试恢复原服务'
  fi
fi
install -d -m 700 -o 10001 -g 10001 "$INSTALL_DIR/data"
if [[ -n $DOMAIN ]]; then
  install -d -m 700 -o 10002 -g 10002 "$INSTALL_DIR/caddy-data" "$INSTALL_DIR/caddy-config"
fi
for file in compose.yml Caddyfile deployment.json; do cp "$STAGE/$file" "$INSTALL_DIR/$file"; done
chmod 644 "$INSTALL_DIR/Caddyfile"
if ! dc up -d --no-build --pull never --remove-orphans --force-recreate || ! healthy; then
  if [[ $HAD_PREVIOUS == 1 ]]; then restore || die '新旧版本都未启动，请检查服务日志'; else dc down --remove-orphans || true; fi
  die '新版未通过健康检查；有旧版时已尝试回滚'
fi
ROLLBACK_NEEDED=0
install -d -m 700 "$INSTALL_DIR/installer/deploy"
if [[ "$SELF_DIR" != "$INSTALL_DIR/installer" ]]; then
  cp "$SELF_DIR/install.sh" "$SELF_DIR/release.json" "$INSTALL_DIR/installer/"
  cp "$SELF_DIR/deploy/render.py" "$INSTALL_DIR/installer/deploy/"
fi
printf '安装完成。密钥不在日志中输出。\n查看密钥：sudo bash %s/installer/install.sh --dir %s --credentials\n' "$INSTALL_DIR" "$INSTALL_DIR"
if [[ -n $DOMAIN ]]; then
  printf '网页：https://%s/\n管理：https://%s/admin\n请确认 DNS、80/443 端口和证书签发正常。\n' "$DOMAIN" "$DOMAIN"
else
  printf '在自己的电脑建立隧道：ssh -N -L %s:127.0.0.1:%s 用户@服务器\n网页：http://127.0.0.1:%s/\n管理：http://127.0.0.1:%s/admin\n' "$PORT" "$PORT" "$PORT" "$PORT"
fi
