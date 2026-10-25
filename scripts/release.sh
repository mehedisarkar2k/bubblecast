#!/bin/bash
set -euo pipefail

# One command: build, sign and package. The only file to share or double-click is in dist/.
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
bash scripts/make-pkg.sh
