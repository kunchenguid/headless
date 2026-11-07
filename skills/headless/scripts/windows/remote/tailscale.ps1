# tailscale.ps1 - Tailscale on the Windows machine, for tailscale.sh, run in
# the administrator's SSH session.
#
# usage: tailscale.ps1 -Mode state            print "STATE IP", "off", or
#                                             "Owned IP ACCOUNT" (IP - when
#                                             none) for a Tailscale another
#                                             account joined
#        tailscale.ps1 -Mode uninstall        uninstall Tailscale and its
#                                             state (once the user agreed)
#        tailscale.ps1 -Mode key -Server S    join with the auth key on
#                                             standard input
#        tailscale.ps1 -Mode link -Server S   print a sign-in link
# S is - for Tailscale's own control server. The machine joins unattended
# (it stays connected with nobody signed in), under its host name.
param([Parameter(Mandatory = $true)][ValidateSet('state', 'key', 'link', 'uninstall')][string]$Mode, [string]$Server = '-')
. (Join-Path $PSScriptRoot 'common.ps1')

if ($Mode -eq 'uninstall') {
  # Not over Tailscale itself: the uninstall would end this session halfway.
  $here = @("$env:SSH_CONNECTION" -split ' ')[2]
  $tsAddresses = @(Get-NetIPAddress -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -like 'Tailscale*' } | ForEach-Object { $_.IPAddress -replace '%.*$', '' })
  if ($here -and $tsAddresses -contains ($here -replace '%.*$', '')) { Fail "this SSH session reaches the PC over Tailscale ($here); uninstall over the PC's local network address instead" }
  $apps = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' | Get-ItemProperty |
      Where-Object { $_.DisplayName -eq 'Tailscale' -and $_.WindowsInstaller -eq 1 })
  foreach ($a in $apps) {
    $p = Start-Process -FilePath msiexec.exe -Wait -PassThru -ArgumentList '/x', $a.PSChildName, '/quiet', '/norestart'
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Fail "the Tailscale uninstaller failed (exit code $($p.ExitCode))" }
  }
  # Its state, which ties it to the account that joined it.
  $state = Join-Path $env:ProgramData 'Tailscale'
  Remove-Item -Recurse -Force $state -ErrorAction SilentlyContinue
  $left = @($TailscaleExe, $state | Where-Object { Test-Path $_ })
  if ($left) { Fail "Tailscale is not fully removed ($($left -join ', ') still there); restart the PC (restart.sh) and run tailscale.sh --uninstall again" }
  'Tailscale uninstalled'
  exit 0
}

$record = Join-Path $HeadlessHome 'settings.json'
$on = $false
if (Test-Path $record) { $on = [bool]([IO.File]::ReadAllText($record) | ConvertFrom-Json).tailscale.enable }
if (-not $on) {
  if ($Mode -eq 'state') { 'off'; exit 0 }
  Fail 'Tailscale is off on this machine; set "tailscale": { "enable": true } in settings.json and run apply.sh'
}
$ts = Get-TailscaleState
if ($null -eq $ts) { Fail 'Tailscale is not installed; run apply.sh with Tailscale on first' }
if ($ts.Owner) {
  if ($Mode -eq 'state') { $ip = $ts.Ip; if (-not $ip) { $ip = '-' }; "Owned $ip $($ts.Owner)"; exit 0 }
  Fail "Tailscale here is in use by $($ts.Owner) and answers only that account; the skill does not join it again"
}
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
