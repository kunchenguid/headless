# common.ps1 - shared by apply.ps1, verify.ps1 and tailscale.ps1 on the
# Windows machine; dot-sourced, not run. Windows PowerShell 5.1 (every
# Windows 10 and 11, and Windows Server 2016 and newer) runs it; nothing is
# installed for it.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# The Tailscale release apply.ps1 installs, with each installer's SHA-256.
$TailscaleVersion = '1.104.5'
$TailscaleSha256 = @{
  amd64 = '3c41318c83c5d95d0b017b1baa08ba7c99fd5334166122bbb1931e55af99839c'
  arm64 = '609982de4dfe70b67a02e2a93c9c5c1dfa20addceb33a7d3b144f1d34d98f5fc'
}
$TailscaleExe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'

$HeadlessHome = Join-Path $env:ProgramData 'headless'
$SshDir = Join-Path $env:ProgramData 'ssh'
$SshdConfig = Join-Path $SshDir 'sshd_config'
$AdminKeys = Join-Path $SshDir 'administrators_authorized_keys'
$PowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$PasswordLess = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device'
$Flyout = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings'
$UpdateUx = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
$PowerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power'
$ComputerNameKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName'

# Power settings, by GUID (the same in every language).
$SubSleep = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$StandbyIdle = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$HibernateIdle = '9d7815a6-7ee4-497e-8888-515a05f02364'
$SubButtons = '4f971e89-eebd-4455-a8de-9e59040e7347'
$PowerButtonAction = '7648efa3-dd9c-4e3e-b566-50f929386280'

# Active hours for Windows Update (updatesOvernight): it restarts for
# updates only outside them, between 2 and 8 in the morning.
$ActiveHoursStart = 8
$ActiveHoursEnd = 2

# The block apply.ps1 keeps at the top of sshd_config. sshd takes the first
# value it reads for each keyword, so these win over the lines below them.
$BlockBegin = '# headless begin: written by the headless skill (apply.sh rewrites this block)'
$BlockEnd = '# headless end'

$SidAdministrators = 'S-1-5-32-544'
$SidSystem = 'S-1-5-18'

function Fail([string]$Message) {
  [Console]::Error.WriteLine("headless: $Message")
  exit 1
}

# What Windows itself offers for the LSA secret that automatic sign-in reads,
# for checking a password and for reading power settings. The secret never
# comes back to PowerShell: the native side only says whether it matches.
if (-not ('Headless.Native' -as [type])) {
  Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Headless {
  public static class Native {
    [StructLayout(LayoutKind.Sequential)]
    struct LsaString { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    struct LsaObjectAttributes {
      public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public uint Attributes;
      public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService;
    }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr system, ref LsaObjectAttributes attributes, uint access, out IntPtr policy);
    [DllImport("advapi32.dll")] static extern uint LsaStorePrivateData(IntPtr policy, ref LsaString key, IntPtr data);
    [DllImport("advapi32.dll")] static extern uint LsaRetrievePrivateData(IntPtr policy, ref LsaString key, out IntPtr data);
    [DllImport("advapi32.dll")] static extern uint LsaFreeMemory(IntPtr buffer);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr policy);
    [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint status);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool LogonUser(string user, string domain, string password, int type, int provider, out IntPtr token);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr memory);
    [DllImport("powrprof.dll")] static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr scheme);
    [DllImport("powrprof.dll")] static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);
    [DllImport("powrprof.dll")] static extern uint PowerReadDCValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint value);

    const uint StatusNotFound = 0xC0000034;

    static LsaString Make(string s) {
      LsaString u = new LsaString();
      u.Buffer = Marshal.StringToHGlobalUni(s);
      u.Length = (ushort)(s.Length * 2);
      u.MaximumLength = (ushort)(s.Length * 2 + 2);
      return u;
    }
    static void Wipe(LsaString u) {
      if (u.Buffer == IntPtr.Zero) return;
      for (int i = 0; i < u.MaximumLength; i++) Marshal.WriteByte(u.Buffer, i, 0);
      Marshal.FreeHGlobal(u.Buffer);
    }
    static IntPtr Open() {
      LsaObjectAttributes a = new LsaObjectAttributes();
      a.Length = Marshal.SizeOf(typeof(LsaObjectAttributes));
      IntPtr policy;
      uint status = LsaOpenPolicy(IntPtr.Zero, ref a, 0x00F0FFF, out policy);
      if (status != 0) throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status));
      return policy;
    }

    // Whether the LSA secret name exists (even holding an empty string).
    // Its own method because PowerShell passes $null to a string parameter
    // as an empty string.
    public static bool HasSecret(string name) {
      IntPtr policy = Open();
      LsaString key = Make(name);
      try {
        IntPtr data;
        uint status = LsaRetrievePrivateData(policy, ref key, out data);
        if (status == StatusNotFound) return false;
        if (status != 0) throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status));
        if (data != IntPtr.Zero) LsaFreeMemory(data);
        return true;
      } finally { Wipe(key); LsaClose(policy); }
    }

    // Whether the LSA secret name holds exactly value (never empty).
    public static bool SecretIs(string name, string value) {
      if (string.IsNullOrEmpty(value)) throw new ArgumentException("empty value");
      IntPtr policy = Open();
      LsaString key = Make(name);
      try {
        IntPtr data;
        uint status = LsaRetrievePrivateData(policy, ref key, out data);
        if (status == StatusNotFound) return false;
        if (status != 0) throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status));
        if (data == IntPtr.Zero) return false;
        try {
          LsaString s = (LsaString)Marshal.PtrToStructure(data, typeof(LsaString));
          if (s.Length != value.Length * 2) return false;
          bool same = true;
          for (int i = 0; i < value.Length; i++)
            if ((char)Marshal.ReadInt16(s.Buffer, i * 2) != value[i]) same = false;
          return same;
        } finally { LsaFreeMemory(data); }
      } finally { Wipe(key); LsaClose(policy); }
    }

    // Store value (never empty) as the LSA secret name.
    public static void SetSecret(string name, string value) {
      if (string.IsNullOrEmpty(value)) throw new ArgumentException("empty value");
      IntPtr policy = Open();
      LsaString key = Make(name);
      LsaString data = Make(value);
      data.MaximumLength = data.Length;
      IntPtr p = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(LsaString)));
      try {
        Marshal.StructureToPtr(data, p, false);
        uint status = LsaStorePrivateData(policy, ref key, p);
        if (status != 0) throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status));
      } finally {
        Marshal.FreeHGlobal(p);
        data.MaximumLength = (ushort)(data.Length + 2);
        Wipe(data);
        Wipe(key);
        LsaClose(policy);
      }
    }

    // Delete the LSA secret name; nothing to do when there is none.
    public static void RemoveSecret(string name) {
      IntPtr policy = Open();
      LsaString key = Make(name);
      try {
        uint status = LsaStorePrivateData(policy, ref key, IntPtr.Zero);
        if (status != 0 && status != StatusNotFound)
          throw new System.ComponentModel.Win32Exception(LsaNtStatusToWinError(status));
      } finally { Wipe(key); LsaClose(policy); }
    }

    // Whether user (a local account) signs in with password.
    public static bool CheckPassword(string user, string password) {
      IntPtr token;
      if (!LogonUser(user, ".", password, 3, 0, out token)) return false;
      CloseHandle(token);
      return true;
    }

    // The active power plan's value of a setting, on AC (ac) or battery;
    // -1 when this machine has no such setting.
    public static long ReadPower(string subgroup, string setting, bool ac) {
      IntPtr p;
      if (PowerGetActiveScheme(IntPtr.Zero, out p) != 0) return -1;
      try {
        Guid scheme = (Guid)Marshal.PtrToStructure(p, typeof(Guid));
        Guid sub = new Guid(subgroup), set = new Guid(setting);
        uint v;
        uint r = ac ? PowerReadACValueIndex(IntPtr.Zero, ref scheme, ref sub, ref set, out v)
                    : PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref sub, ref set, out v);
        return r == 0 ? (long)v : -1;
      } finally { LocalFree(p); }
    }
  }
}
'@
}

# Read-Settings PATH LOGIN: settings.json, checked, with every default
# filled in. It stops on anything it does not expect.
function Read-Settings([string]$Path, [string]$Login) {
  if (-not (Test-Path $Path)) { Fail "no settings.json at $Path" }
  try { $j = [IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { Fail "settings.json is not valid JSON" }
  function Bool($Value, [bool]$Default, [string]$Name) {
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return $Value }
    Fail "settings.json: $Name must be true or false"
  }
  $s = [ordered]@{}
  $s.user = [string]$j.user
  # Same rule as LOGIN_PATTERN in windows/lib.sh; -notmatch and -ne ignore
  # case, as Windows does for account names.
  if ($s.user -notmatch '^[A-Za-z0-9_][A-Za-z0-9._-]{0,19}$') { Fail 'settings.json: user must be a Windows account name of up to 20 letters, digits, dots, dashes and underscores' }
  if ($s.user -ne $Login) { Fail "settings.json names the user $($s.user), but headless.env signs in as $Login" }
  $s.hostName = $j.hostName
  if ($null -ne $s.hostName -and ([string]$s.hostName) -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
    Fail 'settings.json: hostName must be 1 to 15 letters, digits and dashes on Windows'
  }
  $keys = @()
  foreach ($k in @($j.sshKeys)) {
    if ($null -eq $k) { continue }
    if ([string]$k -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) [A-Za-z0-9+/=]+( [ -~]*)?$') {
      Fail 'settings.json: an sshKeys entry is not a plain public key line'
    }
    $keys += [string]$k
  }
  $s.sshKeys = $keys
  $s.keyOnlySsh = Bool $j.keyOnlySsh $true 'keyOnlySsh'
  $s.autoLogin = Bool $j.autoLogin $true 'autoLogin'
  $s.tailscale = [ordered]@{ enable = (Bool $j.tailscale.enable $false 'tailscale.enable') }
  $e = $j.extras
  $s.extras = [ordered]@{}
  foreach ($n in 'neverSleep', 'powerButtonShutsDown', 'hideSleep', 'updatesOvernight') {
    $v = $null
    if ($null -ne $e) { $v = $e.$n }
    $s.extras[$n] = Bool $v $true "extras.$n"
  }
  if ($null -ne $e) {
    foreach ($p in $e.PSObject.Properties) {
      if ($s.extras.Keys -notcontains $p.Name) { Fail "settings.json: unknown extra '$($p.Name)' (Windows has $($s.extras.Keys -join ', '))" }
    }
  }
  return $s
}

# The block apply.ps1 writes at the top of sshd_config, as lines.
function Get-SshdBlock($Settings) {
  $l = @($BlockBegin)
  if ($Settings.keyOnlySsh) { $l += 'PasswordAuthentication no', 'KbdInteractiveAuthentication no' }
  $l += 'ClientAliveInterval 60', 'ClientAliveCountMax 3', $BlockEnd
  return $l
}

# Split-SshdConfig TEXT: the current headless block (lines, or empty) and
# the rest of the file.
function Split-SshdConfig([string]$Text) {
  $lines = @($Text -split "`r?`n")
  $b = [Array]::IndexOf($lines, $BlockBegin)
  $e = [Array]::IndexOf($lines, $BlockEnd)
  if ($b -lt 0 -or $e -lt $b) { return @{ Block = @(); Rest = $lines } }
  $rest = @()
  if ($b -gt 0) { $rest += $lines[0..($b - 1)] }
  if ($e -lt $lines.Count - 1) { $rest += $lines[($e + 1)..($lines.Count - 1)] }
  return @{ Block = @($lines[$b..$e]); Rest = $rest }
}

# Whether PATH is readable by Administrators and SYSTEM only, as Windows'
# OpenSSH requires of administrators_authorized_keys.
function Test-AdminOnlyAcl([string]$Path) {
  $acl = Get-Acl $Path
  if (-not $acl.AreAccessRulesProtected) { return $false }
  foreach ($r in $acl.Access) {
    $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
    if ($sid -ne $SidAdministrators -and $sid -ne $SidSystem) { return $false }
  }
  return $true
}

function Get-RegValue([string]$Key, [string]$Name) {
  $p = Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue
  if ($null -eq $p) { return $null }
  return $p.$Name
}

# The name the computer has now, and the one it will have after a restart.
function Get-ComputerNames {
  return @{
    Active = (Get-RegValue "$ComputerNameKey\ActiveComputerName" 'ComputerName')
    Pending = (Get-RegValue "$ComputerNameKey\ComputerName" 'ComputerName')
  }
}

# Invoke-Sshd EXE ARGS: run sshd (-t or -T) with its output in files:
# piped, Windows' sshd waits on a config it rejects, and Windows PowerShell
# stops at the first error line. Ok when it exits 0 within a minute; Out
# its output lines, Err its messages.
function Invoke-Sshd([string]$Exe, [string[]]$Arguments) {
  $log = Join-Path $HeadlessHome ('sshd-' + [guid]::NewGuid().ToString('N'))
  try {
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -NoNewWindow -PassThru -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err"
    $null = $p.Handle
    $ok = $p.WaitForExit(60000) -and $p.ExitCode -eq 0
    if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() }
    return @{
      Ok = $ok
      Out = @([IO.File]::ReadAllLines("$log.out"))
      Err = ([IO.File]::ReadAllText("$log.err") -replace '\\\\', '\').Trim()
    }
  } finally { Remove-Item -Force "$log.out", "$log.err" -ErrorAction SilentlyContinue }
}

# Tailscale's state: BackendState (Running when connected) and its IPv4.
function Get-TailscaleState {
  if (-not (Test-Path $TailscaleExe)) { return $null }
  # Windows PowerShell stops at a redirected error line under 'Stop'.
  $ErrorActionPreference = 'Continue'
  $out = @(& $TailscaleExe status --json 2>&1)
  $err = ($out | Where-Object { $_ -is [Management.Automation.ErrorRecord] }) -join ' '
  $st = $null
  try { $st = ($out | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] }) -join "`n" | ConvertFrom-Json } catch { }
  # Such as "Tailscale already in use by" another account signed in at the PC.
  if (-not $st) { return @{ State = 'unknown'; Ip = ''; AuthUrl = ''; Error = "$err" } }
  $ip = ''
  if ($st.Self -and $st.Self.TailscaleIPs) { $ip = @($st.Self.TailscaleIPs | Where-Object { $_ -match '^\d+\.' })[0] }
  return @{ State = [string]$st.BackendState; Ip = [string]$ip; AuthUrl = [string]$st.AuthURL }
}
