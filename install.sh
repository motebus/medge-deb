#!/bin/sh
set -eu

BASE_URL="https://motebus.github.io/medge-deb"
EXPECTED_FINGERPRINT="AECAA1DCDAF19C7B7FEAF0C082A0E180EDAEA7A0"
KEYRING_PATH="/etc/apt/keyrings/medge-archive-keyring.gpg"
SOURCES_PATH="/etc/apt/sources.list.d/medge.sources"
SYSTEM_UNITS="
sphered.service
mgated.service
ss-webosd.service
moted.service
agosd.service
deskd.service
"
DESKTOP_UNITS="
deskd-session.service
ss-webos-session.service
"

fail() {
    printf 'MEdge install failed: %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] ||
    fail "run this installer as root (for example: sudo sh /tmp/medge-install.sh)"

[ -r /etc/os-release ] || fail "cannot identify the operating system"
# shellcheck disable=SC1091
. /etc/os-release
[ "${ID:-}" = "ubuntu" ] && [ "${VERSION_ID:-}" = "24.04" ] ||
    fail "Ubuntu 24.04 is required"

command -v dpkg >/dev/null 2>&1 || fail "dpkg is unavailable"
[ "$(dpkg --print-architecture)" = "amd64" ] ||
    fail "amd64 architecture is required"
[ -d /run/systemd/system ] ||
    fail "systemd must be running to start the MEdge services"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

TEMP_DIR="$(mktemp -d /tmp/medge-install.XXXXXX)"
cleanup() {
    rm -f \
        "$TEMP_DIR/medge-archive-keyring.gpg" \
        "$TEMP_DIR/medge.sources" \
        "$TEMP_DIR/expected.sources"
    rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

curl --proto '=https' --tlsv1.2 -fsSLo \
    "$TEMP_DIR/medge-archive-keyring.gpg" \
    "$BASE_URL/medge-archive-keyring.gpg"
curl --proto '=https' --tlsv1.2 -fsSLo \
    "$TEMP_DIR/medge.sources" \
    "$BASE_URL/medge.sources"

ACTUAL_FINGERPRINT="$(
    gpg --batch --show-keys --with-colons \
        "$TEMP_DIR/medge-archive-keyring.gpg" |
        awk -F: '
            $1 == "pub" { public_keys += 1 }
            $1 == "fpr" && fingerprint == "" { fingerprint = $10 }
            END {
                if (public_keys != 1 || fingerprint == "") {
                    exit 1
                }
                print fingerprint
            }
        '
)" || fail "the downloaded archive key is invalid"
[ "$ACTUAL_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ] ||
    fail "archive-key fingerprint mismatch (received $ACTUAL_FINGERPRINT)"

cat >"$TEMP_DIR/expected.sources" <<EOF
Types: deb
URIs: $BASE_URL
Suites: stable
Components: main
Architectures: amd64
Signed-By: $KEYRING_PATH
EOF
cmp -s "$TEMP_DIR/medge.sources" "$TEMP_DIR/expected.sources" ||
    fail "the downloaded APT source definition is invalid"

install -d -m 0755 /etc/apt/keyrings
install -m 0644 "$TEMP_DIR/medge-archive-keyring.gpg" "$KEYRING_PATH"
install -m 0644 "$TEMP_DIR/medge.sources" "$SOURCES_PATH"

apt-get update
apt-get install -y medge

for command_name in awk getent loginctl runuser systemctl; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "required runtime command is unavailable: $command_name"
done

systemctl daemon-reload
for unit in $SYSTEM_UNITS; do
    systemctl reset-failed "$unit" 2>/dev/null || true
    systemctl enable --now "$unit" ||
        fail "$unit did not start; inspect it with: systemctl status $unit"
done

sleep 2
for unit in $SYSTEM_UNITS; do
    systemctl is-active --quiet "$unit" ||
        fail "$unit is not active; inspect it with: systemctl status $unit"
done

DESKTOP_SESSION=""
DESKTOP_USER=""
for session_id in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
    [ "$(loginctl show-session "$session_id" -p Active --value)" = "yes" ] ||
        continue
    [ "$(loginctl show-session "$session_id" -p Remote --value)" = "no" ] ||
        continue
    session_type="$(
        loginctl show-session "$session_id" -p Type --value
    )"
    [ "$session_type" = "wayland" ] || [ "$session_type" = "x11" ] ||
        continue
    session_user="$(
        loginctl show-session "$session_id" -p Name --value
    )"
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] &&
        [ "$session_user" != "$SUDO_USER" ]; then
        continue
    fi
    [ -z "$DESKTOP_SESSION" ] ||
        fail "more than one active local graphical session is eligible"
    DESKTOP_SESSION="$session_id"
    DESKTOP_USER="$session_user"
done

if [ -n "$DESKTOP_SESSION" ]; then
    DESKTOP_UID="$(id -u "$DESKTOP_USER")"
    DESKTOP_HOME="$(
        getent passwd "$DESKTOP_USER" | awk -F: '{print $6}'
    )"
    [ -n "$DESKTOP_HOME" ] ||
        fail "home directory is unavailable for $DESKTOP_USER"
    user_systemctl() {
        runuser -u "$DESKTOP_USER" -- env \
            "HOME=$DESKTOP_HOME" \
            "XDG_RUNTIME_DIR=/run/user/$DESKTOP_UID" \
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$DESKTOP_UID/bus" \
            systemctl --user "$@"
    }
    user_systemctl daemon-reload
    for unit in $DESKTOP_UNITS; do
        user_systemctl reset-failed "$unit" 2>/dev/null || true
        user_systemctl restart "$unit" ||
            fail "$unit did not start for graphical user $DESKTOP_USER"
    done
    sleep 2
    for unit in $DESKTOP_UNITS; do
        user_systemctl is-active --quiet "$unit" ||
            fail "$unit is not active for graphical user $DESKTOP_USER"
    done
    printf 'MEdge desktop helpers are running for %s (session %s)\n' \
        "$DESKTOP_USER" "$DESKTOP_SESSION"
else
    printf '%s\n' \
        'No active local graphical session; desktop helpers will start at login.'
fi

INSTALLED_VERSION="$(dpkg-query -W -f='${Version}' medge)"
printf 'MEdge %s installed and running successfully from %s\n' \
    "$INSTALLED_VERSION" "$BASE_URL"
