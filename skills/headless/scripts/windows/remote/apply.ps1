# apply.ps1 - make the Windows machine what settings.json says, changing
# only what differs; run by apply.sh in the administrator's SSH session. It
# prints one "headless: changed: ..." line per change, and none when run
# again with the same settings.
#
# usage: apply.ps1 -Login ACCOUNT
#   With autoLogin on, the account's password is the first line of standard
#   input; it is checked against the account, kept only as the LSA secret
#   Windows' automatic sign-in reads, and never printed.
param([Parameter(Mandatory = $true)][string]$Login)
. (Join-Path $PSScriptRoot 'common.ps1')

function Changed([string]$What) { [Console]::Out.WriteLine("headless: changed: $What") }

# Set-Reg KEY NAME TYPE VALUE WHAT: set a registry value unless it already
# holds VALUE; say WHAT when it changed.
function Set-Reg([string]$Key, [string]$Name, [string]$Type, $Value, [string]$What) {
  if (-not (Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
  $have = Get-RegValue $Key $Name
  $kind = $null
  if ($null -ne $have) { $kind = (Get-Item $Key).GetValueKind($Name).ToString() }
  if ($null -ne $have -and "$have" -eq "$Value" -and $kind -eq $Type) { return }
  if ($null -ne $have -and $kind -ne $Type) { Remove-ItemProperty -Path $Key -Name $Name }
  New-ItemProperty -Path $Key -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
  Changed $What
}
function Remove-Reg([string]$Key, [string]$Name, [string]$What) {
  if ($null -eq (Get-RegValue $Key $Name)) { return }
  Remove-ItemProperty -Path $Key -Name $Name
  Changed $What
}

# Set-Power SUBGROUP SETTING VALUE WHAT: on AC and on battery, in the active
# power plan.
function Set-Power([string]$Sub, [string]$Setting, [long]$Value, [string]$What) {
  $ac = [Headless.Native]::ReadPower($Sub, $Setting, $true)
  $dc = [Headless.Native]::ReadPower($Sub, $Setting, $false)
  if ($ac -eq -1) { return }
  if ($ac -eq $Value -and ($dc -eq $Value -or $dc -eq -1)) { return }
  powercfg /setacvalueindex SCHEME_CURRENT $Sub $Setting $Value
  if ($LASTEXITCODE -ne 0) { Fail "powercfg could not set $What" }
  powercfg /setdcvalueindex SCHEME_CURRENT $Sub $Setting $Value
  powercfg /setactive SCHEME_CURRENT
  Changed $What
}

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Fail "$Login's SSH session has no administrator rights" }
if ($env:USERNAME -ne $Login) { Fail "signed in as $env:USERNAME, not $Login" }
$s = Read-Settings (Join-Path $HeadlessHome 'config\settings.json') $Login

$password = $null
if ($s.autoLogin) {
  $password = [Console]::In.ReadLine()
  if ([string]::IsNullOrEmpty($password)) { Fail 'automatic sign-in is on, but no password came on standard input' }
  # Checked before anything changes, so a wrong password changes nothing.
  if (-not (Get-LocalUser -Name $Login -ErrorAction SilentlyContinue)) {
    Fail "$Login is not a local account here; automatic sign-in needs a local account"
  }
  if (-not [Headless.Native]::CheckPassword($Login, $password)) {
    Fail "the password in the store does not sign $Login in on this machine; nothing was changed"
  }
}

# --- Host name (Windows takes a new name at the next restart).
$names = Get-ComputerNames
if ($s.hostName -and $s.hostName -ne $names.Pending) {
  Rename-Computer -NewName $s.hostName -Force -WarningAction SilentlyContinue
  Changed "host name $($s.hostName) (from the next restart)"
  $names = Get-ComputerNames
}

# --- Automatic sign-in: Winlogon signs the account in at start-up with the
# password kept as the LSA secret DefaultPassword (never the plain-text
# registry value of the same name).
if ($s.autoLogin) {
  Set-Reg $Winlogon 'DefaultUserName' 'String' $Login "automatic sign-in account $Login"
  Set-Reg $Winlogon 'DefaultDomainName' 'String' $names.Pending "automatic sign-in domain $($names.Pending) (this computer)"
  Remove-Reg $Winlogon 'DefaultPassword' 'plain-text DefaultPassword removed from the registry'
  Remove-Reg $Winlogon 'AutoLogonCount' 'automatic sign-in no longer stops after a count'
  if (-not [Headless.Native]::SecretIs('DefaultPassword', $password)) {
    [Headless.Native]::SetSecret('DefaultPassword', $password)
    Changed 'automatic sign-in password, kept as an LSA secret'
  }
  Set-Reg $Winlogon 'AutoAdminLogon' 'String' '1' 'automatic sign-in on'
  # "Only allow Windows Hello sign-in" turns automatic sign-in off.
  if ($null -ne (Get-RegValue $PasswordLess 'DevicePasswordLessBuildVersion')) {
    Set-Reg $PasswordLess 'DevicePasswordLessBuildVersion' 'DWord' 0 'Windows Hello-only sign-in off (it blocks automatic sign-in)'
  }
} else {
  if ((Get-RegValue $Winlogon 'AutoAdminLogon') -eq '1') {
    Set-Reg $Winlogon 'AutoAdminLogon' 'String' '0' 'automatic sign-in off'
  }
  Remove-Reg $Winlogon 'DefaultPassword' 'plain-text DefaultPassword removed from the registry'
  if ([Headless.Native]::HasSecret('DefaultPassword')) {
    [Headless.Native]::RemoveSecret('DefaultPassword')
    Changed 'automatic sign-in password removed from the LSA secrets'
  }
}
$password = $null

# --- Extras. An extra turned off is no longer managed: its setting stays
# as it is.
$x = $s.extras
if ($x.neverSleep) {
  if ((Get-RegValue $PowerKey 'HibernateEnabled') -ne 0) {
    powercfg /hibernate off
    if ($LASTEXITCODE -ne 0) { Fail 'powercfg could not turn hibernation off' }
    Changed 'hibernation off (and with it fast start-up)'
  }
  Set-Power $SubSleep $StandbyIdle 0 'sleep after: never'
  Set-Power $SubSleep $HibernateIdle 0 'hibernate after: never'
}
if ($x.powerButtonShutsDown) {
  Set-Power $SubButtons $PowerButtonAction 3 'power button: shut down'
}
if ($x.hideSleep) {
  Set-Reg $Flyout 'ShowSleepOption' 'DWord' 0 'Sleep hidden from the power menu'
}
if ($x.updatesOvernight) {
  Set-Reg $UpdateUx 'SmartActiveHoursState' 'DWord' 0 'Windows Update active hours set by hand'
  Set-Reg $UpdateUx 'ActiveHoursStart' 'DWord' $ActiveHoursStart "Windows Update active hours from ${ActiveHoursStart}:00"
  Set-Reg $UpdateUx 'ActiveHoursEnd' 'DWord' $ActiveHoursEnd "Windows Update active hours to ${ActiveHoursEnd}:00"
}

# --- Tailscale: Tailscale's own Windows installer, in unattended mode (it
# runs before anyone signs in). An existing install is kept, and gets the
# same unattended policy the installer would set.
if ($s.tailscale.enable) {
  if (-not (Test-Path $TailscaleExe)) {
    $arch = @{ AMD64 = 'amd64'; ARM64 = 'arm64' }[$env:PROCESSOR_ARCHITECTURE]
    if (-not $arch) { Fail "no Tailscale installer for $env:PROCESSOR_ARCHITECTURE" }
    $msi = Join-Path $HeadlessHome "tailscale-setup-$TailscaleVersion-$arch.msi"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri "https://pkgs.tailscale.com/stable/tailscale-setup-$TailscaleVersion-$arch.msi" -OutFile $msi
    if ((Get-FileHash -Algorithm SHA256 $msi).Hash.ToLower() -ne $TailscaleSha256[$arch]) {
      Remove-Item $msi
      Fail 'the Tailscale installer did not match its pinned SHA-256; nothing was installed'
    }
    $p = Start-Process -FilePath msiexec.exe -Wait -PassThru -ArgumentList '/i', "`"$msi`"", '/quiet', '/norestart', 'TS_UNATTENDEDMODE=always', 'TS_NOLAUNCH=true'
    Remove-Item $msi
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Fail "the Tailscale installer failed (exit code $($p.ExitCode))" }
    Changed "Tailscale $TailscaleVersion installed, unattended"
  }
  Set-Reg 'HKLM:\SOFTWARE\Policies\Tailscale' 'UnattendedMode' 'String' 'always' 'Tailscale runs unattended (before anyone signs in)'
  $svc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
  if (-not $svc) { Fail 'Tailscale is installed but has no Tailscale service' }
  if ($svc.StartType -ne 'Automatic') { Set-Service -Name Tailscale -StartupType Automatic; Changed 'Tailscale service starts at start-up' }
  if ($svc.Status -ne 'Running') { Start-Service -Name Tailscale; Changed 'Tailscale service started' }
}

# --- SSH: your keys, PowerShell as the SSH shell, key-only sign-in.
if (-not (Test-Path $AdminKeys)) { New-Item -ItemType File -Path $AdminKeys | Out-Null }
$have = @(Get-Content $AdminKeys)
foreach ($k in $s.sshKeys) {
  if ($have -notcontains $k) { Add-Content -Path $AdminKeys -Value $k -Encoding Ascii; Changed "SSH key added: $(($k -split ' ')[0]) ...$($k.Substring([Math]::Max(0, $k.Length - 24)))" }
}
if (-not (Test-AdminOnlyAcl $AdminKeys)) {
  icacls $AdminKeys /inheritance:r /grant:r "*${SidAdministrators}:F" "*${SidSystem}:F" | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail 'could not limit administrators_authorized_keys to Administrators and SYSTEM' }
  Changed 'administrators_authorized_keys readable by Administrators and SYSTEM only'
}
Set-Reg 'HKLM:\SOFTWARE\OpenSSH' 'DefaultShell' 'String' $PowerShellExe 'SSH shell: Windows PowerShell'
$sshd = Get-CimInstance Win32_Service -Filter "Name='sshd'"
if (-not $sshd) { Fail 'OpenSSH Server (sshd) is not installed' }
if ($sshd.StartMode -ne 'Auto') { Set-Service -Name sshd -StartupType Automatic; Changed 'OpenSSH Server starts at start-up' }
$sshdExe = ($sshd.PathName -replace '^"([^"]+)".*$', '$1') -replace '^(\S+\.exe).*$', '$1'

# The machine's record of its settings, which verify.ps1 checks against.
New-Item -ItemType Directory -Force -Path $HeadlessHome | Out-Null
$record = Join-Path $HeadlessHome 'settings.json'
$json = $s | ConvertTo-Json -Depth 4
if (-not (Test-Path $record) -or [IO.File]::ReadAllText($record) -ne $json) {
  [IO.File]::WriteAllText($record, $json)
}

$text = ''
if (Test-Path $SshdConfig) { $text = [IO.File]::ReadAllText($SshdConfig) }
$parts = Split-SshdConfig $text
$block = Get-SshdBlock $s
if (($parts.Block -join "`n") -ne ($block -join "`n")) {
  $new = (@($block) + @($parts.Rest)) -join "`r`n"
  $candidate = "$SshdConfig.headless-new"
  [IO.File]::WriteAllText($candidate, $new)
  $t = Invoke-Sshd $sshdExe @('-t', '-f', "`"$candidate`"")
  if (-not $t.Ok) {
    Remove-Item $candidate
    Fail "sshd rejected the new sshd_config, which was not changed: $($t.Err)"
  }
  if (-not (Test-Path "$SshdConfig.before-headless") -and (Test-Path $SshdConfig)) {
    Copy-Item $SshdConfig "$SshdConfig.before-headless"
  }
  Move-Item -Force $candidate $SshdConfig
  if ($s.keyOnlySsh) { Changed 'SSH: key sign-in only, password sign-in off' } else { Changed 'SSH: password sign-in left as sshd_config says' }
  # Restarting sshd keeps sessions that are open, this one included.
  Restart-Service -Name sshd -Force
} elseif ((Get-Service sshd).Status -ne 'Running') {
  Start-Service -Name sshd
  Changed 'OpenSSH Server started'
}
