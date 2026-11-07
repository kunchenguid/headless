# shellcheck shell=bash disable=SC2034
# lib.sh - shared by the Windows step scripts beside it; sourced, not run.
# It builds on the Mac steps' lib.sh (headless.env, the SSH options, the
# first sign-in and the password plumbing are the same everywhere) and adds
# what differs on Windows: the machine's shell is cmd.exe or PowerShell, not
# a POSIX shell, and an administrator's SSH session already has full rights,
# so nothing goes through sudo.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/../mac/lib.sh"
REMOTE_SRC="$SCRIPTS/windows/remote"
# Where the skill keeps its scripts, the config folder's copy and the
# machine's record of its settings: readable by Administrators and SYSTEM only.
WIN_HOME=C:/ProgramData/headless
POWERSHELL="powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass"

# ps_command SCRIPT: a command line that runs PowerShell SCRIPT on the
# machine, the same under cmd.exe and under PowerShell (whichever is the
# SSH shell), with no quoting to get wrong: the script travels encoded.
ps_command() {
  printf '%s -EncodedCommand %s' "$POWERSHELL" \
    "$(printf '%s' "\$ProgressPreference = 'SilentlyContinue'; $1" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')"
}
# win_ps SCRIPT: run PowerShell SCRIPT on the machine, standard input passed on.
win_ps() { on "$(ps_command "$1")"; }
# run_remote NAME ARGS...: run remote/NAME.ps1 (copied by copy_remote).
run_remote() { local name="$1"; shift; on "$POWERSHELL -File $WIN_HOME/remote/$name.ps1 $*"; }

# The first sign-in on Windows: the key goes to administrators_authorized_keys
# (what Windows' OpenSSH reads for an administrator), readable only by
# Administrators and SYSTEM, or sshd ignores it.
KEY_PROBE='exit 0'
HOST_KEY_FILE='C:\ProgramData\ssh\ssh_host_ed25519_key.pub'
# shellcheck disable=SC2016 # runs on the machine
ADD_KEY_COMMAND="$(ps_command '
$k = [Console]::In.ReadLine()
$p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 3 }
$f = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
$have = @()
if (Test-Path $f) { $have = @(Get-Content $f) }
if ($have -notcontains $k) { Add-Content -Path $f -Value $k -Encoding Ascii }
icacls $f /inheritance:r /grant:r "*S-1-5-32-544:F" "*S-1-5-18:F" | Out-Null
if ($LASTEXITCODE -ne 0) { exit 1 }
')"

# copy_remote: put the remote step scripts (remote/*.ps1) in
# C:\ProgramData\headless\remote, readable by Administrators and SYSTEM
# only (and empty C:\ProgramData\headless\config).
copy_remote() {
  # shellcheck disable=SC2016 # runs on the machine
  win_ps '
$d = Join-Path $env:ProgramData "headless"
New-Item -ItemType Directory -Force -Path $d | Out-Null
icacls $d /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" | Out-Null
if ($LASTEXITCODE -ne 0) { exit 1 }
foreach ($s in "remote", "config") {
  $p = Join-Path $d $s
  if (Test-Path $p) { Remove-Item -Recurse -Force $p }
  New-Item -ItemType Directory -Path $p | Out-Null
}' || die "could not prepare $WIN_HOME on $ADDRESS"
  tar_c -C "$REMOTE_SRC" . | on "tar -xf - -C $WIN_HOME/remote" || die "could not copy the scripts to $ADDRESS"
}
# copy_config: copy_remote, then the config folder into
# C:\ProgramData\headless\config, without its git history, known_hosts and
# headless.env.
copy_config() {
  copy_remote
  tar_c -C "$CONFIG" --exclude .git --exclude known_hosts --exclude headless.env . \
    | on "tar -xf - -C $WIN_HOME/config" || die "could not copy $CONFIG to $ADDRESS"
}

# setting_on PATH DEFAULT: "true" or "false", the boolean at PATH (such as
# autoLogin or tailscale.enable) in the config folder's settings.json, or
# DEFAULT when it is not there. It reads JSON with jq, plutil (every Mac) or
# python3, whichever this computer has first.
setting_on() {
  local json="$CONFIG/settings.json" v=""
  [ -f "$json" ] || die "$CONFIG has no settings.json; run new-config.sh first"
  if command -v jq > /dev/null; then
    v="$(jq -r ".$1" "$json")" || die "settings.json is not valid JSON"
  elif command -v plutil > /dev/null; then
    plutil -extract user raw -o - "$json" > /dev/null 2>&1 || die "settings.json is not valid JSON, or names no user"
    v="$(plutil -extract "$1" raw -o - "$json" 2> /dev/null || true)"
  elif command -v python3 > /dev/null && python3 -c 'import json' 2> /dev/null; then
    v="$(python3 -c 'import json, sys
v = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    v = v.get(k) if isinstance(v, dict) else None
print("" if v is None else str(v).lower())' "$json" "$1")" || die "settings.json is not valid JSON"
  else
    die "reading settings.json needs python3, jq or plutil on this computer"
  fi
  case "$v" in true | 1) echo true ;; false | 0) echo false ;; *) echo "$2" ;; esac
}
