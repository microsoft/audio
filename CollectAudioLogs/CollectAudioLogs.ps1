# Copyright (c) Microsoft Corporation. All rights reserved.

# Script requires admin privileges to run
Import-Module "$PSScriptRoot\RegistryToXml.psm1";
Import-Module "$PSScriptRoot\tttraceall.psm1";

# need this for [System.IO.Compression.ZipFile]::CreateFromDirectory to work on PowerShell 5
Add-Type -AssemblyName System.IO.Compression.FileSystem;

$system32 = "${env:windir}\system32";
# check for WOW64
if ($env:PROCESSOR_ARCHITEW6432 -ne $null)
{
    Write-Host "WARNING: script is running WOW64";
    $system32 = "${env:windir}\sysnative";
}

# Create a directory for all output files
$outDirName = "$($env:COMPUTERNAME)_$(Get-Date -Format yyyyMMdd-HHmmss)";
Write-Host "Creating temporary directory $env:TEMP\$outDirName.";
$outDir = New-Item -Path $env:TEMP -ItemType Directory -Name $outDirName;

# Ask the user if they'd like to take a repro trace
do 
{
    $reproResponse = Read-Host "Take a repro trace? (y/n)";
}
while (($reproResponse.Trim().ToLower())[0] -ne 'y' -and ($reproResponse.Trim().ToLower())[0] -ne 'n');

if (($reproResponse.Trim().ToLower())[0] -eq 'y')
{
    # Packaged wprp file
    $wprp = "$PSScriptRoot\audio-glitches-manual.wprp";

    # Profile in wprp file to use for repro trace
    $profile = 'audio-glitches-manual';

    $svchostConfigChange = $false
    $rundllConfigChange = $false
    $adgConfigChange = $false
    $tracingStarted = $false

    # prompt and optionally start the time travel traces
    # before starting etw tracing, so that the potential
    # service restarts are not included in the etw logs
    StartTTTracing -OutFolder $outDir -SvchostConfigChange ([ref]$svchostConfigChange) -RundllConfigChange ([ref]$rundllConfigChange) -AdgConfigChange ([ref]$adgConfigChange) -TracingStarted ([ref]$tracingStarted)

    # Start repro
    $wprExe = "$system32\wpr.exe";
    $wprStartArgs = "-start `"$wprp!$profile`"";
    Start-Process $wprExe -ArgumentList $wprStartArgs -NoNewWindow -Wait;

    # Wait for user to press enter before continuing
    Write-Host "Tracing started, please reproduce your scenario.";
    $null = Read-Host "Press Enter to stop tracing";

    # Stop repro
    Write-Host 'Writing repro trace to disk.';
    $wprStopArgs = "-stop `"$outDir\Repro.etl`"";
    Start-Process $wprExe -ArgumentList $wprStopArgs -NoNewWindow -Wait;

    # stop time travel traces, if they were started
    # do this after stopping etw's so we don't have the potential
    # service restarts included in the logs
    StopTTTracing -OutFolder $outDir -SvchostConfigChange ([ref]$svchostConfigChange) -RundllConfigChange ([ref]$rundllConfigChange) -AdgConfigChange ([ref]$adgConfigChange) -TracingStarted ([ref]$tracingStarted)
}

# Ask the user if they'd like to gather diagnostic information
do 
{
    $diagResponse = Read-Host "Gather system information (this can take a few minutes)? (y/n)";
}
while (($diagResponse.Trim().ToLower())[0] -ne 'y' -and ($diagResponse.Trim().ToLower())[0] -ne 'n');

if (($diagResponse.Trim().ToLower())[0] -eq 'y')
{
    # Dump registry keys
    @(
        ([Microsoft.Win32.RegistryHive]::CurrentUser,  'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore', 'CapabilityAccessManager-ConsentStore-HKCU.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SOFTWARE\Microsoft\SQMClient', 'SQMClient.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Audio', 'CurrentVersionAudio.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore', 'CapabilityAccessManager-ConsentStore-HKLM.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices', 'MMDevices.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}', 'MediaDeviceConfig.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SYSTEM\CurrentControlSet\Control\Class\{c166523c-fe0c-4a94-a586-f1a80cfbbf3e}', 'AudioEndpointClass.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SYSTEM\CurrentControlSet\Control\DeviceClasses\{2EEF81BE-33FA-4800-9670-1CD474972C3F}', 'DeviceInterfaceAudioCapture.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SYSTEM\CurrentControlSet\Control\DeviceClasses\{6994AD04-93EF-11D0-A3CC-00A0C9223196}', 'MediaDeviceTopography.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SYSTEM\CurrentControlSet\Control\DeviceClasses\{E6327CAD-DCEC-4949-AE8A-991E976A79D2}', 'DeviceInterfaceAudioRender.xml'),
        ([Microsoft.Win32.RegistryHive]::LocalMachine, 'SYSTEM\CurrentControlSet\Services\ksthunk', 'ksthunk.xml')
    ) | ForEach-Object {
        $hive = $_[0];
        $subkey = $_[1];
        $file = $_[2];
        Write-Host "Dumping registry from $hive\$subkey.";
        $xml = Get-RegKeyQueryXml -hive $hive -subkey $subkey;
        $xml.Save("$outDir\$file");
    }

    # Copy files
    @(
        ("$system32\winevt\logs", "Application.evtx", "ApplicationLog"),
        ("$env:windir\INF", "setupapi*.log", "SetupapiLogs"),
        ("$env:windir", "setup*.log", "WindowsSetupLogs"),
        ("$env:windir\Panther", "setup*.log", "PantherLogs"),
        ("$system32\winevt\logs", "Microsoft-Windows-UserPnp%4DeviceInstall.evtx", "PnpUserEventLog"),
        ("$system32\winevt\logs", "Microsoft-Windows-Kernel-PnP%4Configuration.evtx", "PnpKernelEventLog"),
        ("$system32\winevt\logs", "System.evtx", "SystemLog")
    ) | ForEach-Object {
        Write-Host "Copying $($_[1]) from $($_[0]).";
        $dir = New-Item -Path $outDir -ItemType Directory -Name $_[2];
        Copy-Item -Path "$($_[0])\$($_[1])" -Destination $dir;
    }

    # Run command lines
    @(
        ("ddodiag", "$system32\ddodiag.exe", "-o `"$outDir\ddodiag.xml`""),
        ("dispdiag", "$system32\dispdiag.exe", "-out `"$outDir\dispdiag.dat`""),
        ("dxdiag (text)", "$system32\dxdiag.exe", "/t `"$outDir\dxdiag.txt`""),
        ("dxdiag (XML)", "$system32\dxdiag.exe", "/x `"$outDir\dxdiag.xml`""),
        ("pnputil", "$system32\pnputil.exe", "/export-pnpstate `"$outDir\pnpstate.pnp`" /force")
    ) | ForEach-Object {
        
        Write-Host "Running $($_[0]).";
        $proc = Start-Process $_[1] -ArgumentList $_[2] -NoNewWindow -PassThru;
        $timeout = 60; # seconds
        $proc | Wait-Process -TimeoutSec $timeout -ErrorAction Ignore;
        if (!$proc.HasExited)
        {
            Write-Host "$($_[0]) took longer than $timeout seconds, skipping.";
            taskkill /T /F /PID $proc.ID;
        }
    }
}

if (($reproResponse.Trim().ToLower())[0] -eq 'y' -or ($diagResponse.Trim().ToLower())[0] -eq 'y')
{
    # Logs should exist

    # Zip logs
    $logLoc = "$PSScriptRoot\${outDirName}.zip";
    Write-Host "Zipping logs...";
    [System.IO.Compression.ZipFile]::CreateFromDirectory($outDir, $logLoc);

    # Delete temporary directory
    Write-Host "Deleting temporary directory $outDir.";
    Remove-Item -Path $outDir -Recurse;

    # Write log location to console
    Write-Host '';
    Write-Host "Logs are located at $logLoc";
    Write-Host '';
}
else
{
    # No logs were gathered
    Write-Host "No logs gathered."

    # Delete temporary directory
    Write-Host "Deleting temporary directory $outDir.";
    Remove-Item -Path $outDir;
}


# SIG # Begin signature block
# MIIoLAYJKoZIhvcNAQcCoIIoHTCCKBkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA9rfNXE2OhMaiL
# skXUl0/kD+6XFDEqKtnHuZqPhIRXF6CCDXYwggX0MIID3KADAgECAhMzAAADTrU8
# esGEb+srAAAAAANOMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjMwMzE2MTg0MzI5WhcNMjQwMzE0MTg0MzI5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDdCKiNI6IBFWuvJUmf6WdOJqZmIwYs5G7AJD5UbcL6tsC+EBPDbr36pFGo1bsU
# p53nRyFYnncoMg8FK0d8jLlw0lgexDDr7gicf2zOBFWqfv/nSLwzJFNP5W03DF/1
# 1oZ12rSFqGlm+O46cRjTDFBpMRCZZGddZlRBjivby0eI1VgTD1TvAdfBYQe82fhm
# WQkYR/lWmAK+vW/1+bO7jHaxXTNCxLIBW07F8PBjUcwFxxyfbe2mHB4h1L4U0Ofa
# +HX/aREQ7SqYZz59sXM2ySOfvYyIjnqSO80NGBaz5DvzIG88J0+BNhOu2jl6Dfcq
# jYQs1H/PMSQIK6E7lXDXSpXzAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUnMc7Zn/ukKBsBiWkwdNfsN5pdwAw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMDUxNjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAD21v9pHoLdBSNlFAjmk
# mx4XxOZAPsVxxXbDyQv1+kGDe9XpgBnT1lXnx7JDpFMKBwAyIwdInmvhK9pGBa31
# TyeL3p7R2s0L8SABPPRJHAEk4NHpBXxHjm4TKjezAbSqqbgsy10Y7KApy+9UrKa2
# kGmsuASsk95PVm5vem7OmTs42vm0BJUU+JPQLg8Y/sdj3TtSfLYYZAaJwTAIgi7d
# hzn5hatLo7Dhz+4T+MrFd+6LUa2U3zr97QwzDthx+RP9/RZnur4inzSQsG5DCVIM
# pA1l2NWEA3KAca0tI2l6hQNYsaKL1kefdfHCrPxEry8onJjyGGv9YKoLv6AOO7Oh
# JEmbQlz/xksYG2N/JSOJ+QqYpGTEuYFYVWain7He6jgb41JbpOGKDdE/b+V2q/gX
# UgFe2gdwTpCDsvh8SMRoq1/BNXcr7iTAU38Vgr83iVtPYmFhZOVM0ULp/kKTVoir
# IpP2KCxT4OekOctt8grYnhJ16QMjmMv5o53hjNFXOxigkQWYzUO+6w50g0FAeFa8
# 5ugCCB6lXEk21FFB1FdIHpjSQf+LP/W2OV/HfhC3uTPgKbRtXo83TZYEudooyZ/A
# Vu08sibZ3MkGOJORLERNwKm2G7oqdOv4Qj8Z0JrGgMzj46NFKAxkLSpE5oHQYP1H
# tPx1lPfD7iNSbJsP6LiUHXH1MIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGgwwghoIAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAANOtTx6wYRv6ysAAAAAA04wDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIDgVXh4Z6PvozFLSrAJijjdp
# QYM/GprJ5VWZS1U/UBqJMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQDRKB5ieVl2+CNqXBuRHd3qCs/SsyhKxcMOiaZRKJMS6+LPET5RKxET
# zS4g4UHn/YAC1ZdK+m74CkW1puLHSyvVdDiT3BwrcqWD0eCNpd3hNxqlTzUx2Q37
# XdEkn+WVCvEVL7x9rXOCOH6/jZI+LiThQdTPKFesNVcKuw92Lke+99wUB1XQ2FX+
# 1DD8L85FJyxQNuCusyUc/IMe73X5iZ9n5jDMi6jtH2gUKGxZMxIf2qGI+OZBYh6U
# xtoq3R0X9U74L8VJbo4QKNtgzzMRJt2CpnMglWhCzxIWfdhNMvonK1wDtXqib+gC
# 1mtdmxlH4FTOdT7Lr9glskR/hbC6lJ/NoYIXlDCCF5AGCisGAQQBgjcDAwExgheA
# MIIXfAYJKoZIhvcNAQcCoIIXbTCCF2kCAQMxDzANBglghkgBZQMEAgEFADCCAVIG
# CyqGSIb3DQEJEAEEoIIBQQSCAT0wggE5AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEICxweZiEZQ2AWAYL1e1u+ET7ekwcM6Zb/SatnL1ZXgLTAgZlKIbP
# pEkYEzIwMjMxMTAxMTc0MDA1LjIyN1owBIACAfSggdGkgc4wgcsxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBB
# bWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo4NjAz
# LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZaCCEeowggcgMIIFCKADAgECAhMzAAAB15sNHlcujFGOAAEAAAHXMA0GCSqGSIb3
# DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIzMDUyNTE5
# MTIzN1oXDTI0MDIwMTE5MTIzN1owgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlv
# bnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo4NjAzLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAMSsYKQ3Zf9S+40Jx+XTJUE2j4sgjLMbsDXRfmRW
# Aaen2zyZ/hpmy6Rm7mu8uzs2po0TFzCc+4chZ2nqSzCNrVjD1LFNf4TSV6r5YG5w
# hEpZ1wy6YgMGAsTQRv/f8Fj3lm1PVeyedq0EVmGvS4uQOJP0eCtFvXbaybv9iTIy
# KAWRPQm6iJI9egsvvBpQT214j1A6SiOqNGVwgLhhU1j7ZQgEzlCiso1o53P+yj5M
# gXqbPFfmfLZT+j+IwVVN+/CbhPyD9irHDJ76U6Zr0or3y/q/B7+KLvZMxNVbApcV
# 1c7Kw/0aKhxe3fxy4/1zxoTV4fergV0ZOAo53Ssb7GEKCxEXwaotPuTnxWlCcny7
# 7KNFbouia3lFyuimB/0Qfx7h+gNShTJTlDuI+DA4nFiGgrFGMZmW2EOanl7H7pTr
# O/3mt33vfrrykakKS7QgHjcv8FPMxwMBXj/G7pF9xUXBqs3/Imrmp9nIyykfmBxp
# MJUCi5eRBNzwvC1/G2AjPneoxJVH1z2CRKfEzlzW0eCIxfcPYYGdBqf3m3L4J1Ng
# ACGOAFNzKP0/s4YQyGveXJpnGOveCmzpmajjtU5Mjy2xJgeEe0PwGkGiDf0vl7j+
# UMmD86risawUpLExe4hFnUTTx2Zfrtczuqa+bbs7zTgKESZv4I5HxZvjowUQTPra
# O77FAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUrqfAu/1ZAvc0jEQnI+4kxnowjY0w
# HwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKg
# UIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
# XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9j
# ZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQw
# DAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
# BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAFIF3dQn4iy90wJf4rvGodrlQG1ULUJp
# dm8dF36y1bSVcD91M2d4JbRMWsGgljn1v1+dtOi49F5qS7aXdfluaGxqjoMJFW6p
# yaFU8BnJJcZ6hV+PnZwsaLJksTDpNDO7oP76+M04aZKJs7QoT0Z2/yFARHHlEbQq
# CtOaTxyR4LVVSq55RAcpUIRKpMNQMPx1dMtYKaboeqZBfr/6AoNJeCDClzvmGLYB
# spKji26UzBN9cl0Z3CuyIeOTPyfMhb9nc+cyAYVTvoq7NgVXRfIf0NNL8M87zpEu
# 1CMDlmVUbKZM99OfDuTGiIsk3/KW4wciQdLOlom8KKpf4OfVAZEQSc0hl5F6S8ui
# 6uo9EQg5ObVslEnTrlz1hftsnSdo+LHObnLxjYH5gggQCLiNSto6HegTtrgm8hbc
# SDeg2o/uqGl3vEwvGrZacz5T1upZN5PhUKikCFe7a4ZB7F0urttZ1xjDIQUOFLhn
# 03S7DeHpuMHtLgxf3ql9hIRXQwoUY4puZ8JRLtZ6aS4WpnLSg0c8/H5x901h5IXp
# uE48d2yujURV3fNYiR0PUbmQQM+cRC0Vqu0zwf5u/nNSEBQmzyovO4UB0FlAu54P
# 1dl7KeNArAR4DPrfEBMgKHy05QzbMyBISFUvwebjlIHp+h6zgFMLRjxJlai/chqG
# 2/DIcVtSqzViMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+
# F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU
# 88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqY
# O7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzp
# cGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0Xn
# Rm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1
# zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZN
# N3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLR
# vWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTY
# uVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUX
# k8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB
# 2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKR
# PEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0g
# BFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQM
# MAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQ
# W9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNv
# bS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBa
# BggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqG
# SIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOX
# PTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6c
# qYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/z
# jj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz
# /AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyR
# gNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdU
# bZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo
# 3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4K
# u+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10Cga
# iQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9
# vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGC
# A00wggI1AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODYwMy0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMV
# ADFb26LMbeERjz24va675f6Yb+t1oIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDo7Ln1MCIYDzIwMjMxMTAxMTE1
# MDEzWhgPMjAyMzExMDIxMTUwMTNaMHQwOgYKKwYBBAGEWQoEATEsMCowCgIFAOjs
# ufUCAQAwBwIBAAICKEEwBwIBAAICEsQwCgIFAOjuC3UCAQAwNgYKKwYBBAGEWQoE
# AjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkq
# hkiG9w0BAQsFAAOCAQEAD1Y04got5hg22PMiaqS1bjUnoybOJVRDp9I9Y433/jMr
# t6knoabEOKebjflrPTGXP3eaP3G/SoU4ajSD5NOgGZVks5m5JBmMKkrff3p7JhxC
# JNWfJ4rKqwRaGMhQIGLQ2GcMs9Xx/MVgabk3AVphvEskd7Ga5vtgs7XD3dTfXefM
# fvsrA3KmQe71jj81smGUVchlt1AHXsc/ngWStCVbata0fVSuszugzKcRfZ7Wr3wL
# w/0x9j2gRJ64XijgC06ioYQSRvE9niTh2JZLu4lXMAThdjmW3CCErHVa6yBq4Zsd
# u0hZrFgb0kbrcmfW0jW5jPsFwhcky48WTuOFhyEnMTGCBA0wggQJAgEBMIGTMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB15sNHlcujFGOAAEAAAHX
# MA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQw
# LwYJKoZIhvcNAQkEMSIEILC/dYXnnh3RIVGD+rrg94LpH1ZBLB5lFmiKAvUzjeLM
# MIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgnN4+XktefU+Ko2PHxg3tM3Vk
# jR3Vlf/bNF2cj3usmjswgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMAITMwAAAdebDR5XLoxRjgABAAAB1zAiBCDwuKvqEguulWHzdQ8MwfUp1Vqn
# 9GeWGB85nWHavPOJXDANBgkqhkiG9w0BAQsFAASCAgCx9OhzlQuqdcvieoJJE2oN
# u2HXOzl/ZM8rzU9rQptiWWKzFsaj2h3r+xh0X9KUQJl1g0PGOpIUhyK+SGG+OPBM
# gALgVyLNGoajEE/+nA7uvuFx8rcQutvThivevT9xUdTfiEetrnfVlLd8WUxpTsez
# /F7deL+cMj4ESkCL2yBTdEdYknv7orl0CN/87nd0/JEmOxRI4LK6XAZq++2GNlAW
# dsyE7W9cjLd16Fwmz2VHENDyCkV1pHhaMyVsxumWRWUAZIO5wpOMMCVKPTcyHz1W
# vmfcI28bJmPboGKX9IR92CACoM3XcBnZCjed6JOgokHYkQ0YnzEPJBU5PhtnDeDZ
# sGKSXo9pukUyk6fZgwhQIqVwMk8K5ZNk8H/lchPaiwAgoesEHkMxnYGYU+PIgFTv
# NiMZnmF24ol2+hUdBiSmAUHN+6Ib0u/hEBIal74DXONP1x9/TbAdFcSaR4Xy6egz
# UDU6SrIQXW+NJlq8VTPFUQESPY3uuyFgh53cFg7RSs2LxDLMNB+d3pmbNpMmWQs1
# qvNwjueaMFIkomka8/bQBlEMm2LNA8DgW9EYDFXF1rqy3FQ0j8a4vKgERzDqWpUk
# nqTWRjeh7+pPZbEn+3bixtmnQjyGYRQnzUQtH9D3NwJjil9gMwQtwqbdVYxuEOfW
# QllQqdpvUGeaCrYPmClCjw==
# SIG # End signature block
