#!/usr/bin/env bash
# Local, non-destructive tests. Docker lifecycle tests run only in disposable CI.
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
bash -n install.sh
python3 -m unittest discover -s tests -v
python3 tools/test-import-tool.py
bash install.sh --dry-run
