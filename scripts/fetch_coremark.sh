#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
COREMARK="$ROOT/ext/coremark"
REVISION=1f483d5b8316753a742cbf5590caf5bd0a4e4777

if [[ ! -d "$COREMARK/.git" ]]; then
  git clone https://github.com/eembc/coremark.git "$COREMARK"
fi
git -C "$COREMARK" fetch origin
git -C "$COREMARK" checkout "$REVISION"
