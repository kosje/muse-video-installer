#!/usr/bin/env bash
# Only for a disposable Linux CI runner. Never run against a real deployment.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR=/opt/mvw-ci
[[ ! -e $DIR ]] || { echo 'CI directory already exists; refusing'; exit 1; }
sudo bash "$ROOT/install.sh" --dir "$DIR" --api-port 19610 | tee /tmp/mvw-ci-install.log
! grep -q 'm2a_' /tmp/mvw-ci-install.log
sudo bash "$ROOT/install.sh" --dir "$DIR" --status
for path in /data/auth.json /data/accounts.json /install.conf /compose.yml /.git/config; do
  test "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:19610$path")" = 404
done
sudo python3 "$ROOT/tests/probe.py" "$DIR" rotate
sudo bash "$ROOT/install.sh" --dir "$DIR" --upgrade
sudo python3 "$ROOT/tests/probe.py" "$DIR" verify
sudo test -n "$(sudo find "$DIR/backups" -name '*.tar.gz' -print -quit)"
sudo bash "$ROOT/install.sh" --dir "$DIR" --rollback
sudo python3 "$ROOT/tests/probe.py" "$DIR" verify

# Fail exactly the first compose up during a port-changing upgrade. The next
# up is the real rollback. No Docker commands or system files are replaced.
shim="$(mktemp -d)"
real_docker="$(command -v docker)"
printf '%s\n' '#!/usr/bin/env bash' 'set -eu' \
  'if [[ " $* " == *" up "* && ! -e /tmp/mvw-ci-failed-once ]]; then touch /tmp/mvw-ci-failed-once; exit 1; fi' \
  "exec $real_docker \"\$@\"" > "$shim/docker"
chmod +x "$shim/docker"
if sudo env "PATH=$shim:$PATH" bash "$ROOT/install.sh" --dir "$DIR" --upgrade --api-port 19611; then
  echo 'Injected failure should not succeed'; exit 1
fi
sudo python3 "$ROOT/tests/probe.py" "$DIR" verify
test "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:19610/readyz)" = 200
sudo bash "$ROOT/install.sh" --dir "$DIR" --uninstall
sudo test -f "$DIR/data/auth.json"
echo 'PASS: install, auth, persisted rotation, upgrade, rollback, failure recovery, uninstall retention'
