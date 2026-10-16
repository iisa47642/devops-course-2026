#!/usr/bin/env bash
# Доставка сайта на учебную VM.
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LOCAL_DIR="$ROOT/site/"
DRY_RUN=false
ARGS=(-avz --delete --chmod=D755,F644)

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--dry-run" ) ]]; then
    echo "Использование: scripts/deploy.sh [--dry-run]" >&2
    exit 1
fi
if [[ $# -eq 1 ]]; then
    DRY_RUN=true
    ARGS+=(--dry-run)
fi
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: нет site/index.html" >&2
    exit 1
fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "Ошибка: сначала зафиксируйте изменения в Git" >&2
    exit 1
fi
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"

if ! rsync "${ARGS[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "$LOCAL_DIR" "$REMOTE:$REMOTE_DIR/"; then
    echo "Ошибка доставки" >&2
    exit 1
fi
if [[ "$DRY_RUN" == true ]]; then
    echo "План для коммита $COMMIT. Файлы не изменены."
    exit 0
fi
if ! curl -fsS --connect-timeout 10 --max-time 20 \
    --cacert "$CA_CERT" "$SITE_URL/" -o /dev/null; then
    echo "Ошибка: сайт недоступен или сертификат не прошёл проверку" >&2
    exit 1
fi
echo "Доставлен коммит $COMMIT"
