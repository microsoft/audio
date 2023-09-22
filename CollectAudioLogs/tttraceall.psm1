# Copyright (c) Microsoft Corporation. All rights reserved.

# Collects a Time Travel Trace for Windows Audio services,
# audiosrv, audioendpointbuilder, audiodg, and mmsyscpl (if it is running)

Function FindProcessWithModule(
    [string]$ProcessName,
    [string]$Module
)
{
    # uses the process name to find the win32 process, if it's not a process then it checks to see if it's a service.
    # it then convers the WMI object to a process object, for later use.
    $processFound = get-wmiobject -class win32_process -Filter "name='$ProcessName'"
    if ($processFound -eq $null)
    {
        $processFound = get-wmiobject win32_service -Filter "name='$ProcessName'"
    }

    if ($processFound -ne $null)
    {
        # find only the rundll32 that contains mmsys.cpl, we don't need a trace from others
        foreach ($item in $processFound)
        {
            $thisProcess = get-process -Id $item.ProcessId
            
            if ($Modules -eq $null -or
                $thisProcess.Modules.ModuleName.Contains($Module))
            {
                $process += $thisProcess
            }
        }
    }

    return $process
}

Function GetMitigations(
    [String]$ProcessName,
    $Process,
    [ref]$ConfigChange
)
{
    $ConfigChange.Value=$false
    # retrieve the current process mitigations, and disable shadowstack if necessary
    # shadowstacks must be disabled for time travel traces to work. Shadowstacks is a security
    # mechanism to protect the stored return address so it cannot be overwritten with a buffer
    # overflow.
    if ($Process -ne $null)
    {
        $mitigation = get-processmitigation -Id $Process.Id
        if ($mitigation.UserShadowStack.UserShadowStack -eq "ON" -or
            $mitigation.UserShadowStack.UserShadowStackStrictMode -eq "ON")
        {
            set-processmitigation -Name $ProcessName -Disable UserShadowStack,UserShadowStackStrictMode -Force on
            $ConfigChange.Value=$true
        }
    }
}

Function RestoreMitigations(
    [string]$ProcessName,
    [bool]$ConfigChanged
)
{
    # restore shadowstack settings
    if ($ConfigChanged -eq $true)
    {
        # "notset" is not on or off, but rather a neutral value indicating that the setting is inherited
        # This is the default value.
        set-processmitigation -Name $ProcessName -Enable UserShadowStack,UserShadowStackStrictMode -Force notset
    }
}

Function ResetProcesses()
{
    # if something with shadowstacks changed, we need to shut down and restart the processes for it to take
    # effect.
    stop-service -Name "audioendpointbuilder" -Force
    start-service -Name "audiosrv"

    $mmsys = FindProcessWithModule -ProcessName "rundll32.exe" -Module "mmsys.cpl"
    if ($mmsys -ne $null)
    {
        stop-process $mmsys.Id -Force
        mmsys.cpl
    }

    # this ensures that audiodg is also started, by playing a beep
    [console]::beep(500,300)
}

Function StartTracer(
    $ProcessName,
    $Process,
    $OutFolder
)
{
    if ($Process -ne $null)
    {
        $processId =  $Process.Id.ToUInt32($null);

        # capture the STDOUT and STDERR of each tttracer start process
        $stdoutlog = $OutFolder + "\tttracer-" + $ProcessId + ".log";
        $stderrlog = $OutFolder + "\tttracer-" + $ProcessId + ".err";

        # the default size for ring tracing is a little over 2 GB
        # we can increase this by adding a -maxFile <file size in megabytes> switch
        start-process "tttracer.exe" `
            -argumentlist "-ring -out $OutFolder -attach $ProcessId" `
            -nonewwindow `
            -redirectstandardoutput $stdoutlog `
            -redirectstandarderror $stderrlog;
    }
    else
    {
        
        Write-Host "$ProcessName is not running"
    }
}

Function StartTTTracing(
    [String]$OutFolder,
    [ref]$SvchostConfigChange,
    [ref]$RundllConfigChange,
    [ref]$AdgConfigChange,
    [ref]$TracingStarted
)
{
    # check to see if this is a machine with tttracer inbox, if not,
    # can't get a ttt
    if ( !(test-path "${env:windir}\system32\tttracer.exe"))
    {
        Write-Host "System does not support TimeTravelTrace, continuing"
        return;
    }

    do 
    {
        $reproResponse = Read-Host "Record time travel traces? Warning, these can be very large, and may require stopping and restarting audio components, which will lose system state. (y/n)";
    }
    while (($reproResponse.Trim().ToLower())[0] -ne 'y' -and ($reproResponse.Trim().ToLower())[0] -ne 'n');

    if (($reproResponse.Trim().ToLower())[0] -eq 'n')
    {
        return
    }

    $TracingStarted.Value = $true

    # if any changes are needed for mitigations, we must have AEB in it's own
    # svchost, so set it to "own" now.
    $ownProcess = 16; # default is shareProcess = 32
    get-ciminstance win32_service -filter "name='audioendpointbuilder'" |
        Invoke-CIMMethod -MethodName "Change" -Arguments @{ ServiceType = $ownProcess } |
        Out-Null;

    # we check for the mitigation settings on the currently running processes,
    # get the processes
    $mmsys = FindProcessWithModule -ProcessName "rundll32.exe" -Module "mmsys.cpl"
    $aeb = FindProcessWithModule -ProcessName "audioendpointbuilder"
    $asrv = FindProcessWithModule -ProcessName "audiosrv"
    $adg = FindProcessWithModule -ProcessName "audiodg.exe"

    # if audiodg isn't running, play a beep to get it running
    if ($adg -eq $null)
    {
        [console]::beep(500,300)
        $adg = FindProcessWithModule -ProcessName "audiodg.exe"
    }

    # now we can retrieve all of the current mitigations.
    # audiosrv and audioendpointbuilder are both in svchost, so if either of them need a config
    # change, it affects both.
    GetMitigations -Process $aeb -ProcessName "svchost.exe" -ConfigChange $SvchostConfigChange
    if ($SvchostConfigChange.Value -eq $false)
    {
        GetMitigations -Process $asrv -ProcessName "svchost.exe" -ConfigChange $SvchostConfigChange
    }
    GetMitigations -Process $mmsys -ProcessName "rundll32.exe" -ConfigChange $RundllConfigChange
    GetMitigations -Process $adg -ProcessName "audiodg.exe" -ConfigChange $AdgConfigChange

    # if we needed a config change, we have to restart everything.
    if ($SvchostConfigChange.Value -eq $true -or
        $RundllConfigChange.Value -eq $true -or 
        $AdgConfigChange.Value -eq $true)
    {
        Write-Host "Mitigations change required, resetting processes."
        "Processes were reset" | out-file (join-path $OutFolder "TTTProcessReset.txt")
        ResetProcesses

        $mmsys = FindProcessWithModule -ProcessName "rundll32.exe" -Module "mmsys.cpl"
        $aeb = FindProcessWithModule -ProcessName "audioendpointbuilder"
        $asrv = FindProcessWithModule -ProcessName "audiosrv"
            $adg = FindProcessWithModule -ProcessName "audiodg.exe"
    }

    # shadowstack settings are good, start the trace
    StartTracer -ProcessName "audioendpointbuilder" -process $aeb -OutFolder $OutFolder
    StartTracer -ProcessName "audiosrv" -process $asrv -OutFolder $OutFolder
    StartTracer -ProcessName "audiodg" -process $adg -OutFolder $OutFolder
    StartTracer -ProcessName "mmsys" -process $mmsys -OutFolder $OutFolder
}

Function StopTTTracing(
    [string]$OutFolder,
    [ref]$SvchostConfigChange,
    [ref]$RundllConfigChange,
    [ref]$AdgConfigChange,
    [ref]$TracingStarted
)
{
    if ($TracingStarted.Value -eq $true)
    {
        # capture the STDOUT and STDERR of the tttracer stop process
        $stdoutlog = $OutFolder + "\tttracer-stop.log";
        $stderrlog = $OutFolder + "\tttracer-stop.err";
        start-process "tttracer.exe" `
            -argumentlist "-stop all" `
            -nonewwindow `
            -redirectstandardoutput $stdoutlog `
            -redirectstandarderror $stderrlog `
            -wait;

        # restore from any mitigation changes
        RestoreMitigations -ProcessName "svchost.exe" -ConfigChange $SvchostConfigChange.Value
        RestoreMitigations -ProcessName "rundll32.exe" -ConfigChange $RundllConfigChange.Value
        RestoreMitigations -ProcessName "audiodg.exe" -ConfigChange $AdgConfigChange.Value

        Write-Host "Resetting processes to close out traces."
        ResetProcesses
    }
}
