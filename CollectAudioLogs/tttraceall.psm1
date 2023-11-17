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
    if ($null -eq $adg)
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
# MIInwQYJKoZIhvcNAQcCoIInsjCCJ64CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBH2B+xJ6KdAWj1
# NkUUqW3UEa0vfOKIGIpjWRd91hEszqCCDXYwggX0MIID3KADAgECAhMzAAADTrU8
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGaEwghmdAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAANOtTx6wYRv6ysAAAAAA04wDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIMMfgT0odADmrtA2HgaG7ttq
# kGZlk9Y/Bd48/TBaoedCMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQBTc7iwdN3qmyeHUPS6fWx02Qq1HuzIhMcWgNdfPQvp91iGnfVnLH67
# NRErCvtiMuJh59W4tJotXuJahyHDyjqmtP+uoc008Q89DuxH4UcHLq9pTuz8Gaeh
# 2IblcdHno2NT8lI5e5PYJU+3FdJ52qVzwXDWri/YXjzR7dt8a8OUuzcSRw5kYYbb
# guvk2FY+AEL6fPDUgjFUBQLWOOoFjGGlzotoLjPjZ89QwMzmEPujuwUmMb7Qih5r
# E8adf27f0Af/kmbsZVkT5QwjcErfEpq4zkwT9uJsIBvfOzXQnM2gh/MSYn0BJuXR
# 5erFkvIvUcg/uzbfnJzBR0dL3Mip4dtIoYIXKTCCFyUGCisGAQQBgjcDAwExghcV
# MIIXEQYJKoZIhvcNAQcCoIIXAjCCFv4CAQMxDzANBglghkgBZQMEAgEFADCCAVkG
# CyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIGRPfCO9AptCO4IrOczhaPPQq5Iwu93ecy8cn8B3R3nnAgZlQrsD
# aDwYEzIwMjMxMTE2MjMzNTA1LjA1OVowBIACAfSggdikgdUwgdIxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJ
# cmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBF
# U046MDg0Mi00QkU2LUMyOUExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFNlcnZpY2WgghF4MIIHJzCCBQ+gAwIBAgITMwAAAdqO1claANERsQABAAAB2jAN
# BgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0y
# MzEwMTIxOTA2NTlaFw0yNTAxMTAxOTA2NTlaMIHSMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBP
# cGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNOOjA4NDIt
# NEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAk5AGCHa1UVHWPyNADg0N
# /xtxWtdI3TzQI0o9JCjtLnuwKc9TQUoXjvDYvqoe3CbgScKUXZyu5cWn+Xs+kxCD
# bkTtfzEOa/GvwEETqIBIA8J+tN5u68CxlZwliHLumuAK4F/s6J1emCxbXLynpWzu
# wPZq6n/S695jF5eUq2w+MwKmUeSTRtr4eAuGjQnrwp2OLcMzYrn3AfL3Gu2xgr5f
# 16tsMZnaaZffvrlpLlDv+6APExWDPKPzTImfpQueScP2LiRRDFWGpXV1z8MXpQF6
# 7N+6SQx53u2vNQRkxHKVruqG/BR5CWDMJCGlmPP7OxCCleU9zO8Z3SKqvuUALB9U
# aiDmmUjN0TG+3VMDwmZ5/zX1pMrAfUhUQjBgsDq69LyRF0DpHG8xxv/+6U2Mi4Zx
# 7LKQwBcTKdWssb1W8rit+sKwYvePfQuaJ26D6jCtwKNBqBiasaTWEHKReKWj1gHx
# DLLlDUqEa4frlXfMXLxrSTBsoFGzxVHge2g9jD3PUN1wl9kE7Z2HNffIAyKkIabp
# Ka+a9q9GxeHLzTmOICkPI36zT9vuizbPyJFYYmToz265Pbj3eAVX/0ksaDlgkkIl
# cj7LGQ785edkmy4a3T7NYt0dLhchcEbXug+7kqwV9FMdESWhHZ0jobBprEjIPJId
# g628jJ2Vru7iV+d8KNj+opMCAwEAAaOCAUkwggFFMB0GA1UdDgQWBBShfI3JUT1m
# E5WLMRRXCE2Avw9fRTAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBf
# BgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmww
# bAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUF
# BwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAuYNV1O24jSMA
# S3jU7Y4zwJTbftMYzKGsavsXMoIQVpfG2iqT8g5tCuKrVxodWHa/K5DbifPdN04G
# /utyz+qc+M7GdcUvJk95pYuw24BFWZRWLJVheNdgHkPDNpZmBJxjwYovvIaPJauH
# vxYlSCHusTX7lUPmHT/quz10FGoDMj1+FnPuymyO3y+fHnRYTFsFJIfut9psd6d2
# l6ptOZb9F9xpP4YUixP6DZ6PvBEoir9CGeygXyakU08dXWr9Yr+sX8KGi+SEkwO+
# Wq0RNaL3saiU5IpqZkL1tiBw8p/Pbx53blYnLXRW1D0/n4L/Z058NrPVGZ45vbsp
# t6CFrRJ89yuJN85FW+o8NJref03t2FNjv7j0jx6+hp32F1nwJ8g49+3C3fFNfZGE
# xkkJWgWVpsdy99vzitoUzpzPkRiT7HVpUSJe2ArpHTGfXCMxcd/QBaVKOpGTO9Kd
# ErMWxnASXvhVqGUpWEj4KL1FP37oZzTFbMnvNAhQUTcmKLHn7sovwCsd8Fj1QUvP
# iydugntCKncgANuRThkvSJDyPwjGtrtpJh9OhR5+Zy3d0zr19/gR6HYqH02wqKKm
# Hnz0Cn/FLWMRKWt+Mv+D9luhpLl31rZ8Dn3ya5sO8sPnHk8/fvvTS+b9j48iGanZ
# 9O+5Layd15kGbJOpxQ0dE2YKT6eNXecwggdxMIIFWaADAgECAhMzAAAAFcXna54C
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
# ahC0HVUzWLOhcGbyoYIC1DCCAj0CAQEwggEAoYHYpIHVMIHSMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJl
# bGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1MgRVNO
# OjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBCoh8hiWMdRs2hjT/COFdGf+xIDaCBgzCB
# gKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBBQUA
# AgUA6QD+pDAiGA8yMDIzMTExNzA0NDgzNloYDzIwMjMxMTE4MDQ0ODM2WjB0MDoG
# CisGAQQBhFkKBAExLDAqMAoCBQDpAP6kAgEAMAcCAQACAgQ1MAcCAQACAhIeMAoC
# BQDpAlAkAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEA
# AgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQEFBQADgYEAiVUjm+95AtZCfepE
# v9AbQbuwh3ai2i71TpLk4apj2aFW1vFaYAHoj/1KmV26oM6lWbtH/rBCTspHl1oW
# NEHexF4G5fprnUBEoCjQi+JRsCmoV6lku1ofOpnwnuEDEUObGS42Oc8zjOUleLaj
# X/EbSyFxf8YFdmj6P836X740q6wxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAdqO1claANERsQABAAAB2jANBglghkgBZQME
# AgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJ
# BDEiBCAno77fuIrH1FJKSh2YWT9F+6/VAjy1CYHw5VaKWaOapzCB+gYLKoZIhvcN
# AQkQAi8xgeowgecwgeQwgb0EICKlo2liwO+epN73kOPULT3TbQjmWOJutb+d0gI7
# GD3GMIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAHa
# jtXJWgDREbEAAQAAAdowIgQg2YN//TQ2ZFYAm5C0PqChr5y+UMlsw+eRfvNybOcD
# GTgwDQYJKoZIhvcNAQELBQAEggIAFLI92wy6LYKEh3jqKnILSHwq2dijXd6XI89g
# AdvZJXViKMzesJhuKhzDvcqzS1pwl7rWE92LTSKhhXgUuxVc7r74kSw6Qbexx8K7
# HlNzoT1psKbdNDN4gxjyQXn5WOuC2v1mO2xIDn1m9+LK6roMbORWRMZ6MudO/zo5
# 025C7wxmpUbhV/WYrooPr40inJE7UH14JdSIGAR0UY+pbqdWa8cpySzgNZV8vVve
# Hs8hH8FJiK8JEJrK6aX4itiWOU1umsEkW+iArTde8ZSMbG6EtLPG02rc1JtpInRn
# AavlXuS8RhbqLxwiFqRqJwg8Aj7Zy/j+v8tqexkwWQh6QTpaOhUG7xJylVplP7lF
# IS104r3FiekP2ni9NyfrotoJsVXB3/SZjQYdO02ggRqQmAGYDAjWAv61jg0ZZ/QA
# xIFvRmiNp8omlpZkmXVYu2xRcZPwa4wmR32JWDcgrkVMyA3jsPjzfbClSWv0rzcT
# xhVKFPLzLA7xmPbl+0Ww/Y4OJ3+V9+AeVdlGa26GOUhWzOUdf7ML1slUIQPHe5Gi
# 1eAls37kQGvTFM1tId/PxCsABGumUWQT9mDVirBX1pXhGu6TjdRK119MoGY4e5Wt
# U23dQNJC55qRDyxGxDOhHj3m4tw0tAdGeIpBokI0T2vDeT+0Vk+l7+VO2zBdRVP9
# oV8Rh3Y=
# SIG # End signature block
