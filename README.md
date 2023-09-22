# Project

This project will contain open source tools and utilities shared by the Microsoft Windows Audio team.

## CollectAudioLogs

This is a script for collecting audio logs, which are used when diagnosing audio problems. This till is primarily use in collaboration with a developer on the Windows Audio team, though the data may be useful for audio driver developers and software venders that are creating [Audio Processing Objects (APOs)](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/audio-processing-object-architecture)

The logs collected by this script are mostly identical to the logs collected by feedback hub. To collect audio logs using the feedback hub, you would first go into Feedback Hub Settings and enable "save a local copy of diagnostics when giving feedback." You would then file a feedback under "Devices and Drivers"->"Audio and Sound" with the "Recreate my problem" option.

There are two notable exceptions with the logs collected using this script versus the logs collected using Feedback Hub. First, the logs collected by this script are more compact than the files collected by feedback hub, having all of the log files in a flatter directory structure makes it a little more friendly for manual analysis. Second, this script has the option to collect [Time Travel Traces](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/time-travel-debugging-overview) of the Windows Audio Services. Feedback hub does not have the ability to collect Time Travel Traces.

Some important things to keep in mind when collecting Time Travel Traces. In order to collect Time Travel Traces of Windows services, some security features on these services need to be disabled. This script queries if the security features are enabled for the services, disables the security features, restarts the services for collecting the Time Travel Traces, and then restores the security settings and restarts the services again after tracing is completed. In the event the script is interruped in the middle of collection, it is important to note that Shadowstacks and CET may be disabled for services running on the system. It is possible that disabling and restarting the service will lose system state and remove the ability to reproduce a bug, so it is best to collect logs or file a feedback without Time Travel Tracing first, in order to ensure that some logs are collected and the bug is not lost. Also, Time Travel Tracing is CPU intensive, and it is expected that when enabled there may be audio glitching and other audible artifacts caused by slow audio processing. Time Travel Tracing should not be collected when investigating issues with audio quality, normal audio feedback logs are sufficient for diagnosing audio glitch and quality problems.

When will the information in these logs be useful and what is collected? I'm glad you asked. :)

When you open the .zip file, you will see a repro.etl file. This file can be viewed in [Windows Performance Analyzer](https://learn.microsoft.com/en-us/windows-hardware/test/wpt/getting-started--windows-performance-analyzer--wpa-). This file contains logging from the logging providers specified in the .wprp file included with the script. This includes the logging providers for the windows audio services, along with many of the providers for audio drivers and APOs. This is a "circular" log, when the specified log size is reached, newer log entries overwrite older log entries. There is a lot of logging collected for each frame of audio data when audio playback or capture is running. The result is that this log often only collects about 30 to 60 seconds worth of activity by the audio services before overwriting earlier events. For issues which require multiple tries to reproduce the problem, the log will not grow unbounded. Just be sure to stop log collection within 30 seconds of the issue being reproduced. 

If Time Travel Tracing is enabled, you will see three .run and .out files for the Time Travel Trace. The two svchost.run files are for AudioSrv and AudioEndpointBuilder, audiodg.run is for AudioDG. Audio Processing Objects (APOs) run inside of the [AudioDG.exe](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/windows-audio-architecture) process, and Time Travel Traces can be invaluable for software vendors diagnosing failures with their APO's. Also, when collaborating with a developer on the Windows audio team, time travel traces of AudioSrv and AudioEndpointBuilder can help with quickly identifying and resolving issues.

Finally, when you indicate to collect "additional system information," there are various other files containing PNP logs and registry keys which are interesting to the audio system, such as the MMDevice registry keys which contain information about all of the audio endpoints in the system, and the pnpstate.pnp which contains driver installation information from the PNP system. Most of these files are plain text. The PNP export contains the same information that is visible in the device manager and event viewer, including driver installation dates, driver versions, driver inf's, event viewer data for PNP, and driver state/failure information. Often the information contained in these logs are necessary for interpreting the logging collected in the repro.etl file, so it is recommended to always collect this information at least once. When collecting a sequence of logs to demonstrate a problem, the additional system information is typically only needed for one collection, the remainder of logs can contain only the repro.etl.


## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
