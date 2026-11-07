#!/bin/bash
# remote/apply-script.sh - the distro-neutral setup for a Linux machine that
# keeps its own distribution, run as root by apply.sh with sudo -S. It reads
# settings.env beside it and changes only what differs; running it again
# changes nothing. Supported: Debian and Ubuntu (apt), Fedora (dnf5).
#
# usage: sudo -S bash apply-script.sh LOGIN
set -euo pipefail
exec < /dev/null
die() { echo "headless: $*" >&2; exit 1; }
say() { echo "headless: $*"; }
changed() { echo "headless: changed: $*"; }

LOGIN="${1:?usage: apply-script.sh LOGIN}"
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || die "run apply-script.sh as root"
export HOME=/root
[[ "$LOGIN" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "LOGIN is not a plain account name"
getent passwd "$LOGIN" > /dev/null || die "$LOGIN is not an account on this machine"
[ -d /run/systemd/system ] || die "this machine does not run systemd, which the script needs"

# settings.env holds checked KEY=value lines; read them, never run them.
USER_NAME="" HOST_NAME="" KEY_ONLY=true AUTO_LOGIN=true TAILSCALE=false NEVER_SLEEP=true AUTO_UPDATES=true
KEYS=()
while IFS= read -r line; do
  case "$line" in
    USER_NAME=*) USER_NAME="${line#*=}" ;;
    HOST_NAME=*) HOST_NAME="${line#*=}" ;;
    KEY_ONLY=*) KEY_ONLY="${line#*=}" ;;
    AUTO_LOGIN=*) AUTO_LOGIN="${line#*=}" ;;
    TAILSCALE=*) TAILSCALE="${line#*=}" ;;
    NEVER_SLEEP=*) NEVER_SLEEP="${line#*=}" ;;
    AUTO_UPDATES=*) AUTO_UPDATES="${line#*=}" ;;
    AUTHORIZED_KEY=*) KEYS+=("${line#*=}") ;;
  esac
done < "$HERE/settings.env"
[ "$USER_NAME" = "$LOGIN" ] || die "settings.env is for $USER_NAME, not $LOGIN"
[[ "$HOST_NAME" =~ ^([A-Za-z0-9][A-Za-z0-9-]{0,62})?$ ]] || die "HOST_NAME is not a plain name"

# shellcheck source=/dev/null
. /etc/os-release
pm=""
if command -v apt-get > /dev/null; then
  pm=apt
elif command -v dnf5 > /dev/null; then
  pm=dnf5
fi
if [ -z "$pm" ] && { [ "$AUTO_UPDATES" = true ] || [ "$TAILSCALE" = true ]; }; then
  die "$PRETTY_NAME has neither apt nor dnf5; turn autoUpdates and Tailscale off in settings.json, or set them up yourself"
fi

# --- Keys: every configured key may sign in as the user. ---
home="$(getent passwd "$LOGIN" | cut -d: -f6)"
group="$(id -gn "$LOGIN")"
ak="$home/.ssh/authorized_keys"
install -d -m 0700 -o "$LOGIN" -g "$group" "$home/.ssh"
[ -e "$ak" ] || install -m 0600 -o "$LOGIN" -g "$group" /dev/null "$ak"
for k in "${KEYS[@]}"; do
  if ! grep -qxF "$k" "$ak"; then
    printf '%s\n' "$k" >> "$ak"
    changed "added a key to $ak"
  fi
done
grep -qE '^(ssh-|ecdsa-|sk-)' "$ak" || die "$LOGIN has no SSH key to sign in with; run connect.sh first"

# --- SSH: key only. sshd takes the first value it reads, and drop-ins are
# read in name order, so this one comes before the distribution's own
# (such as Ubuntu's 50-cloud-init.conf). ---
sshd=/usr/sbin/sshd
[ -x "$sshd" ] || die "no OpenSSH server at $sshd"
grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config \
  || die "/etc/ssh/sshd_config does not read /etc/ssh/sshd_config.d; add 'Include /etc/ssh/sshd_config.d/*.conf' at its top, then run this again"
dropin=/etc/ssh/sshd_config.d/00-headless.conf
want="# Written by the headless skill.
ClientAliveInterval 60
ClientAliveCountMax 3"
if [ "$KEY_ONLY" = true ]; then
  want="$want
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no"
fi
if [ "$(cat "$dropin" 2> /dev/null || true)" != "$want" ]; then
  old="$(mktemp)"
  had=0
  [ ! -e "$dropin" ] || { cp -p "$dropin" "$old"; had=1; }
  printf '%s\n' "$want" > "$dropin"
  chmod 0644 "$dropin"
  if ! "$sshd" -t; then
    if [ "$had" = 1 ]; then cp -p "$old" "$dropin"; else rm -f "$dropin"; fi
    rm -f "$old"
    die "sshd refused the new settings; nothing changed"
  fi
  rm -f "$old"
  for u in ssh.service sshd.service; do
    ! systemctl is-active -q "$u" || systemctl reload "$u"
  done
  changed "SSH settings in $dropin"
fi
eff="$("$sshd" -T -C "user=$LOGIN,host=headless-check,addr=127.0.0.1" 2> /dev/null)"
if [ "$KEY_ONLY" = true ]; then
  grep -qx 'passwordauthentication no' <<< "$eff" || die "sshd still allows password sign-in; another setting overrides $dropin"
fi

# --- Host name. ---
if [ -n "$HOST_NAME" ] && [ "$(hostnamectl --static 2> /dev/null || hostname)" != "$HOST_NAME" ]; then
  hostnamectl set-hostname "$HOST_NAME"
  changed "host name $HOST_NAME"
fi
if [ -n "$HOST_NAME" ]; then
  # sudo and others look the machine's own name up.
  if ! grep -qE "^127\.0\.1\.1[[:space:]]+$HOST_NAME([[:space:]]|\$)" /etc/hosts; then
    if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
      sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1 $HOST_NAME/" /etc/hosts
    else
      printf '127.0.1.1 %s\n' "$HOST_NAME" >> /etc/hosts
    fi
    changed "/etc/hosts names $HOST_NAME"
  fi
  # cloud-init would set the cloud's name again at the next start.
  if [ -d /etc/cloud/cloud.cfg.d ] && [ ! -e /etc/cloud/cloud.cfg.d/99-headless.cfg ]; then
    printf '# Written by the headless skill: keep the host name it set.\npreserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-headless.cfg
    changed "cloud-init keeps the host name"
  fi
fi

# --- Never sleep. ---
if [ "$NEVER_SLEEP" = true ]; then
  for t in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    if [ "$(systemctl is-enabled "$t" 2> /dev/null || true)" != masked ]; then
      systemctl mask "$t" > /dev/null 2>&1
      changed "$t masked"
    fi
  done
fi

# --- Automatic sign-in: the user's session starts at boot (lingering). ---
if [ "$AUTO_LOGIN" = true ]; then
  if [ ! -e "/var/lib/systemd/linger/$LOGIN" ]; then
    loginctl enable-linger "$LOGIN"
    changed "$LOGIN's session starts at boot"
  fi
elif [ -e "/var/lib/systemd/linger/$LOGIN" ]; then
  loginctl disable-linger "$LOGIN"
  changed "$LOGIN's session no longer starts at boot"
fi

# --- Package installs. ---
apt_updated=0
pkg_install() {
  case "$pm" in
    apt)
      if [[ "$(dpkg-query -W -f='${Status}' "$1" 2> /dev/null || true)" != *'install ok installed'* ]]; then
        [ "$apt_updated" = 1 ] || { apt-get -q update > /dev/null; apt_updated=1; }
        DEBIAN_FRONTEND=noninteractive apt-get -q -y install "$1" > /dev/null
        changed "installed $1"
      fi ;;
    dnf5)
      if ! rpm -q "$1" > /dev/null 2>&1; then
        dnf5 -q -y install "$1" > /dev/null
        changed "installed $1"
      fi ;;
  esac
}
write_file() { # PATH CONTENT
  if [ "$(cat "$1" 2> /dev/null || true)" != "$2" ]; then
    printf '%s\n' "$2" > "$1"
    chmod 0644 "$1"
    changed "$1"
  fi
}

# --- Automatic updates. ---
if [ "$AUTO_UPDATES" = true ]; then
  case "$pm" in
    apt)
      pkg_install unattended-upgrades
      write_file /etc/apt/apt.conf.d/20auto-upgrades 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'
      for t in apt-daily.timer apt-daily-upgrade.timer; do
        if [ "$(systemctl is-enabled "$t" 2> /dev/null || true)" != enabled ]; then
          systemctl enable --now "$t" > /dev/null 2>&1
          changed "$t on"
        fi
      done ;;
    dnf5)
      pkg_install dnf5-plugin-automatic
      write_file /etc/dnf/automatic.conf '# Written by the headless skill.
[commands]
apply_updates = yes'
      if [ "$(systemctl is-enabled dnf5-automatic.timer 2> /dev/null || true)" != enabled ]; then
        systemctl enable --now dnf5-automatic.timer > /dev/null 2>&1
        changed "dnf5-automatic.timer on"
      fi ;;
  esac
fi

# --- Tailscale, from Tailscale's own signed package repository. ---
if [ "$TAILSCALE" = true ]; then
  if ! command -v tailscale > /dev/null; then
    case "$pm" in
      apt)
        case "$ID" in debian | ubuntu) ;; *) die "Tailscale's packages cover Debian and Ubuntu; $ID is neither" ;; esac
        [ -n "${VERSION_CODENAME-}" ] || die "/etc/os-release names no release codename"
        pkg_install curl
        pkg_install ca-certificates
        base="https://pkgs.tailscale.com/stable/$ID/$VERSION_CODENAME"
        install -d -m 0755 /usr/share/keyrings
        curl -fsSL "$base.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
        curl -fsSL "$base.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
        apt_updated=0
        pkg_install tailscale ;;
      dnf5)
        dnf5 -q -y config-manager addrepo --overwrite --from-repofile="https://pkgs.tailscale.com/stable/$ID/tailscale.repo" > /dev/null
        pkg_install tailscale ;;
    esac
  fi
  if [ "$(systemctl is-enabled tailscaled 2> /dev/null || true)" != enabled ] || ! systemctl is-active -q tailscaled; then
    systemctl enable --now tailscaled > /dev/null 2>&1
    changed "tailscaled on"
  fi
fi

# --- What this machine should be, for the verify step. ---
install -d -m 0755 /etc/headless
write_file /etc/headless/settings.env "KIND=script
USER_NAME=$LOGIN
HOST_NAME=$HOST_NAME
KEY_ONLY=$KEY_ONLY
AUTO_LOGIN=$AUTO_LOGIN
TAILSCALE=$TAILSCALE
NEVER_SLEEP=$NEVER_SLEEP
AUTO_UPDATES=$AUTO_UPDATES
PACKAGES=$pm"
say "the script is done"
