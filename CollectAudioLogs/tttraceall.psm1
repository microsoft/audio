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
                $process = $thisProcess
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
        #ARM systems support PAC, which is similar to CET. At this time PAC cannot be disabled via set-processmitigation,
        #so disable it via registry.
        if (${env:PROCESSOR_ARCHITECTURE} -eq "ARM64")
        {
            $path = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$ProcessName"

            #create this path if it does not already exist
            $key = Get-Item -path Registry::$path -Erroraction Ignore
            if ($key -eq $null)
            {
                $output = New-Item -Path Registry::$path
            }

            #retrieve the current mitigation value
            $mitigation = Get-ItemProperty -path Registry::$path -Name MitigationOptions -Erroraction Ignore

            #if there is no mitigation option value, or the current value is not the expected value, change it
            if ($mitigation -eq $null -or
                $mitigation.MitigationOptions -eq $null -or
                $mitigation.MitigationOptions -ne 0x20)
            {
                $output = New-ItemProperty -Path Registry::$path -Name MitigationOptions -PropertyType qword -Value 0x20 -Force
                $ConfigChange.Value=$true

		#if there was a previous value, save it in $ConfigChange to restore, otherwise ConfigChange is $true.
                if ($mitigation -ne $null -and
                    $mitigation.MitigationOptions -ne $null)
                {
                    $ConfigChange.Value=$mitigation.MitigationOptions
                }
            }
        }
        else
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
}

Function RestoreMitigations(
    [string]$ProcessName,
    [ref]$ConfigChanged
)
{
    # restore shadowstack settings
    if ($ConfigChanged.Value -ne $false)
    {
        $path = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$ProcessName"
        if (${env:PROCESSOR_ARCHITECTURE} -eq "ARM64")
        {
            #if ConfigChanged is $true, then that means that we changed the MitigationOptions, but there was no
            #previous value to restore. Delete the key.
            if ($ConfigChanged.Value -eq $true)
            {
                $output = Remove-ItemProperty -Path Registry::$path -Name MitigationOptions
            }
            else
            {
                $output = New-ItemProperty -Path Registry::$path -Name MitigationOptions -PropertyType Qword -Value $ConfigChange.Value -Force
            }
        }
        else
        {
            # "notset" is not on or off, but rather a neutral value indicating that the setting is inherited
            # This is the default value.
            set-processmitigation -Name $ProcessName -Enable UserShadowStack,UserShadowStackStrictMode -Force notset
        }
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
    if ($SvchostConfigChange.Value -ne $false -or
        $RundllConfigChange.Value -ne $false -or 
        $AdgConfigChange.Value -ne $false)
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
        RestoreMitigations -ProcessName "svchost.exe" -ConfigChange $SvchostConfigChange
        RestoreMitigations -ProcessName "rundll32.exe" -ConfigChange $RundllConfigChange
        RestoreMitigations -ProcessName "audiodg.exe" -ConfigChange $AdgConfigChange

        Write-Host "Resetting processes to close out traces."
        ResetProcesses
    }
}


# SIG # Begin signature block
# MIIoLgYJKoZIhvcNAQcCoIIoHzCCKBsCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCSru//z8dhCEr7
# iYzYVRgQk8XSp2uYrHBuCE4RmJjxh6CCDXYwggX0MIID3KADAgECAhMzAAADTrU8
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGg4wghoKAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAANOtTx6wYRv6ysAAAAAA04wDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIHdsUjO6gsDoMRAwzpqO6eS3
# vaWpNE17uXzJjFaCSkX4MEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQAVUHnjXLuok5hqN1oxwsqbQ3qzemOpIhTN2hNkTQkoJyHaL8NUyMT4
# Nrft/XUfYI7WJFI4EqJWlaUGr6essamx9oZHaUZP21RIkTcr4Z0pbrmqdH/dcpXI
# Fmmlc+0R3bYECSZCF02IXM7tgY3Hq29WEcPaNHHLYfMaWxeitCFPBSDyeHyhysCK
# lkAjpysfGoqUqnfp72FNYqQrd26mWlHgFfs5vyBx5ZJ8Z3W6AcsyJYQKyUa2c3ek
# daXL0AwnHFZ0IuFKNQVBfpQfePdP7eA6ZLFTlJ8pEoHV41ct1UZ1300HOOpRtTkc
# EkFZlZhIRXcd4dSCNJ5lmwAG9kvAW+oeoYIXljCCF5IGCisGAQQBgjcDAwExgheC
# MIIXfgYJKoZIhvcNAQcCoIIXbzCCF2sCAQMxDzANBglghkgBZQMEAgEFADCCAVEG
# CyqGSIb3DQEJEAEEoIIBQASCATwwggE4AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIAm8a03wpiRePEu+oqIy+Km62v1Dfb4697mQHtFhyaHSAgZlKK4i
# V3sYEjIwMjMxMTAxMTc0MDEzLjg4WjAEgAIB9KCB0aSBzjCByzELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkUwMDIt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oIIR7TCCByAwggUIoAMCAQICEzMAAAHZnFwFkrCDaz4AAQAAAdkwDQYJKoZIhvcN
# AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjMwNjAxMTgz
# MjU4WhcNMjQwMjAxMTgzMjU4WjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9u
# czEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkUwMDItMDVFMC1EOTQ3MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEA1ekgzda4GNt9Oci3QnVDbxwhBOGdLnA+giry+ZQO
# xzPNUjJFt+kVO+1GgS/T0nL4qn1cxNq9qUW0TLQwTMBMdYmos1dhGbDRhrs3kd1z
# WDm0LyVS2gogZLQGXau+QTRSIpfkn3aV4Cs1UGYgwSQzedFggAza62+PGeGe/yr8
# s2g+Bm/mmXgoqAdhoNZud3fuqVEwXN1jucR2Yv66yP13Z4YhOv27KY6VOWrnwpSA
# 8dEA6tUEcNOGnayoXA1shi90mgaf4YzfuCSVOys77ClmVXU7lz6I52k8FnB3RBn8
# 8Ymhd9M3fEmOGEVHDBjzkDkR9SD8JMMJakJHNBwZCQkM4ml2PyKYDEcP1z+FL/iQ
# SfEWRimTdc0T1k/XebxxlEpl95u+0SqAn5IEiYnyIkIuhXNDmCkuoGTgO53eLfpY
# gK6/Z4qngv1HDTrla3FQuAm5MHydnh5GlodfLFLd1A/EB2C0MJ/eT/h5vD2SYoK9
# UkS3LJvKTj3nuzwW53SP1XiibJkHY3pNmhTvVRp1LcwwwaMJYV7IbMGTDJCyf+I1
# M0JlAX5viQB9edehPhtNsEuzYMzMJqR1gpgGhXXew8iSKhmum3Ga0e0AC3ZMCIVU
# A4M2QLjcasL4eCGuGSOVaMo+G+81gIZrq6cKTKYo8/onnlsH+mXZsrEY0f8melF5
# hmsCAwEAAaOCAUkwggFFMB0GA1UdDgQWBBQcOsEpU2eoBV5dOcP7NxmtX+dcJzAf
# BgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQ
# hk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQl
# MjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBe
# MFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2Nl
# cnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAM
# BgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQE
# AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAKjbVWCzutUzLiGpwu3JbdIvl0UWx8J8D
# aNOUN7OKaRbXeJwpgf0yTwyerrxK8sbNL8OWPo0MFIip4ZdlRhsCKtKVgyLmluKa
# TFdaWEHyenbQRpEYkz9XilbwEWGTEWiE3vWYcCSZ2D/N6TMRwsWhLGQuIpWN/+eX
# aneGV0ws/3KRuWp5g2q7Z1poMrMoDbLU8G1iSUY/OYGEZI8Yv58SgIhBcZehn5HJ
# 11cvA0RUI9XdwIqrHj6HiM8btYrgCUcA633uDZyh6qE4FrL+3gliZ1o1lkbe0URq
# 6b8y0KPwcVG/IuPVMEYPRuW8aXeUrtW9tuBr+htR0VPqiRwdc6HuNQ9q/4nNgT6L
# rFfZ3mCuaiOTxy7IQJ+mE0JZW1faQmzlL2TtHbXcKeRx9n8OqHyTcCnDxJWqpBHM
# b64YUVqsDYGhFU8iFeIzHPIz28djYfcwM7Z2/TX5wxThPv4BfHGak2v0+uUxjT97
# jIj94K/JyF0NiEcDFVKC5hrtqn5oQ6HsLN3XL5OrNWgOplx8PjADRCAyio8N4thu
# ibWZBHprtTl7bJIP7Rp38sGjIKuQmrlPW+np07QPlBPhip5okFumFBz4QSNC9kBu
# +k0Qa3uT6TVR4snP9NW41BDKXmgfiJwB+Jw8WF8dfMGyRPnvyGzL9NeOxBS+/dnR
# CxdF8KqnFNEwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqG
# SIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkg
# MjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4X
# YDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTz
# xXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7
# uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlw
# aQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedG
# bsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXN
# xF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03
# dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9
# ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5
# UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReT
# wDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZ
# MBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8
# RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAE
# VTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAww
# CgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQD
# AgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb
# 186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoG
# CCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZI
# hvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9
# MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2Lpyp
# glYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OO
# PcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8
# DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA
# 0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1Rt
# nWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjc
# ZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq7
# 7EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJ
# C4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328
# y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYID
# UDCCAjgCAQEwgfmhgdGkgc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMx
# JzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpFMDAyLTA1RTAtRDk0NzElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUA
# 4hxFugmt5+QYGVf7UP3wkdPU3/eggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAOjs4EcwIhgPMjAyMzExMDExNDMz
# NDNaGA8yMDIzMTEwMjE0MzM0M1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA6Ozg
# RwIBADAKAgEAAgIJfgIB/zAHAgEAAgITXDAKAgUA6O4xxwIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQCeVIuDfVn+IXaW7iOmT8mUrdIKaoosChbFwhUrRTk4
# Q9tkiVD1XZzV84HqoIJ9phJSId8jdk0sIcVTem+pmCsr+3Q4kg3dtkQJxXjjvFaD
# a1Rg9eblDKz8HrbW1n1t6UA2h6dpMlL0Yfz+q6d3/818IyJy0Qi6dB3cbK/Lk9Bx
# h9C/q3i85m083Tk1qzC6XgRZ4zy0JqoXXDKYoX/VYWmehXyXFB2CzaOljtEhEKQ9
# Ix++T0iXbMlzZfHrRIOTyICgQs3tOvB3zB54q62pMkVCImS3nFQZiYXD8U4N3uep
# YDsXmtaMclJH4dXthPl7vGEG2HmKCNh8oIDk8K/9W72mMYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAHZnFwFkrCDaz4AAQAA
# AdkwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgLbkCKbsplZiT+ZGg+m/Y4rtKplDETOYeGZot8E/3
# DIEwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCCfoBWyLTpv1DAwJxE82yXt
# LtA1ndjIKYG9EnG0IAd58zCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAAB2ZxcBZKwg2s+AAEAAAHZMCIEIPPZVuZ3l/P6e+rfv1nmfzcd
# vsVEoTiuqWp/0d3wQGCpMA0GCSqGSIb3DQEBCwUABIICAB78OJW2ug1WslvoXUVC
# NmWGAZJ3tPLrcRUv/bN9ZullcORhISKLuFgx0w0nWAX+onUQSBKlr7LzcLPe+ioM
# SJIB+Jc9NGyu09lOyoRFcNCSUxaIhdxZ0gIkWSTu7mNw0zzQvdaeLKbmQol9mT/e
# MC89mEC+uKhIeE1QXWkzHXcE3G6xFdJq48i4wBHaNnH1EPkeC3dX7WLZ7YrYthFr
# Ff9knhgUB+srz6vEUYFMGM6p9gPfX6ZCGpngD5a1KTU+Hk5wQD3Rp0HTt7hYTiuC
# +aMGJw4NAqvrF+PQ/l9FPGJo5huSiG/fMDIzxbolCjrQ6P6i+sU+ldYIUmgUiBBS
# f5Rk6jL5PompYm714fgHsDAMIzpToWgBWJxdC79hkE/H4xvBPf0up6qAdc4zsvyC
# hT+RMUy3DBdik0q/iw/VBS9GV73zwWoMe7lBmFkCjWzyDKfpd7uAx6iIxwnAg52h
# iPna3U36QanRRBgyCKNxU5YYs36ciAokeQlIC/Qe5LjOtq0FNHVz+SdZswBHdSEu
# x/OZIWoSnRsdnCVvOYu3dRBf67OPCx3zPMFLAH3VBbAZJuxgTtLKINQfEa/Iq/fS
# VU4njbMfJoLYeSSC+S57mkaYRMuM5A5U6JyQImc/OZFoLKisrK3w1ANiwrFMffxw
# 7T5RG/uyuUVL6Jl67SZon3vk
# SIG # End signature block
