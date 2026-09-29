#!/usr/bin/env bash
# muse-video 安装脚本 —— 回归测试套件
# 用法：bash test-install.sh
# 退出码 = 失败数

set -uo pipefail

INSTALLER="${INSTALLER:-/root/install-muse-video.sh}"
TDIR="/opt/muse-regress"
APIP=28710
WEBP=28711
PASS=0
FAIL=0

G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[0;33m'; B=$'\033[1m'; O=$'\033[0m'

t_ok()   { PASS=$((PASS+1)); printf '  %s✓%s %s\n' "$G" "$O" "$1"; }
t_fail() { FAIL=$((FAIL+1)); printf '  %s×%s %s\n' "$R" "$O" "$1"; [ $# -gt 1 ] && printf '      证据：%s\n' "$2"; }
t_case() { printf '\n%s▸ %s%s\n' "$B" "$1" "$O"; }

cleanup_all() {
  # ⚠️ 只操作本测试自己创建的对象（名字都带 muse-regress / muse-conflict 前缀），
  # 绝不用 muse-* 通配 —— 曾因此误删正式的 muse-video-web.service。
  cd "$TDIR" 2>/dev/null && docker compose down --remove-orphans >/dev/null 2>&1
  docker rm -f muse-regress muse-regress-caddy >/dev/null 2>&1
  systemctl disable --now muse-regress-web.service >/dev/null 2>&1
  rm -f /etc/systemd/system/muse-regress-web.service
  rm -f /etc/systemd/system/muse-conflict-name-web.service
  systemctl daemon-reload >/dev/null 2>&1
  rm -rf "$TDIR" /opt/muse-conflict /opt/muse-conflict-name
}

# ─────────────────────────────────────────────
t_case "1. 语法与静态检查"
if bash -n "$INSTALLER" 2>/dev/null; then t_ok "bash -n 通过"; else t_fail "bash -n 失败"; fi
if [ "$(tr -dc '\r' < "$INSTALLER" | wc -c)" = "0" ]; then t_ok "换行符是 LF"; else t_fail "含 CRLF"; fi

t_case "2. 帮助与参数校验"
# 先落盘再 grep，规避 set -o pipefail + grep -q 的 SIGPIPE 误判
bash "$INSTALLER" --help >/tmp/h.log 2>&1
grep -q -- "--api-port" /tmp/h.log && t_ok "--help 正常" || t_fail "--help 异常"
O1="$(bash "$INSTALLER" --api-port abc 2>&1)"; case "$O1" in *abc*) t_ok "非数字端口被拦" ;; *) t_fail "非数字端口未拦" "$O1" ;; esac
O2="$(bash "$INSTALLER" --web-port 80 2>&1)"; case "$O2" in *1024*) t_ok "越界端口被拦" ;; *) t_fail "越界端口未拦" "$O2" ;; esac
O3="$(bash "$INSTALLER" --nonsense 2>&1)"; case "$O3" in *nonsense*) t_ok "未知参数被拦" ;; *) t_fail "未知参数未拦" "$O3" ;; esac

t_case "2b. 缺值参数（小白最容易手滑）"
# 这 4 条曾经**不报错就继续装**，会误装到默认目录 —— 必须拦住
for _opt in --dir --api-port --web-port --domain; do
  _out="$(bash "$INSTALLER" "$_opt" 2>&1)"; _rc=$?
  if [ "$_rc" != 0 ] && printf '%s' "$_out" | grep -q "后面要跟"; then
    t_ok "$_opt 缺值被拦"
  else
    t_fail "$_opt 缺值未拦" "退出码=$_rc"
  fi
done
# 等号形式
_out="$(bash "$INSTALLER" --dir= 2>&1)"; _rc=$?
[ "$_rc" != 0 ] && t_ok "--dir= 空值被拦" || t_fail "--dir= 空值未拦"
# 缺值时必须不产生任何目录
# 缺值时必须不产生任何目录（默认目录已改为 /opt/mvw，避免与既有服务撞名）
if [ ! -d /opt/mvw ] && [ ! -d /opt/muse-video ]; then
  t_ok "缺值未误装默认目录"
else
  t_fail "缺值误装了默认目录"
fi

t_case "2c. 参数冲突检查"
# 注意：这些 case 的输出只用「是否匹配」来判断，绝不把输出塞进 t_ok 的参数，
# 否则错误文案会被当成成功描述打印，污染整份测试报告。
bash "$INSTALLER" --status --uninstall >/tmp/c1.log 2>&1
if grep -qE "只能给一个|一次只能" /tmp/c1.log; then t_ok "互斥子命令被拦"; else t_fail "互斥子命令未拦" "$(tail -2 /tmp/c1.log | tr '\n' ' ')"; fi
bash "$INSTALLER" --api-port 9000 --web-port 9000 >/tmp/c2.log 2>&1
if grep -q "不能是同一个" /tmp/c2.log; then t_ok "端口撞车被拦"; else t_fail "端口撞车未拦" "$(tail -2 /tmp/c2.log | tr '\n' ' ')"; fi

t_case "3. dry-run 无副作用"
rm -rf "$TDIR"
bash "$INSTALLER" --dry-run --yes --dir "$TDIR" --api-port $APIP --web-port $WEBP >/tmp/dr.log 2>&1
if [ ! -d "$TDIR" ]; then t_ok "dry-run 未创建目录"; else t_fail "dry-run 创建了目录"; fi
grep -q "dry-run" /tmp/dr.log && t_ok "dry-run 有输出" || t_fail "dry-run 无输出"
# dry-run 输出里不该有未替换的占位符
# 只检查真正的路径类占位符；密钥占位符 <自动生成的随机密钥> 是 dry-run 的设计
if grep -qE '<本机>|<端口>|<你的|<域名>' /tmp/dr.log; then
  t_fail "dry-run 输出含未替换占位符" "$(grep -oE '<[^>]*>' /tmp/dr.log | sort -u | head -3 | tr '\n' ' ')"
else t_ok "无未替换占位符（密钥占位符属预期）"; fi
# dry-run 也要检查安装目录可写性
# ⚠️ 不能写 `cmd | grep -q X && ...`：脚本头有 set -o pipefail，
#    而 grep -q 一命中就退出，会给左边进程发 SIGPIPE（退出码 141），
#    导致整条管道返回 141，把「匹配成功」误判成失败。
#    正解：先落盘，再对文件 grep。
bash "$INSTALLER" --dry-run --yes --dir "$TDIR" >/tmp/dr2.log 2>&1
grep -q "安装目录" /tmp/dr2.log \
  && t_ok "dry-run 检查了安装目录" || t_fail "dry-run 未检查安装目录" "$(grep -c . /tmp/dr2.log)"

t_case "4. 真实安装"
cleanup_all
bash "$INSTALLER" --yes --dir "$TDIR" --api-port $APIP --web-port $WEBP >/tmp/inst.log 2>&1
RC=$?
[ "$RC" = 0 ] && t_ok "安装退出码 0" || t_fail "安装退出码 $RC" "$(tail -5 /tmp/inst.log)"
if grep -q "No such file or directory" /tmp/inst.log; then
  t_fail "安装中有 No such file 报错" "$(grep -m1 'No such file' /tmp/inst.log)"
else t_ok "无文件路径报错"; fi

t_case "5. 安装结果核验"
docker inspect muse-regress --format '{{.State.Status}}' 2>/dev/null | grep -q running \
  && t_ok "容器 running" || t_fail "容器未运行"
# 判据：容器内能拿到任意 HTTP 状态码即算活（401 说明服务在跑、只是缺 Key）
Alive=0; Code=""
for i in 1 2 3 4 5 6 7 8; do
  Code="$(docker exec muse-regress curl -s -o /dev/null -w '%{http_code}' \
    --max-time 6 "http://127.0.0.1:${APIP}/v1/models" 2>/dev/null)"
  case "$Code" in ''|000) sleep 5 ;; *) Alive=1; break ;; esac
done
if [ "$Alive" = 1 ]; then
  t_ok "接口自检通过（容器内 HTTP $Code）"
else
  t_fail "接口自检失败（拿不到 HTTP 响应）" "$(docker logs muse-regress --tail 3 2>&1 | tr '\n' ' ')"
fi
systemctl is-active muse-regress-web.service >/dev/null 2>&1 \
  && t_ok "网页服务 active" || t_fail "网页服务未运行"
# 判据：先拿到 HTTP 状态码（200 即通），再看内容；不依赖 grep 管道退出码
WCode="$(curl -s -o /tmp/mv-web.html -w '%{http_code}' --max-time 8 "http://127.0.0.1:${WEBP}/" 2>/dev/null)"
if [ "$WCode" = "200" ]; then
  t_ok "网页返回 HTTP 200"
  if grep -q "生成视频" /tmp/mv-web.html 2>/dev/null; then
    t_ok "网页内容包含关键功能文案"
  else
    t_fail "网页内容不含预期文案" "$(head -c 120 /tmp/mv-web.html 2>/dev/null | tr '\n' ' ')"
  fi
else
  t_fail "网页打不开（HTTP ${WCode:-无响应}）" "$(systemctl status muse-regress-web.service --no-pager 2>&1 | head -3 | tr '\n' ' ')"
fi
rm -f /tmp/mv-web.html
[ -f "$TDIR/install.conf" ] && t_ok "状态文件已生成" || t_fail "状态文件缺失"
grep -qE "^SCRIPT_VERSION=1\.0\.0$" "$TDIR/install.conf" 2>/dev/null \
  && t_ok "状态文件版本号正确（未被 os-release 污染）" \
  || t_fail "状态文件版本号异常" "$(grep SCRIPT_VERSION "$TDIR/install.conf" 2>/dev/null)"

# ── API Key 的三道硬检查（这三条曾全部失守，是真事故级 bug）──
K="$(sed -n 's/^API_KEY=//p' "$TDIR/install.conf" 2>/dev/null | head -1)"
KC="$(grep -oP 'MUSE2API_KEY=\K.*' "$TDIR/docker-compose.yml" 2>/dev/null | head -1)"
# ① 必须记进状态文件（否则小白关掉窗口就找不回 Key）
[ -n "$K" ] && t_ok "API Key 已记入状态文件" || t_fail "API Key 没记进状态文件"
# ② 必须是真随机（上游 compose 里有个 m2a_change_me_to... 占位符，
#    曾经的实现会把它的前缀 m2a_change 误当成"上次的 Key"复用）
case "$K" in
  ""|m2a_change|m2a_change_me_to_your_secure_key|m2a_your_secret_admin_key_here)
    t_fail "API Key 是占位符，不是真随机钥匙！" "$K" ;;
  m2a_*)
    [ "${#K}" -ge 36 ] && t_ok "API Key 是真随机（${#K} 位）" || t_fail "API Key 长度可疑" "$K" ;;
  *) t_fail "API Key 格式异常" "$K" ;;
esac
# ③ 状态文件与 compose 必须一致（否则 status 显示的 Key 调不通）
[ "$K" = "$KC" ] && t_ok "状态文件与 compose 的 Key 一致" || t_fail "两处 Key 不一致" "conf=$K compose=$KC"

t_case "6. --status"
OUT="$(bash "$INSTALLER" --status --dir "$TDIR" 2>&1)"
printf '%s' "$OUT" | grep -q "运行中" && t_ok "--status 报运行中" || t_fail "--status 异常" "$(printf '%s' "$OUT" | head -3)"
# --status 必须能把地址和 Key 打回来（小白找回凭据的唯一途径）
printf '%s' "$OUT" | grep -q "连接信息" && t_ok "--status 有「连接信息」段" || t_fail "--status 缺连接信息"
printf '%s' "$OUT" | grep -q "API Key：" && t_ok "--status 能显示 API Key" || t_fail "--status 不显示 Key"
printf '%s' "$OUT" | grep -q "$K" && t_ok "--status 显示的 Key 与状态文件一致" || t_fail "--status 的 Key 不对"
printf '%s' "$OUT" | grep -q "账号池是空的" && t_ok "--status 提示了账号池为空" || t_fail "--status 未提示空账号池"

t_case "7. 幂等重跑（沿用配置）"
bash "$INSTALLER" --yes --dir "$TDIR" >/tmp/re.log 2>&1
RC7=$?
[ "$RC7" = 0 ] && t_ok "重跑退出码 0（不会因自己占端口而失败）" || t_fail "重跑退出码 $RC7" "$(tail -3 /tmp/re.log | tr '\n' ' ')"
if grep -q "${APIP}" /tmp/re.log; then t_ok "重跑沿用上次端口"; else t_fail "重跑丢了端口配置" "$(grep -c . /tmp/re.log)"; fi
# 关键：重跑不得换 Key
K2="$(sed -n 's/^API_KEY=//p' "$TDIR/install.conf" 2>/dev/null | head -1)"
[ "$K2" = "$K" ] && t_ok "重跑保持 API Key（客户端不用重配）" || t_fail "重跑换了 Key" "$K -> $K2"
grep -q "沿用上次的密钥" /tmp/re.log && t_ok "输出里说明了「沿用上次的密钥」" || t_fail "没提示沿用密钥"
docker inspect muse-regress --format '{{.State.Status}}' 2>/dev/null | grep -q running \
  && t_ok "重跑后容器仍健康" || t_fail "重跑后容器异常"

t_case "7b. 命名冲突保护（不覆盖别人的服务/容器）"
# 造一个「别人的」unit，名字正好等于我们要派生的那个（/opt/muse-conflict-name → muse-conflict-name-web.service）
FAKE_UNIT="/etc/systemd/system/muse-conflict-name-web.service"
cat > "$FAKE_UNIT" <<'UEOF'
[Unit]
Description=someone else's service
[Service]
ExecStart=/bin/true
UEOF
systemctl daemon-reload >/dev/null 2>&1
bash "$INSTALLER" --yes --dir /opt/muse-conflict-name --api-port 28731 --web-port 28732 >/tmp/nc.log 2>&1
RC_NC=$?
if [ "$RC_NC" != 0 ] && grep -q "冲突" /tmp/nc.log; then
  t_ok "检测到别人的同名服务并拒绝覆盖"
else
  t_fail "没拦住同名服务冲突" "退出码=$RC_NC $(tail -2 /tmp/nc.log | tr '\n' ' ')"
fi
# 别人的 unit 必须原样还在
grep -q "someone else's service" "$FAKE_UNIT" 2>/dev/null \
  && t_ok "别人的 unit 未被改动" || t_fail "别人的 unit 被覆盖了！"
rm -f "$FAKE_UNIT"; systemctl daemon-reload >/dev/null 2>&1
rm -rf /opt/muse-conflict-name

t_case "8. 端口冲突 fail-fast"
# 用另一个安装目录去抢 muse-regress 已占的端口 —— 对脚本来说这是「外人占的」，
# 必须 fail-fast。注意判据用「已被别的程序占用」这句完整文案。
bash "$INSTALLER" --yes --dir /opt/muse-conflict --api-port $APIP --web-port 28719 >/tmp/cf.log 2>&1
RC8=$?
if grep -q "已被别的程序占用\|已被占用" /tmp/cf.log; then
  t_ok "端口冲突被拦"
  [ "$RC8" != 0 ] && t_ok "冲突时退出码非 0（$RC8）" || t_fail "冲突时退出码竟为 0"
  if [ ! -d /opt/muse-conflict ]; then
    t_ok "冲突时未产生残留目录"
  else
    t_fail "冲突时留下残留目录"
    rm -rf /opt/muse-conflict
  fi
else t_fail "端口冲突未被拦" "$(tail -3 /tmp/cf.log | tr '\n' ' ')"; fi

t_case "8b. 自己的容器占用端口 → 应放行（幂等重跑的关键）"
# 同一个安装目录再装一次，端口是自己上次的 —— 必须成功，不能报冲突
bash "$INSTALLER" --yes --dir "$TDIR" >/tmp/cf2.log 2>&1
RC8B=$?
if [ "$RC8B" = 0 ]; then
  t_ok "自己占的端口被正确放行（退出码 0）"
else
  t_fail "自己占的端口被误判为冲突" "$(grep -E '已被|×' /tmp/cf2.log | head -2 | tr '\n' ' ')"
fi

t_case "9. 卸载（保留数据）"
bash "$INSTALLER" --yes --uninstall --dir "$TDIR" >/tmp/uni.log 2>&1
# docker inspect 无 stderr 泄漏，显式判存在性
CID="$(docker ps -a --filter "name=^muse-regress$" --format '{{.Names}}' 2>/dev/null)"
if [ -n "$CID" ]; then t_fail "容器仍存在" "$CID"; else t_ok "容器已删除"; fi
systemctl is-active muse-regress-web.service >/dev/null 2>&1 && t_fail "网页服务仍在" || t_ok "网页服务已停"
[ -f /etc/systemd/system/muse-regress-web.service ] && t_fail "unit 文件残留" || t_ok "unit 文件已清理"
[ -d "$TDIR" ] && t_ok "数据目录按预期保留" || t_fail "数据目录被删（默认应保留）"

t_case "10. 卸载后复检 --status"
SO="$(bash "$INSTALLER" --status --dir "$TDIR" 2>&1)"
case "$SO" in
  *"没找到容器"*|*"未安装"*|*"未运行"*) t_ok "--status 正确报告未运行" ;;
  *) t_fail "--status 报告异常" "$(printf '%s' "$SO" | head -3 | tr '\n' ' ')" ;;
esac

t_case "11. 清理测试残留"
cleanup_all
[ ! -d "$TDIR" ] && t_ok "测试目录已清理" || t_fail "残留 $TDIR"

printf '\n%s════════════════════════════════════%s\n' "$B" "$O"
printf '  通过 %s%d%s   失败 %s%d%s\n' "$G" "$PASS" "$O" "$([ "$FAIL" -gt 0 ] && echo "$R" || echo "$G")" "$FAIL" "$O"
printf '%s════════════════════════════════════%s\n\n' "$B" "$O"
exit "$FAIL"
