---
page_type: sample
description: "The Microsoft SysVAD Virtual Audio Device Driver (SYSVAD) shows how to develop a WDM audio driver that exposes support for multiple audio devices."
languages:
- cpp
products:
- windows
- windows-wdk
urlFragment: sysvad-virtual-audio-device-driver-sample
---

# SysVAD Virtual Audio Device Driver Sample

> [!NOTE]
> With the [end of support for Windows 10 Mobile](https://support.microsoft.com/help/4484693/windows-10-mobile-end-of-support), the Phone Audio sample has been also removed from the SysVAD driver sample.

## Introduction

The Microsoft SysVAD Virtual Audio Device Driver (SYSVAD) shows how to develop a WDM audio driver that exposes support for multiple audio devices.

Some of these audio devices are embedded in the system (for example, speakers, microphone arrays) while others are pluggable (like headphones, Bluetooth headsets etc.). The driver uses WaveRT and audio offloading for rendering devices. The driver uses a "virtual audio device" instead of an actual hardware-based adapter, and highlights the different aspects of the audio offloading WDM audio driver architecture.

Driver developers can use the framework in this sample to provide support for various audio devices without concern for hardware dependencies. The framework includes implementations of the following interfaces:

- The *CAdapterCommon* interface gives the miniports access to virtual mixer hardware. It also implements the *IAdapterPowerManagement* interface.

- The *CMiniportTopologySYSVAD* interface is the base class for all sample topologies. It has very basic common functions. In addition, this class contains common topology property handlers.

The following table shows the features that are implemented in the various subdirectories of this sample.

| Directory | Description |
| --- | --- |
| TabletAudioSample | Endpoints that are present in TabletAudioSample driver. |
| EndpointsCommon | Common endpoint information that could be shared across different versions of the driver
| SwapAPO | Sample APO that installs onto endpoints exposed by the SysVAD sample driver and swaps the left and right channels. |
| DelayAPO | Sample APO that adds a delay to the input samples. |
| KwsAPO | Sample APO that uses KSPROPERTY_INTERLEAVEDAUDIO_FORMATINFORMATION to determine if the keyword spotter pin is interleaving loopback audio with the microphone audio and identify which channels contain loopback audio. If it is interleaved the APO will strip out the loopback audio and deliver only the microphone audio upstream. Because channel data is removed, the APO negotiates an output format which is different than the input format. |
| AecAPO | Sample capture MFX APO that implements Acoustic Echo Cancellation. This APO demonstrates the use of echo cancellation interfaces that an AEC APO uses to obtain reference audio for cancellation.  |
| KeywordDetectorAdapter | Sample Keyword Detector Adapter. |

For more information about the Windows audio engine, see [Hardware-Offloaded Audio Processing](https://docs.microsoft.com/windows-hardware/drivers/audio/hardware-offloaded-audio-processing), and note that audio hardware that is offload-capable replicates the architecture that is presented in the diagram shown in the topic.

## Build the sample

If you simply want to build this sample driver and don't intend to run or test it, then you do not need a target computer (also called a test computer). If, however, you would like to deploy, run and test this sample driver, then you need a second computer that will serve as your target computer. Instructions are provided in [Run the sample](#run-the-sample) to show you how to set up the target computer - also referred to as *provisioning* a target computer.

Perform the following steps to build this sample driver.

### Setup the development computer

For building the sample driver, the following components must be installed:
- Visual Studio,
- Windows SDK,
- Windows Driver Kit (WDK).

Please refer to [Download the Windows Driver Kit](https://docs.microsoft.com/windows-hardware/drivers/download-the-wdk) for instructions on how to download and install each one.

From the Visual Studio Installer, the following individual packages must be installed in order to build SysVAD:
- C++ ATL for latest v142 build tools \<arch\>
- C++ ATL for latest v142 build tools with Spectre Mitigations \<arch\>
- MSVC v142 - VS 2019 C++ \<arch\> build tools (Latest)
- MSVC v142 - VS 2019 C++ \<arch\> build tools Spectre-mitigated libs (Latest)

Where "\<arch\>" refers to your target architecture.

#### Configure the repository for Windows Implementation Library (WIL)

In order to build the project, it is necessary to include WIL. The Windows Driver Samples repository includes WIL as a Git submodule.

If it has not been done before (such as in a fresh clone), the following command should be run at the root of the repository:

`git submodule update --init`

This will populate a folder named *wil* at the root of the repository.

### Open the driver solution in Visual Studio

In Microsoft Visual Studio, click *File* \> *Open* \> *Project/Solution...* and navigate to the folder that contains the sample files (for example, *C:\Windows-driver-samples\audio\sysvad*). Double-click the *sysvad* solution file.

In Visual Studio locate the Solution Explorer. (If this is not already open, choose *Solution Explorer* from the *View* menu.) In Solution Explorer, you can see one solution that has eight projects.

### Set the sample's configuration and platform

Right-click *Solution 'sysvad' (8 of 8 projects)* once more and choose *Configuration Manager*. Make sure that the configuration and platform settings are the same for the eight projects. By default, the configuration is set to *Debug*, and the platform is set to *Win32* for all the projects. If you make any configuration and/or platform changes for one project, you must make the same changes for all the remaining projects.

### Build the sample using Visual Studio

In Visual Studio, click *Build* \> *Build Solution*.

### Locate the built driver package

In File Explorer, navigate to the folder that contains the sample files. For example, you would navigate to *C:\\Windows-driver-samples\\audio\\sysvad*, if that's the folder you specified in the preceding Step 1.

In the folder, the location of the driver package varies depending on the configuration and platform settings that you selected in the *Configuration Manager*. For example, if you left the default settings unchanged, then the built driver package will be saved to a folder named *Debug* inside the same folder as the sample files. Double-click the folder for the built driver package, and then double-click the folder named *package*.

The package should contain these files:

| File | Description |
| --- | --- |
| TabletAudioSample.sys | The driver file. |
| DelayAPO.dll | The delay APO. |
| KeywordDetectorContosoAdapter.dll | Sample Keyword detector adapter. |
| AecApo.dll | The AEC APO. |
| KWSApo.dll | The KWS APO. |
| SwapAPO.dll | The swap APO. |
| sysvad.cat | A signed catalog file, which serves as the signature for the entire package. |
| ComponentizedApoSample.inf | A componentized information (INF) file that installs an APO device. |
| ComponentizedAudioSample.inf | A componentized information (INF) file that contains information needed to install the Tablet Audio Sample driver. |
| ComponentizedAudioSampleExtension.inf | An extension information (INF) file that extends the Tablet Audio Sample driver functionality by associating an APO device to it. |
| TabletAudioSample.inf | A non-componentized information (INF) file that contains information needed to install the driver. |

For more information on extension INF files, see [Using an extension INF file](https://docs.microsoft.com/windows-hardware/drivers/install/using-an-extension-inf-file).

## Run the sample

The computer where you install the driver is called the *target computer* or the *test computer*. Typically this is a separate computer from the computer on which you develop and build the driver package. The computer where you develop and build the driver is called the *host computer*.

The process of moving the driver package to the target computer and installing the driver is called *deploying* the driver. You can deploy the TabletAudioSample sample driver automatically or manually.

### Setup the target computer

First of all, install the latest [Windows Driver Kit](https://docs.microsoft.com/windows-hardware/drivers/download-the-wdk) (WDK) on the target computer.

Before you manually deploy a driver, you must prepare the target computer by turning on test signing and by installing a certificate. You also need to locate the DevCon tool in your WDK installation. After that you're ready to run the built driver sample.

Open a Command Prompt window as Administrator. Then enter the following command:

`bcdedit /set TESTSIGNING ON`

and reboot the target computer.

> [!IMPORTANT]
> Before using BCDEdit to change boot information you may need to temporarily suspend Windows security features such as BitLocker and Secure Boot on the test PC.

Re-enable these security features when testing is complete and appropriately manage the test PC, when the security features are disabled.

After rebooting, navigate to the Tools folder in your WDK installation and locate the DevCon tool. For example, look in the following folder:

C:\\Program Files (x86)\\Windows Kits\\10\\Tools\\x64\\devcon.exe

Copy *devcon.exe* to a folder on the target computer where it is easier to find. For example, create a *C:\\Tools* folder and copy *devcon.exe* to that folder.

Create a folder on the target for the built driver package (for example, *C:\\SysvadDriver*). Copy all the files from the built driver package on the host computer and save them to the folder that you created on the target computer.

Create a folder on the target computer for the certificate created by the build process. For example, you could create a folder named *C:\\Certificates* on the target computer, and then copy *package.cer* to it from the host computer. You can find this certificate in the same folder on the host computer, as the *package* folder that contains the built driver files. On the target computer, right-click the certificate file, and click *Install*, then follow the prompts to install the test certificate.

If you need more detailed instructions for setting up the target computer, see [Preparing a Computer for Manual Driver Deployment](https://docs.microsoft.com/windows-hardware/drivers/develop/preparing-a-computer-for-manual-driver-deployment).

#### A note on signatures

Since most of these binary files are executed in kernel mode, it is important that they are signed and, optionally, to have a kernel debugger attached.

Without any signature or kernel debugger, the driver will not be installed in the target computer. With a kernel debugger attached, the driver can be installed and the driver files (.sys extension) would be loaded, but any user mode files (.dll files) will not be loaded.

The only way of installing and executing the whole driver sample is to have all the files (.sys, .dll and .cat) signed with a trusted certificate. This will allow the entire driver to be loaded even without a kernel debugger attached.

For more information on the subject, see [Driver signing](https://docs.microsoft.com/windows-hardware/drivers/install/driver-signing).

### Install the driver

#### Componentized INF files

The TabletAudioSample driver package contains a sample driver, an extension sample and an APO software component. The following instructions show you how to install and test the sample driver, the APO component and then the extension to apply the software component to the driver.

First, the base INF, *ComponentizedAudioSample.inf*, has to be installed. To install it, open a Command Prompt window as administrator on the target computer, then navigate to your driver package folder and enter the following command:

`devcon install ComponentizedAudioSample.inf Root\Sysvad_ComponentizedAudioSample`

If you get an error message about *devcon* not being recognized, try adding the path to the *devcon* tool. For example, if you copied it to a folder called *C:\\Tools*, then try using the following command:

`C:\\tools\\devcon install ComponentizedAudioSample.inf Root\Sysvad_ComponentizedAudioSample`

This installs the base Tablet Audio Sample driver with a hardware ID of "Root\Sysvad_ComponentizedAudioSample".

Then, either the extension INF (*ComponentizedAudioSampleExtension.inf*) or the APO INF (*ComponentizedApoSample.inf*) can be installed.

If the extension INF is installed first, it will create a new component called *Audio Proxy APO Sample*. Until the APO is installed, this component will appear in Device Manager under the section of Software Components, because it does not have a driver attached yet. The driver is attached by installing the APO INF.

If the APO is installed first, it will install a driver, but it will not create a device, so the APO will not be visible in Device Manager until the extension INF creates a software component that will then have the APO driver installed.

Both extension and APO INFs can be installed by right-clicking on any of the files and selecting "install" from the menu.

Once the three componentized INF files are installed, an APO device should appear in Device Manager and the *Microsoft Virtual Audio Device (WDM) - Tablet Audio Sample* device should now be named *SYSVAD (with APO Extensions)*.

For more detailed instructions, see [Provision a computer for driver deployment and testing](https://docs.microsoft.com/windows-hardware/drivers/gettingstarted/provision-a-target-computer-wdk-8-1).

#### Single INF files

TabletAudioSample also contains an INF file, tabletaudiosample.inf, which install the sample driver using a single INF file.

Componentized driver packages are required since Windows 10 1809 release. However, for backward compatibility, instructions on how to install the TabletAudioSample.inf are provided below.

On the target computer, open a Command Prompt window as Administrator. Navigate to your driver package folder, and enter the following command:

`devcon install TabletAudioSample.inf Root\Sysvad_TabletAudioSample`

After successfully installing the sample driver, you're now ready to test it.

### Test the driver

On the target computer, in a Command Prompt window, enter *devmgmt.msc* to open Device Manager. In Device Manager, on the *View* menu, choose *Devices by type*. In the device tree, locate *SYSVAD (with APO Extensions)*. This is typically under the *Sound, video and game controllers* node.

On the target computer, open Control Panel and navigate to *Hardware and Sound* \> *Manage audio devices*. In the Sound dialog box, select the speaker icon labeled as *SYSVAD (with APO Extensions)*, then click *Set Default*, but do not click *OK*. This will keep the Sound dialog box open.

Locate an MP3 or other audio file on the target computer and double-click to play it. Then in the Sound dialog box, verify that there is activity in the volume level indicator associated with the *SYSVAD (with APO Extensions)* driver.

## HLK testing

The sample uploaded here is tested using the latest HLK version available to make sure it passes all audio tests in the current playlist. However, since it is a virtual audio driver it does not implement audio mixing and simulates capture and loopback by generating a tone. Given these limitations, there are some HLK tests that are expected to fail because they rely on the described functionality.

In the case of audio tests, one of these exceptions is the Hardware Offload of Audio Processing Test. This test is aimed at devices that support offload capabilities and performs checks to make sure that the device complies with the appropiate requirements. In the particular case of SysVAD, this test will fail for endpoints with offload and loopback.

For endpoints with offload, the test will fail because the driver includes offload pins but it does not implement a mixer with volume, mute and peak meter nodes, etc. For the case of endpoints with loopback, the test will fail because the driver simulates loopback by returning a sine tone instead of performing real mixing of streams in host and/or offload pins.