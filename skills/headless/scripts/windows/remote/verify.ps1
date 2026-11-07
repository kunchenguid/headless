# verify.ps1 - read every headless setting back on the Windows machine and
# compare it with the machine's record of its settings (written by
# apply.ps1). Prints one line per setting, "ok", "FAIL" or "n/a"; verify.sh
# counts the FAIL lines. Needs no password and changes nothing.
param()
. (Join-Path $PSScriptRoot 'common.ps1')
$ErrorActionPreference = 'Continue'

function Check([bool]$Ok, [string]$What) {
  if ($Ok) { [Console]::Out.WriteLine("ok    $What") } else { [Console]::Out.WriteLine("FAIL  $What") }
}
function NotApplicable([string]$What) { [Console]::Out.WriteLine("n/a   $What") }

$record = Join-Path $HeadlessHome 'settings.json'
if (-not (Test-Path $record)) { Check $false 'the machine has a record of its settings (run apply.sh)'; exit 0 }
$s = Read-Settings $record $env:USERNAME
$x = $s.extras

# --- SSH
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
Check ($sshd -and $sshd.Status -eq 'Running' -and $sshd.StartType -eq 'Automatic') 'OpenSSH Server running, starts at start-up'
Check ((Get-RegValue 'HKLM:\SOFTWARE\OpenSSH' 'DefaultShell') -eq $PowerShellExe) 'SSH shell is Windows PowerShell'
$keys = @()
if (Test-Path $AdminKeys) { $keys = @(Get-Content $AdminKeys) }
foreach ($k in $s.sshKeys) { Check ($keys -contains $k) "SSH key $(($k -split ' ')[0]) ...$($k.Substring([Math]::Max(0, $k.Length - 24))) may sign in" }
Check ((Test-Path $AdminKeys) -and (Test-AdminOnlyAcl $AdminKeys)) 'administrators_authorized_keys readable by Administrators and SYSTEM only'
$text = ''
if (Test-Path $SshdConfig) { $text = [IO.File]::ReadAllText($SshdConfig) }
$block = (Split-SshdConfig $text).Block
Check (($block -join "`n") -eq ((Get-SshdBlock $s) -join "`n")) 'sshd_config starts with the headless block (sessions whose other end is gone end after about 3 minutes)'
if ($s.keyOnlySsh) {
  $exe = (Get-CimInstance Win32_Service -Filter "Name='sshd'").PathName -replace '^"([^"]+)".*$', '$1' -replace '^(\S+\.exe).*$', '$1'
  $t = & $exe -T 2> $null
  if ($LASTEXITCODE -eq 0 -and $t) {
    Check (($t -contains 'passwordauthentication no') -and ($t -contains 'kbdinteractiveauthentication no')) 'sshd: password sign-in off (sshd -T)'
  } else {
    NotApplicable 'sshd -T could not be read; verify.sh checks the server refuses a password'
  }
}

# --- Host name
$names = Get-ComputerNames
if ($s.hostName) {
  if ($names.Active -eq $s.hostName) { Check $true "host name $($s.hostName)" }
  elseif ($names.Pending -eq $s.hostName) { NotApplicable "host name $($s.hostName) takes effect at the next restart (restart.sh)" }
  else { Check $false "host name $($s.hostName) (it is $($names.Active))" }
}

# --- Automatic sign-in
$auto = Get-RegValue $Winlogon 'AutoAdminLogon'
$plain = $null -ne (Get-RegValue $Winlogon 'DefaultPassword')
$secret = [Headless.Native]::HasSecret('DefaultPassword')
if ($s.autoLogin) {
  Check ($auto -eq '1') 'automatic sign-in on'
  Check ((Get-RegValue $Winlogon 'DefaultUserName') -eq $s.user) "automatic sign-in account $($s.user)"
  Check ((Get-RegValue $Winlogon 'DefaultDomainName') -eq $names.Pending) 'automatic sign-in domain is this computer'
  Check $secret 'automatic sign-in password kept as an LSA secret'
  Check (-not $plain) 'no plain-text DefaultPassword in the registry'
  Check ($null -eq (Get-RegValue $Winlogon 'AutoLogonCount')) 'automatic sign-in has no count that ends it'
  Check ((Get-RegValue $PasswordLess 'DevicePasswordLessBuildVersion') -ne 2) 'Windows Hello-only sign-in off'
} else {
  Check ($auto -ne '1') 'automatic sign-in off'
  Check (-not $secret -and -not $plain) 'no automatic sign-in password stored'
}

# --- Extras
if ($x.neverSleep) {
  Check ((Get-RegValue $PowerKey 'HibernateEnabled') -eq 0) 'hibernation off'
  foreach ($p in @(@($StandbyIdle, 'sleep after: never'), @($HibernateIdle, 'hibernate after: never'))) {
    $ac = [Headless.Native]::ReadPower($SubSleep, $p[0], $true)
    $dc = [Headless.Native]::ReadPower($SubSleep, $p[0], $false)
    if ($ac -eq -1) { NotApplicable "$($p[1]) (this machine has no such setting)" }
    else { Check ($ac -eq 0 -and ($dc -eq 0 -or $dc -eq -1)) $p[1] }
  }
} else { NotApplicable 'neverSleep is off: sleep settings are not managed' }
if ($x.powerButtonShutsDown) {
  $ac = [Headless.Native]::ReadPower($SubButtons, $PowerButtonAction, $true)
  $dc = [Headless.Native]::ReadPower($SubButtons, $PowerButtonAction, $false)
  if ($ac -eq -1) { NotApplicable 'power button (this machine has no such setting)' }
  else { Check ($ac -eq 3 -and ($dc -eq 3 -or $dc -eq -1)) 'power button: shut down' }
} else { NotApplicable 'powerButtonShutsDown is off: the power button is not managed' }
if ($x.hideSleep) {
  Check ((Get-RegValue $Flyout 'ShowSleepOption') -eq 0) 'Sleep hidden from the power menu'
} else { NotApplicable 'hideSleep is off: the power menu is not managed' }
if ($x.updatesOvernight) {
  Check ((Get-RegValue $UpdateUx 'SmartActiveHoursState') -eq 0 -and (Get-RegValue $UpdateUx 'ActiveHoursStart') -eq $ActiveHoursStart -and (Get-RegValue $UpdateUx 'ActiveHoursEnd') -eq $ActiveHoursEnd) `
    "Windows Update active hours ${ActiveHoursStart}:00 to ${ActiveHoursEnd}:00 (update restarts at night)"
} else { NotApplicable 'updatesOvernight is off: active hours are not managed' }

# --- Tailscale
if ($s.tailscale.enable) {
  $ts = Get-TailscaleState
  if ($null -eq $ts) { Check $false 'Tailscale installed' }
  else {
    $svc = Get-Service Tailscale -ErrorAction SilentlyContinue
    Check ($svc -and $svc.Status -eq 'Running' -and $svc.StartType -eq 'Automatic') 'Tailscale service running, starts at start-up'
    Check ((Get-RegValue 'HKLM:\SOFTWARE\Policies\Tailscale' 'UnattendedMode') -eq 'always') 'Tailscale runs unattended (before anyone signs in)'
    if ($ts.State -eq 'Running') { Check $true "Tailscale connected: $($ts.Ip)" }
    else { Check $false "Tailscale connected (it is $($ts.State); run tailscale.sh)" }
  }
}
