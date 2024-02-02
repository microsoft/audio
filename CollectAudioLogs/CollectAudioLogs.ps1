# Copyright (c) Microsoft Corporation. All rights reserved.
param(
    [string]$problem,
    [switch]$reproLogsOnly
);

Function Get-YesNoResponse
{
    param([string]$prompt);
    do 
    {
        $response = Read-Host "${prompt}? (y/n)";
        $response = $response.Trim().ToLower();
    }
    while (-not $response.StartsWith("y") -and -not $response.StartsWith("n"));
    
    Return $response.StartsWith("y");
}

[Nullable[bool]]$canRepro;
[Nullable[bool]]$glitch;
[Nullable[bool]]$ttt;

switch ($problem)
{
    ""
    {
    }

    "glitch"
    {
        $canRepro = $true;
        $glitch = $true;
        $ttt = $false;
        break;
    }

    "norepro"
    {
        $canRepro = $false;
        break;
    }

    "other"
    {
        $canRepro = $true;
        $glitch = $false;
        break;
    }

    "ttt"
    {
        $canRepro = $true;
        $glitch = $false;
        $ttt = $true;
        break;
    }

    default
    {
        Write-Host "Unexpected problem $problem - specify 'glitch', 'norepro', or 'other'";
        Exit;
    }
}

if ($null -eq $canRepro)
{
    # Ask the user if they'd like to take a repro trace
    $canRepro = Get-YesNoResponse -prompt "Do you want to grab logs of the problem in action";
}

if ($canRepro)
{
    if ($null -eq $glitch)
    {
        # Ask the user if the problem is an audio glitch
        $glitch = Get-YesNoResponse -prompt "Is the problem that audio sounds bad";

        if ($glitch)
        {
            $ttt = $false;
        }
    }

    if ($null -eq $ttt)
    {
        $ttt = Get-YesNoResponse -prompt "Do you want to grab time-travel traces";
    }
}
elseif ($reproLogsOnly)
{
    Write-Host "reproLogsOnly parameter passed but cannot repro";
    $reproLogsOnly = $false;
    Exit;
}

# Script requires admin privileges to run
Import-Module "$PSScriptRoot\RegistryToXml.psm1";
Import-Module "$PSScriptRoot\tttraceall.psm1";

# need this for [System.IO.Compression.ZipFile]::CreateFromDirectory to work on PowerShell 5
Add-Type -AssemblyName System.IO.Compression.FileSystem;

$system32 = "${env:windir}\system32";
# check for WOW64
if ($null -ne $env:PROCESSOR_ARCHITEW6432)
{
    Write-Host "WARNING: script is running WOW64";
    $system32 = "${env:windir}\sysnative";
}

# Create a directory for all output files
$outDirName = "$($env:COMPUTERNAME)_$(Get-Date -Format yyyyMMdd-HHmmss)";
Write-Host "Creating temporary directory $env:TEMP\$outDirName.";
$outDir = New-Item -Path $env:TEMP -ItemType Directory -Name $outDirName;

if ($canRepro)
{
    if ($glitch)
    {
        $profileName = "audio-glitches-manual";
    }
    else
    {
        $profileName = "audio-info-manual";
    }

    # Packaged wprp file
    $wprp = "$PSScriptRoot\$profileName.wprp";

    $svchostConfigChange = $false
    $rundllConfigChange = $false
    $adgConfigChange = $false
    $tracingStarted = $false

    # prompt and optionally start the time travel traces
    # before starting etw tracing, so that the potential
    # service restarts are not included in the etw logs
    if ($ttt)
    {
        StartTTTracing -OutFolder $outDir -SvchostConfigChange ([ref]$svchostConfigChange) -RundllConfigChange ([ref]$rundllConfigChange) -AdgConfigChange ([ref]$adgConfigChange) -TracingStarted ([ref]$tracingStarted)
    }

    # Start repro
    $wprExe = "$system32\wpr.exe";
    $wprStartArgs = "-start `"$wprp!$profileName`"";
    Start-Process $wprExe -ArgumentList $wprStartArgs -NoNewWindow -Wait;

    # Wait for user to press enter before continuing
    Write-Host "$profileName tracing started, please reproduce your scenario.";
    $null = Read-Host "Press Enter to stop tracing";

    # Stop repro
    Write-Host 'Writing repro trace to disk.';
    $wprStopArgs = "-stop `"$outDir\${profileName}.etl`"";
    Start-Process $wprExe -ArgumentList $wprStopArgs -NoNewWindow -Wait;

    # stop time travel traces, if they were started
    # do this after stopping etw's so we don't have the potential
    # service restarts included in the logs
    if ($ttt)
    {
        StopTTTracing -OutFolder $outDir -SvchostConfigChange ([ref]$svchostConfigChange) -RundllConfigChange ([ref]$rundllConfigChange) -AdgConfigChange ([ref]$adgConfigChange) -TracingStarted ([ref]$tracingStarted)
    }
}

# Gather diagnostic information
if (-not $reproLogsOnly)
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

# SIG # Begin signature block
# MIIoLgYJKoZIhvcNAQcCoIIoHzCCKBsCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCmDcCjZD2eRr9j
# Wm3W8uY0Z+22vyDks9rCyduONFf8VaCCDXYwggX0MIID3KADAgECAhMzAAADrzBA
# DkyjTQVBAAAAAAOvMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjMxMTE2MTkwOTAwWhcNMjQxMTE0MTkwOTAwWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDOS8s1ra6f0YGtg0OhEaQa/t3Q+q1MEHhWJhqQVuO5amYXQpy8MDPNoJYk+FWA
# hePP5LxwcSge5aen+f5Q6WNPd6EDxGzotvVpNi5ve0H97S3F7C/axDfKxyNh21MG
# 0W8Sb0vxi/vorcLHOL9i+t2D6yvvDzLlEefUCbQV/zGCBjXGlYJcUj6RAzXyeNAN
# xSpKXAGd7Fh+ocGHPPphcD9LQTOJgG7Y7aYztHqBLJiQQ4eAgZNU4ac6+8LnEGAL
# go1ydC5BJEuJQjYKbNTy959HrKSu7LO3Ws0w8jw6pYdC1IMpdTkk2puTgY2PDNzB
# tLM4evG7FYer3WX+8t1UMYNTAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQURxxxNPIEPGSO8kqz+bgCAQWGXsEw
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMTgyNjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAISxFt/zR2frTFPB45Yd
# mhZpB2nNJoOoi+qlgcTlnO4QwlYN1w/vYwbDy/oFJolD5r6FMJd0RGcgEM8q9TgQ
# 2OC7gQEmhweVJ7yuKJlQBH7P7Pg5RiqgV3cSonJ+OM4kFHbP3gPLiyzssSQdRuPY
# 1mIWoGg9i7Y4ZC8ST7WhpSyc0pns2XsUe1XsIjaUcGu7zd7gg97eCUiLRdVklPmp
# XobH9CEAWakRUGNICYN2AgjhRTC4j3KJfqMkU04R6Toyh4/Toswm1uoDcGr5laYn
# TfcX3u5WnJqJLhuPe8Uj9kGAOcyo0O1mNwDa+LhFEzB6CB32+wfJMumfr6degvLT
# e8x55urQLeTjimBQgS49BSUkhFN7ois3cZyNpnrMca5AZaC7pLI72vuqSsSlLalG
# OcZmPHZGYJqZ0BacN274OZ80Q8B11iNokns9Od348bMb5Z4fihxaBWebl8kWEi2O
# PvQImOAeq3nt7UWJBzJYLAGEpfasaA3ZQgIcEXdD+uwo6ymMzDY6UamFOfYqYWXk
# ntxDGu7ngD2ugKUuccYKJJRiiz+LAUcj90BVcSHRLQop9N8zoALr/1sJuwPrVAtx
# HNEgSW+AKBqIxYWM4Ev32l6agSUAezLMbq5f3d8x9qzT031jMDT+sUAoCw0M5wVt
# CUQcqINPuYjbS1WgJyZIiEkBMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGg4wghoKAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAOvMEAOTKNNBUEAAAAAA68wDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIK48V7ZlyUqJGRtVE06kEQH5
# N3M+yoaEiDzKxQoIIYgoMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQBHZVM0upVtmdjYC4HlP7vMdOYjNTU4NiNusqAaaAjO+K1wt7KnJwA5
# 9FNRd0O4xnaLuYz9KcaZvEUMYausGCAls/1YHSLjwey/lAtBEu0ZI8knh0E6lyo4
# a9FuWNyzk26cCqwgMxS2waftJKUAVajwh/gtLs6ZMgUG/aeAc2gFneNOAc0f18dK
# SPxa7SCIcbhHojlqxRbgX+9vftuDBAwRUtqt9ykmY8in+Vb/VNwu+Px6vNxaoFfd
# HK6M1XLOeCUlYtBB2Gj5iX/lhWb/4fI3mOWBNBKy88QAdKymsdere9Q4yZnzEGuk
# XNpBsZ+smvXMBqfr3Du80RSX4zYQic3qoYIXljCCF5IGCisGAQQBgjcDAwExgheC
# MIIXfgYJKoZIhvcNAQcCoIIXbzCCF2sCAQMxDzANBglghkgBZQMEAgEFADCCAVIG
# CyqGSIb3DQEJEAEEoIIBQQSCAT0wggE5AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIDbufFpLrCgyMeFfnubyvmcwYwf9PqHVF+l+di/OjC6NAgZlvBJZ
# H+IYEzIwMjQwMjAyMDAwNTAzLjEzOFowBIACAfSggdGkgc4wgcsxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBB
# bWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpEQzAw
# LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZaCCEewwggcgMIIFCKADAgECAhMzAAAB6FCwgM8rcplNAAEAAAHoMA0GCSqGSIb3
# DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIzMTIwNjE4
# NDUyMloXDTI1MDMwNTE4NDUyMlowgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlv
# bnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpEQzAwLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAOFBd0TRbNcbvDN4L1IZ0fp5XB0aUXpiClTvB44U
# GSlb3K4SYlIMTUAMHH/QNO5EFqmVIPwJHVCrJCbFEMP8J28PJ5kUBxnqXb6eUyyy
# ZnILxM+3UZNYBS3cZdRTqDQXS0isU0uCh8KM6+bcbSPjzZW60pLjBlPps1WcFWwK
# GvYCOZVsYM3/pCz8SpqQvlzCkZ6XW17tQ7Xd1TBo+M7LRaLWpg2ZHyLtPWW6PYl0
# V19mEw/KrKr80Odm441JuPwUznEoGhqvXatqALz/UJdovU4xcHAZpGglNi2SyL2e
# O6rjAORwDCK0JnkG1DY2o9nSUuJAHs7XQGb3Okdaf3HX8eZ0CfiSgxYpQPAfmx3/
# MO7i+LzzsVbGbniSRY2+TwV5DtlnRDmCoYpbiDqt69XYh0DEGhtZ2iurC/OovvRZ
# 2yANT8/lzQvy9giyRQll50IYczaEciw1HLD0QWhKiUMz7IJ52TPr3vzuzycinnmJ
# wt8OgrDmFqTkboxYXp3vW1w3NX36/1FAoxrpTB/Kq6t513mypdYJe/76F6TgDXlb
# Jshzq59PSKVrMphm8O+hqzCCM/RJ4tbua+ZzDQUQvMXX+5ZpcSUsc5ciWJ4oXaL9
# jNDpTnQr11uGcxoNwlKwbSFctFPL8tBuw4PSHDsW4rSebOi1LH/l+j2Dt8LOgWOT
# e0MTAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQU+jlbyj3zSQx9FVBtrpPfgfB6Utow
# HwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKg
# UIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
# XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9j
# ZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQw
# DAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
# BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAJZ9wmbavBe0+LviSbo8oCSeL34Fai2r
# 5C0MaB5PkXeujs+whQ0pGRTK24aojy2EvclytvTfHoM6mlgkQD6lvqjao+MV107V
# Muq9Jetib46AIsv7v7cWZGZ+RG7yse+mtpvQ7X3ANu6SA7wjk6LVF6AwmXy3mT9S
# 0TRZvfMCU4ecKMsZLM/8Ojem3CFeiSTTYi8PtJkQFs9ugZu3DgsIexPakVqSkY4G
# H4hJQxcF/zfkK5U1913DGbIa81LPITISTmHVWHu2nA/vPusn4eyI/ix2oGOPoC+i
# m5/ivFQB+sRtXpqPy3AWztZUc2IiCsc2dr/nmTKsAb1i3X0I++RTDFgrS5m8+XZY
# Lf2d9zSM5OOK8Luz8hSjMTi1/Lck2TJDVw229l+2JfePkO354s564YOO+Em9gwgS
# SmRXrxcs0fv5kF9hr4+Z9FhqgUUcIkoShFJnc9sMk8GISFn3K7Ex12gwxDX1OTJ+
# 2i3oTPReFKbCNgGrf0O8EVaGXIMYGGtTca14NaJV31gZIHZafG4UzLl9sArqjw9b
# PxBEyKm1ccrccMGvbBZYRyuuBxO4dkglOp6k2hiXH1VEW+P+8JdoAVyaRbWeTtUT
# 6jBpevlEmOvIOr25uTIOrWZ2sX+B5pEAtdw1lt81ciSFfNcDprwKJqZxBb8OCYsm
# mJVA2uJlgIcgMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkq
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
# A08wggI3AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046REMwMC0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMV
# AIwkbi+DSO4w5WfYG4oAJS8/zQW6oIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDpZpDcMCIYDzIwMjQwMjAxMjE1
# MTI0WhgPMjAyNDAyMDIyMTUxMjRaMHYwPAYKKwYBBAGEWQoEATEuMCwwCgIFAOlm
# kNwCAQAwCQIBAAIBDgIB/zAHAgEAAgIQQTAKAgUA6WfiXAIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQBSyfotvIxoVe8b6QFSYa7PVH8A5Zx3Z3iPvWl8YN9l
# AhLcK4V14lR9/enyGnR75WJ0zjhLSpbD38IVl+7BEUur2mari0m3sUqmIi7Rt2sE
# EFGL36AHcHHE3T1U6P1syQtE3Jqkya9r4apf2ESFTsGDYuN5jsJhgelo2IrOCtfJ
# WCtunfzUbMFTohFnxwuhCgY21ZujTRQnh+CtS30ES0W8h1H1yC70W/ZSsPQXUvv0
# WnWjM80D/Wh1ptphGfl8eAEg3e54708Iwj1OsBM+wAJ1WcUYZg4AYiF8eTo33djy
# tl/5FkdAONjU1vlfVT5TD/d73T84QpXOQTzujFrEA01EMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAHoULCAzytymU0AAQAA
# AegwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQg6JB5O3l93k6VorUUUAAU2bTZ7mva4mETesN13db0
# zMMwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAq0trE1QKEIIJB0efaTaoo
# HtMXyU9id1PFtUnPB/jrHTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAAB6FCwgM8rcplNAAEAAAHoMCIEIL4ZceMntlVnENnHGPPkA4qc
# crzPNz/zDOh8XeD7YD2iMA0GCSqGSIb3DQEBCwUABIICALBzdvUYzflgHXZnl70V
# eHEQYQXHAekxk3NL9dwZwCuSnXKsWnB1RFP5f66EipIHkMQXwDSaOMFc4FLG/B6F
# BolFSYY8szTmFYGIPBEKXpRyL3vS/PAZ37iNYpZtGIh6omJOsBdrXY7RdxWPWJu0
# ppafay7i3CIbmYU5pWaR4buBSgnWc6qLzAop++ztbVAfuyLYUxsj6AdAK4ywYRfh
# /yOh/ypV/2RNeesAmZDCJ8aYtn+bmMbVGkjoSLvMd4AOirUDXs0O8luby8X/0Y6V
# NQ36+kq5lK7mcVHSTsFPhNTYrkoCz+wI4dTsSzalIRjAkrmTt+EidvNlZxyiBMwy
# FDsR0q+OwSZ0GOkesK1TnXpNjBzsuzf6v4LI0DcMSe/2BZmjMso8xTFLNHnCZtpf
# r7otEinxc5NIzgQr+2esqYdPH4wEJ0NBSfNEgiI+8OeOT5oc9OVPfUOgs/FxR9Fd
# 5skxRj+FFYQrHe+5H10x+4faDmjBnPpnR0YGUhXEv6zCIGCcRjgZE/KIMagLnO7G
# iC921KT8ERVxd6DQiLKof8XX394L3MO9SMtp5tMEMC6xtlNykairnxIW7HG0shgp
# /dEU/mEJ1/E+GqvHs2OKjpKt1j3BdqhvjQ67H2DlEoJ2YCvoJGoHS8ShQM65vteL
# O2p2Bu4flrmY+VwJJviMC7DH
# SIG # End signature block
