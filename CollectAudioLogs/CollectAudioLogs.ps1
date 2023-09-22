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
# MIInwAYJKoZIhvcNAQcCoIInsTCCJ60CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCANc999Rgw4pawS
# jG0ZktUCXD89doIdzYmEmAKVgG0Xk6CCDXYwggX0MIID3KADAgECAhMzAAADTrU8
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGaAwghmcAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAANOtTx6wYRv6ysAAAAAA04wDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMllOMxuB1P6UglDGHQEzloD
# axlPKOU3UoQXBOZZTKnoMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQCOdpLx1y2Q5uruZorHX8pKXXr7qFr45bPXeUmFMSl/6grJaYptZj3/
# /FhApGAavX/QCyRm8Iw/hod2asvQyjPZMrdCmcQz+1x4a+UtjYgDCx7bzx30d+yj
# 6bbdmnjJq+XM/XeiSl1hgH8sJTfBfml4d56/KWmoDSvOldsNcVdRUf7AfZvLCd9u
# K20lNfXdQ8oEZSfaKxNKJHGHyBJIFRKCXeafjJ670lA2sYu/RBilEFjkU2PJijSb
# pdu9XaRL7RKBFRCjVeWk5YpwfaWurELE9nM2gslzdG5l2DmNRmid6rhetr450c8g
# Op9kyxCPVU3gR/lvYsLnJYrGYRFmciHHoYIXKDCCFyQGCisGAQQBgjcDAwExghcU
# MIIXEAYJKoZIhvcNAQcCoIIXATCCFv0CAQMxDzANBglghkgBZQMEAgEFADCCAVkG
# CyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIFX+6Dq5hcqAgJ+BhB0TJI4/x/WjjjmR2ZPs2HOg72eeAgZlCvX6
# WqoYEzIwMjMwOTIyMTY0MDA5LjMyM1owBIACAfSggdikgdUwgdIxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBF
# U046MDg0Mi00QkU2LUMyOUExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2WgghF3MIIHJzCCBQ+gAwIBAgITMwAAAbJuQAN/bqmUkgABAAABsjAN
# BgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0y
# MjA5MjAyMDIyMDFaFw0yMzEyMTQyMDIyMDFaMIHSMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBP
# cGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjA4NDIt
# NEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyqJlMh17+VDisL4GaXl/
# 9a6r/EpPGt9sbbceh+ZD6pkA3gbI7vc8XfL04B+m3tB/aNyV1Y4ZQH4fMG7CWVjI
# /d/HgxjzO+4C4HfsW+jK2c0LYMqdWtWUc5VwZQv0KeaEM0wDb+eySMh/YiiIb0nS
# otivx268d1An0uLY+r2C7JJv2a9QvrSiCyUI72CSHoWIQPAyvBSvxaNrqMWlROfL
# y2DQ3RycI3bDh8qSnmplxtRgViJwtJv/oDukcK1frGeOrCGYmiJve+QonJXFu4Ut
# GFVfEf3lvQsd42GJ+feO+jaP7/hBXXSMSldVb6IL0GxO1Hr3G9ONTnVmA/sFHhgM
# RarsmzKVI6/kHlMdMNdF/XzhRHMWFPJvw5lApjuaoyHtzwnzDWwQzhcNQXZRk3Lz
# b01ULMba190RdlofEXxGbGlBgHHKFnBjWui24hL6B83Z6r6GQBPeKkafz8qYPAO3
# MBud+5eMCmB5mrCBxgnykMn7L/FTqi7MnPUG97lNOKGSIDvBCxB7pHrRmT10903P
# DQwrmeJHO5BkC3gYj3oWGOGVRZxRk4KS/8lcz84a7+uBKmVjB2Y8vPN8O1fK7L8Y
# JTkjiXTyDqKJ9fKkyChiSRx44ADPi/HXHQE6dlZ8jd9LCo1S+g3udxNP4wHhWm9/
# VAGmmMEBBS6+6Lp4IbQwJU0CAwEAAaOCAUkwggFFMB0GA1UdDgQWBBSZ8ieAXNkR
# mU+SMM5WW4FIMNpqcTAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBf
# BgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmww
# bAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUF
# BwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEA3Ee27cXMhpto
# NtaqzB0oGUCEpdEI37kJIyK/ZNhriLZC5Yib732mLACEOEAN9uqivXPIuL3ljoZC
# e8hZSB14LugvVm1nJ73bNgr4Qh/BhmaFL4IfiKd8DNS+xwdkXfCWslR89QgMZU/S
# UJhWx72aC68bR2qRjhrJA8Qc68m5uBllo52D83x0id3p8Z45z7QOgbMH4uJ45snZ
# DQC0S3dc3eJfwKnr51lNfzHAT8u+FHA+lv/6cqyE7tNW696fB1PCoH8tPoI09oSX
# AV4rEqupFM8xsd6D6L4qcEt/CaERewyDazVBfskjF+9P3qZ3R6IyOIwQ7bYts7OY
# sw13csg2jACdEEAm1f7f97f3QH2wwYwen5rVX6GCzrYCikGXSn/TSWLfQM3nARDk
# h/flmTtv9PqkTHqslQNgK2LvMJuKSMpNqcGc5z33MYyV6Plf58L+TkTFQKs6zf9X
# MZEJm3ku9VBJ1aqr9AzNMSaKbixvMBIr2KYSSM21lnK8LUKxRwPW+gWS2V3iYoyM
# T64MRXch10P4OtGT3idXM09K5ld7B9U6dcdJ6obvEzdXt+XZovi/U6Evb4nA7VPH
# cHSKs7U72ps10mTfnlue13VFJUqAzbYoUEeegvsmzulGEGJoqZVNAag5v6PVBrur
# 5yLEajjxWH2TfkEOwlL8MuhcVI8OXiYwggdxMIIFWaADAgECAhMzAAAAFcXna54C
# m0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZp
# Y2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMy
# MjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51
# yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY
# 6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9
# cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN
# 7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDua
# Rr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74
# kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2
# K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5
# TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZk
# i1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9Q
# BXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3Pmri
# Lq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUC
# BBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9y
# eS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUA
# YgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# 1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIw
# MTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/yp
# b+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulm
# ZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM
# 9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECW
# OKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4
# FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3Uw
# xTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPX
# fx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVX
# VAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGC
# onsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU
# 5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEG
# ahC0HVUzWLOhcGbyoYIC0zCCAjwCAQEwggEAoYHYpIHVMIHSMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJl
# bGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNO
# OjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCOEn4R7JJF+fYoI2yOf1wX0BRJOqCBgzCB
# gKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUA
# AgUA6LgXKzAiGA8yMDIzMDkyMjIxMzc0N1oYDzIwMjMwOTIzMjEzNzQ3WjBzMDkG
# CisGAQQBhFkKBAExKzApMAoCBQDouBcrAgEAMAYCAQACAX8wBwIBAAICEuEwCgIF
# AOi5aKsCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQAC
# AwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQB7fc32ZUbXZ6xtoyE4
# cyp3qMk98tCkZlUN/cUYCD4VloYBBW9qy2PkVF3sxlvj8OT8prADah9DxV/DSs3N
# q1+a945yDc8akwJ7GJH+YgYr1QWlQ9uv2o2D+LGhjt294hgj3ZPAFwmaa0QWUy+U
# hvSUkbzQYgjdSs2zQb+zadmV3TGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAABsm5AA39uqZSSAAEAAAGyMA0GCWCGSAFlAwQC
# AQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkE
# MSIEIF3Mk804HYjiX1vEs5tPVyIfWh1V4EUTwCprtBu3Ov+WMIH6BgsqhkiG9w0B
# CRACLzGB6jCB5zCB5DCBvQQgU3jOPOfhPreDxFYnlKBSl+z1ci6P587vobSTwhtO
# PjUwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAbJu
# QAN/bqmUkgABAAABsjAiBCCtmKbiGpV2T+3SsAq39jNMDcZW8JmokFSfOUcBOnC0
# UDANBgkqhkiG9w0BAQsFAASCAgAudfoxD/RwU8TyaiFfBkMLJ5+NNb1CI3+SmoYX
# UpD1m3d/WE0xJyoJMwxaFPggubFzdOJi6x4coPBDmYkKITy79P3/9yo1cQy8tSu3
# hRtGKnxf5s9Nfbu0WBssmEyKuJn6fkE3u9ZK5FN0xmcVhmXiLONO9kisAKFcGtMu
# aKIr6GK5y8oes/Upj3XvwHVyXqC5xn/uIWrwS1RTA+z7Zk+pv2LoE8w4db126Xo5
# YvP6mRzlaf1HJBIbAsHMiT2r/0X3QtV1/KNmjwMHl95sGN3RrDEHhdpxDU5025pf
# odLiJ3B7IFr+67XsROPVxvl1YMW9n1u+C1hvTWcBdqp1BwNMcfWfm1BJ/wja5zcO
# 8q5WDkoiGwwP+icX5HJUJ5hwTsSKwprqTBKlj21RwO6uDapcUUXIOI/hlPoGLnFE
# ctAFT9zVXJAXiKQAbKz8UYk0WRF966mlA5KpYniVann3BBTbEFraft/MJYuiK02b
# 6vkVWEGEx8qYw3x6F+L+SlzL6NHjtiuHSb2avRW194qBg0mjgUWaign+0vgvoGW9
# c7TWtVPN7kbCR01z/PK169lWID4jIDT/ma+TF0Ps4K0xqabY0Zz7aQ/SH2uBd2S6
# SVUSmPNmqNFMjLBqAoEb1fVkr0UJoCgo5zNcfFIZOumRpUw62Y73cM/YSSmLGWKI
# wixgmQ==
# SIG # End signature block
