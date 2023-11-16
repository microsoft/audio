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
        $profileName = "audio-info";
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
