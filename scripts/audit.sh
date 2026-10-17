#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "[OK] $desc"
        ((PASS+=1))
    else
        echo "[FAIL] $desc (expected: '$expected', actual: '$actual')"
        ((FAIL+=1))
    fi
}
if ! sudo -v; then
    echo '[ERROR] sudo access is required'
    exit 1
fi
if ! SSH_CONFIG=$(sudo /usr/sbin/sshd -T); then
    echo '[ERROR] Cannot read sshd configuration'
    exit 1
fi
if ! FIREWALL=$(sudo ufw status verbose); then
    echo '[ERROR] Cannot read UFW configuration'
    exit 1
fi
value() { awk -v key="$1" '$1==key {print $2}' <<< "$SSH_CONFIG"; }
echo "Configuration audit: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo '[1] SSH'
check 'Root login disabled' no "$(value permitrootlogin)"
check 'Password authentication disabled' no "$(value passwordauthentication)"
PORTS=$(value port)
NONSTANDARD=yes
[[ -n "$PORTS" ]] || NONSTANDARD=no
while IFS= read -r port; do
    [[ "$port" =~ ^[0-9]+$ ]] && ((port>=1 && port<=65535)) && [[ "$port" != 22 ]] || NONSTANDARD=no
done <<< "$PORTS"
check 'SSH uses a nonstandard port' yes "$NONSTANDARD"
check 'MaxAuthTries is 3' 3 "$(value maxauthtries)"
echo '[2] Firewall'
check 'UFW active' active "$(awk '/^Status:/{print $2}' <<< "$FIREWALL")"
check 'Default incoming policy is deny' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$FIREWALL")"
echo '[3] User accounts'
awk -F: '$3>=1000 && $3<65534 {printf "%s (uid=%s)\n", $1, $3}' /etc/passwd
echo '[4] Web server'
check 'Nginx is active' active "$(systemctl is-active nginx)"
NGINX_OK=no
sudo nginx -t >/dev/null 2>&1 && NGINX_OK=yes
check 'Nginx configuration is valid' yes "$NGINX_OK"
CERT_OK=no
openssl x509 -in /etc/ssl/certs/devops.crt -noout \
    -checkend 2592000 >/dev/null 2>&1 && CERT_OK=yes
check 'Certificate valid for at least 30 days' yes "$CERT_OK"
RIGHTS_OK=no
if [[ -d /var/www/devops-site ]] && \
    WRITABLE=$(sudo find /var/www/devops-site -perm -o+w) && \
    KEY_MODE=$(sudo stat -c '%a' /etc/ssl/private/devops.key); then
    [[ -z "$WRITABLE" && "$KEY_MODE" == 600 ]] && RIGHTS_OK=yes
fi
check 'Site has no world-writable files and key is 600' yes "$RIGHTS_OK"
echo '[5] Containerization'
check 'Docker is active' active "$(systemctl is-active docker)"
DB_HEALTH=$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null) || DB_HEALTH=missing
check 'Database container is healthy' healthy "$DB_HEALTH"
PORTS_OK=no
if SOCKETS=$(ss -tln); then
    PORTS_OK=$(awk '
        NR>1 && $4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/ {bad=1}
        END {print bad ? "no" : "yes"}
    ' <<< "$SOCKETS")
fi
check 'Ports 5000 and 5432 are not exposed to the network' yes "$PORTS_OK"
ENV_MODE=$(stat -c '%a' "$HOME/app/.env" 2>/dev/null) || ENV_MODE=missing
check 'Application .env has mode 600' 600 "$ENV_MODE"
echo "Passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
