# machine.ps1 - your own additions to this Windows machine's setup.
#
# apply.sh runs this file on the machine after the headless settings, every
# time, in your administrator's SSH session (Windows PowerShell 5.1, with
# full rights). Write it so a second run changes nothing: check before you
# change, as in the example below. The whole config folder is copied to
# C:\ProgramData\headless\config first, so this file can use files beside
# it through $PSScriptRoot.
#
# Example: keep the Windows time service starting automatically.
#   if ((Get-Service W32Time).StartType -ne 'Automatic') {
#     Set-Service W32Time -StartupType Automatic
#     'headless: changed: Windows time service starts at start-up'
#   }
$ErrorActionPreference = 'Stop'
