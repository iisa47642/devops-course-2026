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
echo "Passed: $PASS, failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
