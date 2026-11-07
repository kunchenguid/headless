# tailscale.ps1 - Tailscale on the Windows machine, for tailscale.sh, run in
# the administrator's SSH session.
#
# usage: tailscale.ps1 -Mode state            print "STATE IP", or "off"
#        tailscale.ps1 -Mode key -Server S    join with the auth key on
#                                             standard input
#        tailscale.ps1 -Mode link -Server S   print a sign-in link
# S is - for Tailscale's own control server. The machine joins unattended
# (it stays connected with nobody signed in), under its host name.
param([Parameter(Mandatory = $true)][ValidateSet('state', 'key', 'link')][string]$Mode, [string]$Server = '-')
. (Join-Path $PSScriptRoot 'common.ps1')

$record = Join-Path $HeadlessHome 'settings.json'
$on = $false
if (Test-Path $record) { $on = [bool]([IO.File]::ReadAllText($record) | ConvertFrom-Json).tailscale.enable }
if (-not $on) {
  if ($Mode -eq 'state') { 'off'; exit 0 }
  Fail 'Tailscale is off on this machine; set "tailscale": { "enable": true } in settings.json and run apply.sh'
}
$ts = Get-TailscaleState
if ($null -eq $ts) { Fail 'Tailscale is not installed; run apply.sh with Tailscale on first' }
if ($ts.State -eq 'unknown') { Fail "cannot read Tailscale's state: $($ts.Error)" }
if ($Mode -eq 'state') { "$($ts.State) $($ts.Ip)"; exit 0 }

$names = Get-ComputerNames
$name = ([string]([IO.File]::ReadAllText($record) | ConvertFrom-Json).hostName)
if (-not $name) { $name = $names.Pending }
$up = @('up', '--unattended', "--hostname=$($name.ToLower())")
if ($Server -ne '-') {
  if ($Server -notmatch '^https?://[A-Za-z0-9.:/_-]+$') { Fail 'the login server is not an http(s) address' }
  $up += "--login-server=$Server"
}

if ($Mode -eq 'key') {
  $key = [Console]::In.ReadLine()
  if ([string]::IsNullOrEmpty($key)) { Fail 'no auth key on standard input' }
  # A file only Administrators and SYSTEM may read (the folder's own rules),
  # so the key never reaches a command line.
  $file = Join-Path $HeadlessHome ('tailscale-key-' + [guid]::NewGuid().ToString('N'))
  try {
    [IO.File]::WriteAllText($file, $key)
    $key = $null
    & $TailscaleExe @up "--auth-key=file:$file" '--timeout=120s'
    if ($LASTEXITCODE -ne 0) { Fail 'Tailscale did not join with the auth key' }
  } finally { Remove-Item -Force $file -ErrorAction SilentlyContinue }
  exit 0
}

# link: start the join; the daemon keeps the sign-in going after this session ends.
Start-Process -FilePath $TailscaleExe -ArgumentList $up -WindowStyle Hidden
for ($i = 0; $i -lt 60; $i++) {
  Start-Sleep -Seconds 1
  $ts = Get-TailscaleState
  if ($ts.AuthUrl) { "Sign-in link: $($ts.AuthUrl)"; exit 0 }
  if ($ts.State -eq 'Running') { 'already connected'; exit 0 }
}
Fail 'no sign-in link appeared'
