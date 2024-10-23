function SetIdleTimeOnDevice
{
    param($device, [ref] $finalDeviceSettings)

    # A value of 0,0,0,0 will disable power savings
    $disableValue = [byte[]](0x0,0x0,0x0,0x0)

    # The default value is 30,0,0,0, giving a 30 second idle timeout.
    $restoreValue = [byte[]](0x1e,0x0,0x0,0x0)

    $setValue = $disableValue
	$setPerformance = $false
	$setConservation = $false

    # retrieve the peripheral registry path and the configured idle times
    $DriverRegistryPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Class\" + (get-pnpdeviceproperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_Driver).Data + "\PowerSettings"
    $DriverRegistry = Get-Item -Path $DriverRegistryPath
    $currentPerformanceSetting = Get-ItemProperty $DriverRegistry.PSPath -Name PerformanceIdleTime
    $currentConservationSetting = Get-ItemProperty $DriverRegistry.PSPath -Name ConservationIdleTime


    # If there are multiple peripherals, there is no way to programmatically identify whether this peripheral is affected,
    # prompt the user so they can tell us whether or not to modify the power settings for it.
    $deviceFriendlyName = $device.FriendlyName.ToString()
    do
    {
        $response = Read-Host "Do you wish to modify the power settings for `"$deviceFriendlyName`" (y/n)"
    }
    while (($response.Trim().ToLower())[0] -ne 'y' -and ($response.Trim().ToLower())[0] -ne 'n')
    Write-Host

    if (($response.Trim().ToLower())[0] -eq 'y')
    {
	    # determine if it has already been set to disable idle timeout
	    $performanceCompareResult = Compare-Object -ReferenceObject $currentPerformanceSetting.PerformanceIdleTime -DifferenceObject $setValue
	    $conservationCompareResult = Compare-Object -ReferenceObject $currentConservationSetting.ConservationIdleTime -DifferenceObject $setValue

	    # if performance idle timeout is not currently disabled, then we are going to disable it.
		if ($performanceCompareResult.Count -ne 0)
		{
			$setPerformance = $true

			Write-Host "Disabling power savings while on AC for this device."
			Write-Host
		}
		else
		{
			Write-Host "Power savings already disabled for AC for this device."
			Write-Host
		}

	    # whether performance is disabled or not, if conservation is not currently disabled, see if that's what the
	    # user wants to disable
		if ($conservationCompareResult.Count -ne 0)
		{
	        # prompt the user to see if they also wish to disable the idle timeout for DC
	        do
	        {
	            $response = Read-Host "Do you wish to disable power savings when on DC power? (y/n)"
	        }
	        while (($response.Trim().ToLower())[0] -ne 'y' -and ($response.Trim().ToLower())[0] -ne 'n')
	        Write-Host

	        if (($response.Trim().ToLower())[0] -eq 'y')
	        {
	        	$setConservation = $true
			}
		}
		else
		{
			Write-Host "Power savings already disabled for DC for this device."
			Write-Host
		}

		# the user didn't want to disable anything, see if they want to restore the original settings
		if (($setPerformance -eq $false) -and ($setConservation -eq $false))
		{
		    do
	        {
	            $response = Read-Host "Do you wish to restore the original power settings for this peripheral? (y/n)"
	        }
	        while (($response.Trim().ToLower())[0] -ne 'y' -and ($response.Trim().ToLower())[0] -ne 'n')
	        Write-Host

	        if (($response.Trim().ToLower())[0] -eq 'y')
	        {
				# they do, so we set both performance and conservaton to the restored value
	        	$setValue = $restoreValue
	        	$setPerformance = $true
	        	$setConservation = $true
	        }
		}

		# if something needs to be set, set it, otherwise we're finished
		if (($setPerformance -eq $true) -or ($setConservation -eq $true))
	    {
			Write-Host "Applying settings to" $device.FriendlyName.ToString()

	        Disable-PnpDevice -Confirm:$false -InstanceId $device.InstanceId
			if ($setPerformance -eq $true)
			{
	            Set-ItemProperty $DriverRegistry.PSPath -Name PerformanceIdleTime -Value $setValue -Type Binary
	        }
			if ($setConservation -eq $true)
			{
			    Set-ItemProperty $DriverRegistry.PSPath -Name ConservationIdleTime -Value $setValue -Type Binary
	        }
	        Enable-PnpDevice -Confirm:$false -InstanceId $device.InstanceId

			Write-Host "Finished"
			Write-Host
	    }
	}

    $newPerformanceSetting = Get-ItemProperty $DriverRegistry.PSPath -Name PerformanceIdleTime
    $newConservationSetting = Get-ItemProperty $DriverRegistry.PSPath -Name ConservationIdleTime
    $hardwareId = get-pnpdeviceproperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_HardwareIds

	$deviceInfo = $deviceFriendlyName + ";" + $hardwareId.Data[0] + ";" + $newPerformanceSetting.PerformanceIdleTime + ";" + $newConservationSetting.ConservationIdleTime + "`r`n"

	$finalDeviceSettings.Value += $deviceInfo
}

function SetIdleTimeOnDevices
{
    # we're looking for only USB media class drivers which are present, we then filter this list down to
    # only the devices using the inbox audio class driver. These power settings are only applicable to the
    # inbox audio class driver.

	$finalDeviceSettings = [System.Array]@()

	$devicesProcessed = 0

    $devices = get-pnpdevice -Class Media -PresentOnly -InstanceId "USB*"
    foreach ($device in $devices)
    {
        $includedInfs = get-pnpdeviceproperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_DriverIncludedInfs
        $infPath = get-pnpdeviceproperty -InstanceId $device.InstanceId -KeyName DEVPKEY_Device_DriverInfPath
        if ( $includedInfs.Data.Contains("wdma_usb.inf") -or $infPath.Data.Contains("wdma_usb.inf"))
        {
			$devicesProcessed++
            # this device is either directly using the inbox class driver, or is indirectly using the inbox class driver through
            # an IHV wrapper driver.
            SetIdleTimeOnDevice $device ([ref] $finalDeviceSettings)
        }
    }

	if ($devicesProcessed -eq 0)
	{
		Write-Host "No applicable USB Audio Class 1 device present on system"
		Write-Host
	}
	else
	{
		Write-Host $devicesProcessed "USB Audio Class 1 device(s) processed."
		Write-Host "Final Device Settings:"
		Write-Host ""$finalDeviceSettings
		Write-Host
	}
}

cls

Write-Host "This tool modifies the AC power settings, and optionally the DC power settings, for a USB Audio peripheral that is using the USB audio class driver."
Write-Host
Write-Host "The peripheral must be plugged in prior to running this tool."
Write-Host
do
{
    $response = Read-Host "Do you wish to continue? (y/n)"
}
while (($response.Trim().ToLower())[0] -ne 'y' -and ($response.Trim().ToLower())[0] -ne 'n')
Write-Host

if (($response.Trim().ToLower())[0] -eq 'y')
{
    SetIdleTimeOnDevices
}


# SIG # Begin signature block
# MIIoLwYJKoZIhvcNAQcCoIIoIDCCKBwCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCArdNb+Q7rZ2dg7
# omJVhlf7VpgrUNVYzXDuF2DE5SToW6CCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
# Bv9XKydyAAAAAAQEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjQwOTEyMjAxMTE0WhcNMjUwOTExMjAxMTE0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC0KDfaY50MDqsEGdlIzDHBd6CqIMRQWW9Af1LHDDTuFjfDsvna0nEuDSYJmNyz
# NB10jpbg0lhvkT1AzfX2TLITSXwS8D+mBzGCWMM/wTpciWBV/pbjSazbzoKvRrNo
# DV/u9omOM2Eawyo5JJJdNkM2d8qzkQ0bRuRd4HarmGunSouyb9NY7egWN5E5lUc3
# a2AROzAdHdYpObpCOdeAY2P5XqtJkk79aROpzw16wCjdSn8qMzCBzR7rvH2WVkvF
# HLIxZQET1yhPb6lRmpgBQNnzidHV2Ocxjc8wNiIDzgbDkmlx54QPfw7RwQi8p1fy
# 4byhBrTjv568x8NGv3gwb0RbAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU8huhNbETDU+ZWllL4DNMPCijEU4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMjkyMzAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIjmD9IpQVvfB1QehvpC
# Ge7QeTQkKQ7j3bmDMjwSqFL4ri6ae9IFTdpywn5smmtSIyKYDn3/nHtaEn0X1NBj
# L5oP0BjAy1sqxD+uy35B+V8wv5GrxhMDJP8l2QjLtH/UglSTIhLqyt8bUAqVfyfp
# h4COMRvwwjTvChtCnUXXACuCXYHWalOoc0OU2oGN+mPJIJJxaNQc1sjBsMbGIWv3
# cmgSHkCEmrMv7yaidpePt6V+yPMik+eXw3IfZ5eNOiNgL1rZzgSJfTnvUqiaEQ0X
# dG1HbkDv9fv6CTq6m4Ty3IzLiwGSXYxRIXTxT4TYs5VxHy2uFjFXWVSL0J2ARTYL
# E4Oyl1wXDF1PX4bxg1yDMfKPHcE1Ijic5lx1KdK1SkaEJdto4hd++05J9Bf9TAmi
# u6EK6C9Oe5vRadroJCK26uCUI4zIjL/qG7mswW+qT0CW0gnR9JHkXCWNbo8ccMk1
# sJatmRoSAifbgzaYbUz8+lv+IXy5GFuAmLnNbGjacB3IMGpa+lbFgih57/fIhamq
# 5VhxgaEmn/UjWyr+cPiAFWuTVIpfsOjbEAww75wURNM1Imp9NJKye1O24EspEHmb
# DmqCUcq7NqkOKIG4PVm3hDDED/WQpzJDkvu4FrIbvyTGVU01vKsg4UfcdiZ0fQ+/
# V0hf8yrtq9CkB8iIuk5bBxuPMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGg8wghoLAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCggbAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIKT1iaWm5GFYq+3PM8drfqum
# fVxd2LtgUp1XmhK7ZpnvMEQGCisGAQQBgjcCAQwxNjA0oBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEcgBpodHRwczovL3d3dy5taWNyb3NvZnQuY29tIDANBgkqhkiG9w0B
# AQEFAASCAQApKW2oAz4nfRMn5FVLIMlHmj2xZ8NIijBC3ELFmZOgYI/dZy4wwwGi
# f+DJkK6hNQP7k8MubEaoWieOyNyNsXexxAdRvYPFheD73WVgl9g2XPOV+oxgmiaz
# ZtljSNC+hyn/KcGKC1WrahirUcthjAUGKHZKOB2P/ErYIFGjTYJ/b/HjrlZKUUP8
# 59QjxcyKswr+7BmeSmaNYjslPgJikJt1cUlyynfgMlUBnnXLtJlyF3GF1UhnUs+V
# Z862JvlPEUhfyduVLCP6qxfTJ7oR4S7e1qhjMj+pGNLJfzzX0MRqLs9hEtN/+e0u
# jdnkRDaU8RW/eP4ExMR63PhHqUyFRiotoYIXlzCCF5MGCisGAQQBgjcDAwExgheD
# MIIXfwYJKoZIhvcNAQcCoIIXcDCCF2wCAQMxDzANBglghkgBZQMEAgEFADCCAVIG
# CyqGSIb3DQEJEAEEoIIBQQSCAT0wggE5AgEBBgorBgEEAYRZCgMBMDEwDQYJYIZI
# AWUDBAIBBQAEIPsmHeTzr+qatmGa69bWN+xJRBLxBogM6LbLIIv2mtFiAgZnB83H
# vW8YEzIwMjQxMDIyMjMyMDA1LjIwN1owBIACAfSggdGkgc4wgcsxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBB
# bWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpBMDAw
# LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZaCCEe0wggcgMIIFCKADAgECAhMzAAAB6+AYbLW27zjtAAEAAAHrMA0GCSqGSIb3
# DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
# BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTIzMTIwNjE4
# NDUzNFoXDTI1MDMwNTE4NDUzNFowgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlv
# bnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpBMDAwLTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAMEVaCHaVuBXd4mnTWiqJoUG5hs1zuFIqaS28nXk
# 2sH8MFuhSjDxY85M/FufuByYg4abAmR35PIXHso6fOvGegHeG6+/3V9m5S6AiwpO
# cC+DYFT+d83tnOf0qTWam4nbtLrFQMfih0WJfnUgJwqXoQbhzEqBwMCKeKFPzGug
# lZUBMvunxtt+fCxzWmKFmZy8i5gadvVNj22el0KFav0QBG4KjdOJEaMzYunimJPa
# UPmGd3dVoZN6k2rJqSmQIZXT5wrxW78eQhl2/L7PkQveiNN0Usvm8n0gCiBZ/dcC
# 7d3tKkVpqh6LHR7WrnkAP3hnAM/6LOotp2wFHe3OOrZF+sI0v5OaL+NqVG2j8npu
# Hh8+EcROcMLvxPXJ9dRB0a2Yn+60j8A3GLsdXyAA/OJ31NiMw9tiobzLnHP6Aj9I
# XKP5oq0cdaYrMRc+21fMBx7EnUQfvBu6JWTewSs8r0wuDVdvqEzkchYDSMQBmEoT
# J3mEfZcyJvNqRunazYQlBZqxBzgMxoXUSxDULOAKUNghgbqtSG518juTwv0ooIS5
# 9FsrmV1Fg0Cp12v/JIl+5m/c9Lf6+0PpfqrUfhQ6aMMp2OhbeqzslExmYf1+QWQz
# NvphLOvp5fUuhibc+s7Ul5rjdJjOUHdPPzg6+5VJXs1yJ1W02qJl5ZalWN9q9H4m
# P8k5AgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUdJ4FrNZVzG7ipP07mNPYH6oB6uEw
# HwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKg
# UIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAw
# XjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9j
# ZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQw
# DAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8E
# BAMCB4AwDQYJKoZIhvcNAQELBQADggIBAIN03y+g93wL5VZk/f5bztz9Bt1tYrSw
# 631niQQ5aeDsqaH5YPYuc8lMkogRrGeI5y33AyAnzJDLBHxYeAM69vCp2qwtRozg
# 2t6u0joUj2uGOF5orE02cFnMdksPCWQv28IQN71FzR0ZJV3kGDcJaSdXe69Vq7Xg
# XnkRJNYgE1pBL0KmjY6nPdxGABhV9osUZsCs1xG9Ja9JRt4jYgOpHELjEFtGI1D7
# WodcMI+fSEaxd8v7KcNmdwJ+zM2uWBlPbheCG9PNgwdxeKgtVij/YeTKjDp0ju5Q
# slsrEtfzAeGyLCuJcgMKeMtWwbQTltHzZCByx4SHFtTZ3VFUdxC2RQTtb3PFmpnr
# +M+ZqiNmBdA7fdePE4dhhVr8Fdwi67xIzM+OMABu6PBNrClrMsG/33stEHRk5s1y
# QljJBCkRNJ+U3fqNb7PtH+cbImpFnce1nWVdbV/rMQIB4/713LqeZwKtVw6ptAdf
# tmvxY9yCEckAAOWbkTE+HnGLW01GT6LoXZr1KlN5Cdlc/nTD4mhPEhJCru8GKPae
# K0CxItpV4yqg+L41eVNQ1nY121sWvoiKv1kr259rPcXF+8Nmjfrm8s6jOZA579n6
# m7i9jnM+a02JUhxCcXLslk6JlUMjlsh3BBFqLaq4conqW1R2yLceM2eJ64TvZ9Ph
# 5aHG2ac3kdgIMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkq
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
# A1AwggI4AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMV
# AIAGiXW7XDDBiBS1SjAyepi9u6XeoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDqwh0uMCIYDzIwMjQxMDIyMTI0
# NjM4WhgPMjAyNDEwMjMxMjQ2MzhaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOrC
# HS4CAQAwCgIBAAICK5ICAf8wBwIBAAICE+YwCgIFAOrDbq4CAQAwNgYKKwYBBAGE
# WQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDAN
# BgkqhkiG9w0BAQsFAAOCAQEAlK6naOqrlFV4ykW1RM03VtRUm7SzzmsQnCeO9Fio
# wFokpdbIffDP2zzrXqwcXTDIWceTpLhAd4cV0C1OOmV5+FNzaQrD+xO0cgT4vsqr
# /NSOF7bqgsfoHs1pWQBZCYZp3rNJivYwNzxF9aBuLBdY5nvauwV81he9azi3az1H
# oQccg5JcrqssNbmHd32hyIjeK0YD9XJY+0VWpkKSbfyscDRkAv2EdCjkPGBI2ljJ
# 51dP+ps+xmvJkNCReqgNPrzruenTCbuHW3artq38WYndXpxJVvkFL3hEBV+BnjP/
# +i4OWuE6c1JToPFdmG6XnvRTNO2QCIGJsAeth/VZPP5CdjGCBA0wggQJAgEBMIGT
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB6+AYbLW27zjtAAEA
# AAHrMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQ
# AQQwLwYJKoZIhvcNAQkEMSIEILMvDwI9SAxAKo8m0ciWUZiWE6Rwme/hXC/KSVqg
# kDRBMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgzrdrvl9pA+F/xIENO2TY
# NJSAht2LNezPvqHUl2EsLPgwgZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQ
# Q0EgMjAxMAITMwAAAevgGGy1tu847QABAAAB6zAiBCCyYPxJy5YnZ9rQFDkzErSc
# QahLORM5EIYcNzE0UZsOgzANBgkqhkiG9w0BAQsFAASCAgBYDroEnOe6iuh+AOP1
# hzMYHQaZAOhcl5hg0jRLXJ4l8Sc7DrAvV1rbpSrAcTUb+aGZ7QDeFlE0byFdQW5u
# Og0Ikl7+Qf1bxvQrJJWzyccVA8FupdpOsWe9MOybWgqDSnsUw7NmmqIjwt4kNY2J
# frtOgkY/2U/W8RvEg1nw3QqzGRP3R9Pgq79aJGIy7Q3+EiDLyUFom8PCy3H8pNQQ
# znUsZKl9mtp9QzploZTMs6wRva2Ef6xUXX3GM1XIkBDsOjK0hlXq1xypjo508EJD
# YIj0EJZEZ1HXmnpF97qyMlqwKazd5/wVO3tiEz+8mpVMSbPPEgLzjMdFT6Jp+uoW
# QsiwyM4QCDNXBDdDBi36AzFJ5NQD2qFbx810DZZpUllemvGrtwPZoluIC9iJcP2/
# O6WCyP5BB/692CQtL0jWkTp/3NeR1fe8o/Rb2wfm/2C7af4RndUdDJMzM1AWBRhZ
# pl2v22U5scVCQw9sfDfI7hB7P1XDBVzYz0lXyfHh1fcytAEV16EFDXT31eZQSLEv
# 1CxqgXkHWuh9Cr4QF9kguuPFHytilsKsUA7n+muC3uF5AHuCUSRjM6w2Z8NQ8wC1
# sS5sL3FKCe0/GEuenWsvGXExV6ftdwrLpJBu0K/FWMDI0f/R6TMSoWunb0zzUf2E
# HCVeLlTdqnmmx3SUMJe9k3LVcA==
# SIG # End signature block
