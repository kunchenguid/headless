# shellcheck shell=bash disable=SC2034
# lib.sh - shared by the Linux step scripts beside it; sourced, not run.
# It builds on the Mac steps' lib.sh (headless.env, the SSH options, the
# first sign-in and the password plumbing are the same on both) and adds
# what differs on Linux.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../mac/lib.sh"
REMOTE_SRC="$SCRIPTS/linux/remote"
# NixOS puts nix on the system profile; the flags work without any setting.
NIXOS_NIX="/run/current-system/sw/bin/nix --extra-experimental-features 'nix-command flakes'"

# os_kind: "nixos" when the machine runs NixOS, otherwise its os-release ID.
os_kind() { on '. /etc/os-release && printf "%s\n" "$ID"'; }

# settings_env: settings.json of the config folder as the KEY=value lines
# the machine's remote scripts read (/etc/headless/settings.env), with every
# value checked. It reads JSON with jq, plutil (every Mac) or python3,
# whichever this computer has first (on a Mac without the developer tools,
# even asking python3 opens an install prompt).
settings_env() {
  local json="$CONFIG/settings.json" raw
  [ -f "$json" ] || die "$CONFIG has no settings.json; run new-config.sh first"
  if command -v jq > /dev/null; then
    raw="$(jq -r '"USER_NAME=\(.user // "")",
      "HOST_NAME=\(.hostName // "")",
      "KEY_ONLY=\(if .keyOnlySsh == false then false else true end)",
      "AUTO_LOGIN=\(if .autoLogin == false then false else true end)",
      "TAILSCALE=\(.tailscale.enable == true)",
      "NEVER_SLEEP=\(if .extras.neverSleep == false then false else true end)",
      "AUTO_UPDATES=\(if .extras.autoUpdates == false then false else true end)",
      ((.sshKeys // [])[] | "AUTHORIZED_KEY=\(.)")' "$json")" || die "settings.json is not valid JSON"
  elif command -v plutil > /dev/null; then
    p() { plutil -extract "$1" raw -o - "$json" 2> /dev/null; }
    pb() { local v; v="$(p "$1")"; [ -n "$v" ] || v="$2"; [ "$v" = true ] || [ "$v" = 1 ] && echo true || echo false; }
    raw="USER_NAME=$(p user)
HOST_NAME=$(p hostName)
KEY_ONLY=$(pb keyOnlySsh true)
AUTO_LOGIN=$(pb autoLogin true)
TAILSCALE=$(pb tailscale.enable false)
NEVER_SLEEP=$(pb extras.neverSleep true)
AUTO_UPDATES=$(pb extras.autoUpdates true)"
    local i=0 k
    while k="$(p "sshKeys.$i")" && [ -n "$k" ]; do raw="$raw
AUTHORIZED_KEY=$k"; i=$((i + 1)); done
  elif command -v python3 > /dev/null && python3 -c 'import json' 2> /dev/null; then
    raw="$(python3 - "$json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
b = lambda v: "true" if v else "false"
e = s.get("extras", {})
print("USER_NAME=" + str(s.get("user", "")))
print("HOST_NAME=" + (s.get("hostName") or ""))
print("KEY_ONLY=" + b(s.get("keyOnlySsh", True)))
print("AUTO_LOGIN=" + b(s.get("autoLogin", True)))
print("TAILSCALE=" + b(s.get("tailscale", {}).get("enable", False)))
print("NEVER_SLEEP=" + b(e.get("neverSleep", True)))
print("AUTO_UPDATES=" + b(e.get("autoUpdates", True)))
for k in s.get("sshKeys", []):
    print("AUTHORIZED_KEY=" + k)
PY
)" || die "settings.json is not valid JSON"
  else
    die "reading settings.json needs python3, jq or plutil on this computer"
  fi
  # Only plain values reach the machine, where root reads them.
  printf '%s\n' "$raw" | while IFS= read -r line; do
    case "$line" in
      USER_NAME=*) [[ "${line#*=}" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "settings.json: user is not a plain account name" ;;
      HOST_NAME=*) [[ "${line#*=}" =~ ^([A-Za-z0-9][A-Za-z0-9-]{0,62})?$ ]] || die "settings.json: hostName must be letters, digits and dashes" ;;
      AUTHORIZED_KEY=*) [[ "${line#*=}" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)\ [A-Za-z0-9+/=]+(\ [[:print:]]*)?$ ]] \
        || die "settings.json: an sshKeys entry is not a plain public key line" ;;
      *=true | *=false) ;;
      *) die "settings.json: unexpected value in '${line%%=*}'" ;;
    esac
    printf '%s\n' "$line"
  done
}

# put_settings: the checked settings into ~/.headless/remote/settings.env on
# the machine, for remote/apply-script.sh.
put_settings() {
  local env
  env="$(settings_env)" || exit 1
  printf '%s\n' "$env" | grep -qx "USER_NAME=$LOGIN" || die "settings.json names a user other than LOGIN ($LOGIN) in headless.env"
  printf '%s\n' "$env" | on 'cat > ~/.headless/remote/settings.env'
}

# tar_c ARGS...: tar to standard output, without the macOS extended
# attributes that GNU tar on the machine would warn about.
tar_c() {
  if tar --version 2> /dev/null | grep -q bsdtar; then
    COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -cf - "$@"
  else
    tar -cf - "$@"
  fi
}

# copy_remote: put the remote step scripts in ~/.headless/remote.
copy_remote() {
  tar_c -C "$REMOTE_SRC" . | on 'rm -rf ~/.headless/remote && mkdir -p -m 0700 ~/.headless/remote && tar -xf - -C ~/.headless/remote'
}
