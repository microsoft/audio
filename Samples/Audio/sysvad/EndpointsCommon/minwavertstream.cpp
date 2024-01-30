#include <sysvad.h>
#include <limits.h>
#include <ks.h>
#include "simple.h"
#include "minwavert.h"
#include "minwavertstream.h"
#include "UnittestData.h"
#include "AudioModuleHelper.h"
#define MINWAVERTSTREAM_POOLTAG 'SRWM'

#pragma warning (disable : 4127)

//=============================================================================
// CMiniportWaveRTStream
//=============================================================================

//=============================================================================
#pragma code_seg("PAGE")
CMiniportWaveRTStream::~CMiniportWaveRTStream
( 
    void 
)
/*++

Routine Description:

  Destructor for wavertstream 

Arguments:

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();
    if (NULL != m_pMiniport)
    {
        if (m_pAudioModules)
        {
            m_pMiniport->FreeStreamAudioModules(m_pAudioModules, m_AudioModuleCount);
            m_pAudioModules = NULL;
            m_AudioModuleCount = 0;
        }
    
        if (m_bUnregisterStream)
        {
            m_pMiniport->StreamClosed(m_ulPin, this);
            m_bUnregisterStream = FALSE;
        }
        
        m_pMiniport->Release();
        m_pMiniport = NULL;
    }

    if (m_pDpc)
    {
        ExFreePoolWithTag( m_pDpc, MINWAVERTSTREAM_POOLTAG );
        m_pDpc = NULL;
    }

    if (m_pTimer)
    {
        ExFreePoolWithTag( m_pTimer, MINWAVERTSTREAM_POOLTAG );
        m_pTimer = NULL;
    }

    if (m_pbMuted)
    {
        ExFreePoolWithTag( m_pbMuted, MINWAVERTSTREAM_POOLTAG );
        m_pbMuted = NULL;
    }

    if (m_plVolumeLevel)
    {
        ExFreePoolWithTag( m_plVolumeLevel, MINWAVERTSTREAM_POOLTAG );
        m_plVolumeLevel = NULL;
    }

    if (m_plPeakMeter)
    {
        ExFreePoolWithTag( m_plPeakMeter, MINWAVERTSTREAM_POOLTAG );
        m_plPeakMeter = NULL;
    }

    if (m_pWfExt)
    {
        ExFreePoolWithTag( m_pWfExt, MINWAVERTSTREAM_POOLTAG );
        m_pWfExt = NULL;
    }
    if (m_pNotificationTimer)
    {
        ExDeleteTimer
        (
            m_pNotificationTimer, 
            TRUE, // Cancel the timer if it is currently set.
            TRUE, // Wait for the timer to finish expiring and for any callback to a ExTimerCallback routine to finish.
            NULL
         );
    }

    // Since we just cancelled the notification timer, wait for all queued 
    // DPCs to complete before we free the notification DPC.
    //
    KeFlushQueuedDpcs();

#ifdef SYSVAD_BTH_BYPASS
    ASSERT(m_SidebandOpen == FALSE);
    ASSERT(m_SidebandStarted == FALSE);
#endif  // SYSVAD_BTH_BYPASS

    DPF_ENTER(("[CMiniportWaveRTStream::~CMiniportWaveRTStream]"));
} // ~CMiniportWaveRTStream

//=============================================================================
#pragma code_seg("PAGE")

NTSTATUS CMiniportWaveRTStream::ReadRegistrySettings()
{
    PAGED_CODE();

    NTSTATUS                    ntStatus;
    PDRIVER_OBJECT              DriverObject;
    HANDLE                      DriverKey;

    RTL_QUERY_REGISTRY_TABLE    paramTable[] = {
        // QueryRoutine     Flags                                               Name                            EntryContext                            DefaultType                                                     DefaultData                                 DefaultLength
        { NULL,   RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK, L"HostCaptureToneFrequency",        &m_ulHostCaptureToneFrequency,          (REG_DWORD << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT) | REG_DWORD,  &m_ulHostCaptureToneFrequency,              sizeof(DWORD) },
        { NULL,   RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK, L"LoopbackCaptureToneFrequency",    &m_ulLoopbackCaptureToneFrequency,      (REG_DWORD << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT) | REG_DWORD,  &m_ulLoopbackCaptureToneFrequency,          sizeof(DWORD) },
        { NULL,   RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK, L"HostCaptureToneAmplitude",        &m_dwHostCaptureToneAmplitude,          (REG_DWORD << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT) | REG_DWORD,  &m_dwHostCaptureToneAmplitude,              sizeof(DWORD) },
        { NULL,   RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK, L"LoopbackCaptureToneAmplitude",    &m_dwLoopbackCaptureToneAmplitude,      (REG_DWORD << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT) | REG_DWORD,  &m_dwLoopbackCaptureToneAmplitude,          sizeof(DWORD) },
        { NULL,   RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK, L"HostCaptureToneDCOffset",         &m_dwHostCaptureToneDCOffset,           (REG_DWORD << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT) | REG_DWORD,  &m_dwHostCaptureToneDCOffset,               sizeof(DWORD) },
        { NULL,   RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK, L"LoopbackCaptureToneDCOffset",     &m_dwLoopbackCaptureToneDCOffset,       (REG_DWORD << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT) | REG_DWORD,  &m_dwLoopbackCaptureToneDCOffset,           sizeof(DWORD) },
        { NULL,   RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK, L"HostCaptureToneInitialPhase",     &m_dwHostCaptureToneInitialPhase,       (REG_DWORD << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT) | REG_DWORD,  &m_dwHostCaptureToneInitialPhase,           sizeof(DWORD) },
        { NULL,   RTL_QUERY_REGISTRY_DIRECT | RTL_QUERY_REGISTRY_TYPECHECK, L"LoopbackCaptureToneInitialPhase", &m_dwLoopbackCaptureToneInitialPhase,   (REG_DWORD << RTL_QUERY_REGISTRY_TYPECHECK_SHIFT) | REG_DWORD,  &m_dwLoopbackCaptureToneInitialPhase,       sizeof(DWORD) },
        { NULL,   0,                                                        NULL,                               NULL,                                   0,                                                              NULL,                                       0 }
    };

    DriverObject = WdfDriverWdmGetDriverObject(WdfGetDriver());
    DriverKey = NULL;
    ntStatus = IoOpenDriverRegistryKey(DriverObject, 
                                 DriverRegKeyParameters,
                                 KEY_READ,
                                 0,
                                 &DriverKey);

    if (!NT_SUCCESS(ntStatus))
    {
        return ntStatus;
    }

    ntStatus = RtlQueryRegistryValues(RTL_REGISTRY_HANDLE,
                                  (PCWSTR) DriverKey,
                                  &paramTable[0],
                                  NULL,
                                  NULL);

    if (!NT_SUCCESS(ntStatus)) 
    {
        DPF(D_VERBOSE, ("RtlQueryRegistryValues failed, using default values, 0x%x", ntStatus));
        //
        // Don't return error because we will operate with default values.
        //
    }

    if (DriverKey)
    {
        ZwClose(DriverKey);
    }

    return ntStatus;
}

NTSTATUS
CMiniportWaveRTStream::Init
( 
    _In_ PCMiniportWaveRT           Miniport_,
    _In_ PPORTWAVERTSTREAM          PortStream_,
    _In_ ULONG                      Pin_,
    _In_ BOOLEAN                    Capture_,
    _In_ PKSDATAFORMAT              DataFormat_,
    _In_ GUID                       SignalProcessingMode
)
/*++

Routine Description:

  Initializes the stream object.

Arguments:

  Miniport_ -

  Pin_ -

  Capture_ -

  DataFormat -

  SignalProcessingMode - The driver uses the signalProcessingMode to configure
    driver and/or hardware specific signal processing to be applied to this new
    stream.

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();

    PWAVEFORMATEX pWfEx = NULL;
    NTSTATUS ntStatus = STATUS_SUCCESS;

    m_pMiniport = NULL;
    m_ulPin = 0;
    m_bUnregisterStream = FALSE;
    m_bCapture = FALSE;
    m_ulDmaBufferSize = 0;
    m_pDmaBuffer = NULL;
    m_ulNotificationsPerBuffer = 0;
    m_KsState = KSSTATE_STOP;
    m_pTimer = NULL;
    m_pDpc = NULL;
    m_llPacketCounter = 0;
    m_ullPlayPosition = 0;
    m_ullWritePosition = 0;
    m_ullDmaTimeStamp = 0;
    m_hnsElapsedTimeCarryForward = 0;
    m_ullLastDPCTimeStamp = 0;
    m_hnsDPCTimeCarryForward = 0;
    m_ulDmaMovementRate = 0;
    m_byteDisplacementCarryForward = 0;
    m_bLfxEnabled = FALSE;
    m_pbMuted = NULL;
    m_plVolumeLevel = NULL;
    m_plPeakMeter = NULL;
    m_pWfExt = NULL;
    m_ullLinearPosition = 0;
    m_ullPresentationPosition = 0;
    m_ulContentId = 0;
    m_ulCurrentWritePosition = 0;
    m_ulLastOsReadPacket = ULONG_MAX;
    m_ulLastOsWritePacket = ULONG_MAX;
    m_IsCurrentWritePositionUpdated = 0;
    m_SignalProcessingMode = SignalProcessingMode;
    m_bEoSReceived = FALSE;
    m_bLastBufferRendered = FALSE;
    m_pAudioModules = NULL;
    m_AudioModuleCount = 0;

    m_ulHostCaptureToneFrequency = IsEqualGUID(SignalProcessingMode, AUDIO_SIGNALPROCESSINGMODE_RAW) ? 1000 : 2000;
    m_ulLoopbackCaptureToneFrequency = 3000; // 3 kHz (default)
    m_dwHostCaptureToneAmplitude = 50; 
    m_dwLoopbackCaptureToneAmplitude = 50; 
    m_dwHostCaptureToneDCOffset = 0; 
    m_dwLoopbackCaptureToneDCOffset = 0; 
    m_dwHostCaptureToneInitialPhase = 0; 
    m_dwLoopbackCaptureToneInitialPhase = 0; 


#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
    m_SidebandOpen = FALSE;
    m_SidebandStarted = FALSE;
#endif  // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)

    m_pPortStream = PortStream_;
    InitializeListHead(&m_NotificationList);
    m_ulNotificationIntervalMs = 0;

    // Initialize the spinlock to synchronize position updates
    KeInitializeSpinLock(&m_PositionSpinLock);

    m_pNotificationTimer = ExAllocateTimer(
         TimerNotifyRT,
         this,
         EX_TIMER_HIGH_RESOLUTION
    );
    if (!m_pNotificationTimer)
    {
        return STATUS_INSUFFICIENT_RESOURCES;
    }

    pWfEx = GetWaveFormatEx(DataFormat_);
    if (NULL == pWfEx) 
    { 
        return STATUS_UNSUCCESSFUL; 
    }

    m_pMiniport = reinterpret_cast<CMiniportWaveRT*>(Miniport_);
    if (m_pMiniport == NULL)
    {
        return STATUS_INVALID_PARAMETER;
    }
    m_pMiniport->AddRef();
    if (!NT_SUCCESS(ntStatus))
    {
        return ntStatus;
    }
    m_ulPin = Pin_;
    m_bCapture = Capture_;
    m_ulDmaMovementRate = pWfEx->nAvgBytesPerSec;

    m_pDpc = (PRKDPC)ExAllocatePool2(POOL_FLAG_NON_PAGED, sizeof(KDPC), MINWAVERTSTREAM_POOLTAG);
    if (!m_pDpc)
    {
        return STATUS_INSUFFICIENT_RESOURCES;
    }

    m_pWfExt = (PWAVEFORMATEXTENSIBLE)ExAllocatePool2(POOL_FLAG_NON_PAGED, sizeof(WAVEFORMATEX) + pWfEx->cbSize, MINWAVERTSTREAM_POOLTAG);
    if (m_pWfExt == NULL)
    {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    RtlCopyMemory(m_pWfExt, pWfEx, sizeof(WAVEFORMATEX) + pWfEx->cbSize);

    m_pbMuted = (PBOOL)ExAllocatePool2(POOL_FLAG_NON_PAGED, m_pWfExt->Format.nChannels * sizeof(BOOL), MINWAVERTSTREAM_POOLTAG);
    if (m_pbMuted == NULL)
    {
        return STATUS_INSUFFICIENT_RESOURCES;
    }

    m_plVolumeLevel = (PLONG)ExAllocatePool2(POOL_FLAG_NON_PAGED, m_pWfExt->Format.nChannels * sizeof(LONG), MINWAVERTSTREAM_POOLTAG);
    if (m_plVolumeLevel == NULL)
    {
        return STATUS_INSUFFICIENT_RESOURCES;
    }

    m_plPeakMeter = (PLONG)ExAllocatePool2(POOL_FLAG_NON_PAGED, m_pWfExt->Format.nChannels * sizeof(LONG), MINWAVERTSTREAM_POOLTAG);
    if (m_plPeakMeter == NULL)
    {
        return STATUS_INSUFFICIENT_RESOURCES;
    }

    //
    // Allocate stream audio module resources.
    //
    ntStatus = m_pMiniport->AllocStreamAudioModules(&SignalProcessingMode,
                                                    &m_pAudioModules,
                                                    &m_AudioModuleCount);
    if (!NT_SUCCESS(ntStatus))
    {
        return ntStatus;
    }

    if (m_bCapture)
    {
        ReadRegistrySettings();
            DWORD toneFrequency = 0;
            DWORD toneAmplitude = 0;
            DWORD toneDCOffset = 0;
            DWORD toneInitialPhase = 0;

            double toneAmplitudeDouble = 0;
            double toneDCOffsetDouble = 0;
            double toneInitialPhaseDouble = 0;

            if (m_pMiniport->IsLoopbackPin(Pin_))
            {
                //
                // If the tap-point attribute was specified, extract it.
                //
                if (m_pMiniport->IsLoopbackTapPointSupported() &&
                    (DataFormat_->Flags & KSDATAFORMAT_ATTRIBUTES))
                {
                    KSATTRIBUTE_AUDIOLOOPBACK_TAPPOINT tappoint = {0};

                    // The attributes are aligned (QWORD alignment) after the data format
                    PKSMULTIPLE_ITEM attributes = (PKSMULTIPLE_ITEM) (((PBYTE)DataFormat_) + ((DataFormat_->FormatSize + FILE_QUAD_ALIGNMENT) & ~FILE_QUAD_ALIGNMENT));
                    ntStatus = m_pMiniport->GetAttributeFromAttributeList(attributes,
                                                                          attributes->Size,
                                                                          &KSATTRIBUTEID_AUDIOLOOPBACK_TAPPOINT,
                                                                          (BYTE*)&tappoint,
                                                                          sizeof(tappoint));
                    if (NT_SUCCESS(ntStatus))
                    {
                        if (tappoint.TapPoint == AUDIOLOOPBACK_TAPPOINT_POSTVOLUMEMUTE)
                        {
                            m_ulLoopbackCaptureToneFrequency = 4000; // 4 kHz (post volume/mute tap point)
                        }
                    }
                    else if (ntStatus != STATUS_NOT_FOUND)
                    {
                        return ntStatus;
                    }
                }

                //
                // Loopbacks pins use a different frequency for test validation.
                //
                toneFrequency = m_ulLoopbackCaptureToneFrequency;
                toneAmplitude = m_dwLoopbackCaptureToneAmplitude;
                toneDCOffset  = m_dwLoopbackCaptureToneDCOffset;
                toneInitialPhase = m_dwLoopbackCaptureToneInitialPhase;
            }
            else
            {
                //
                // Init sine wave generator. To exercise the SignalProcessingMode parameter
                // this sample driver selects the frequency based on the parameter.
                //
                toneFrequency = m_ulHostCaptureToneFrequency;
                toneAmplitude = m_dwHostCaptureToneAmplitude;
                toneDCOffset  = m_dwHostCaptureToneDCOffset;
                toneInitialPhase = m_dwHostCaptureToneInitialPhase;
            }

            if (labs(toneAmplitude) > 100)
            {
                toneAmplitude = toneAmplitude > 0 ? 100 : -100;
            }

            if (labs(toneDCOffset) > 100)
            {
                toneDCOffset = toneDCOffset > 0 ? 100 : -100;
            }

            DWORD abssum = labs(toneAmplitude) + labs(toneDCOffset);
            
            if ( abssum > 100)
            {
                toneAmplitudeDouble = ((double)toneAmplitude) / abssum;
                toneDCOffsetDouble = ((double)toneDCOffset) / abssum;
            }
            else
            {
                toneAmplitudeDouble = ((double)toneAmplitude) / 100.0;
                toneDCOffsetDouble = ((double)toneDCOffset) / 100.0;
            }

            if (labs(toneInitialPhase) > 31416)
            {
                toneInitialPhase = toneInitialPhase > 0 ? 31416 : -31416;
            }

            toneInitialPhaseDouble = (double)toneInitialPhase / 10000;

            ntStatus = m_ToneGenerator.Init(toneFrequency, toneAmplitudeDouble, toneDCOffsetDouble, toneInitialPhaseDouble, m_pWfExt);
        if (!NT_SUCCESS(ntStatus))
        {
            return ntStatus;
        }
    }
    else if (!g_DoNotCreateDataFiles)
    {
        //
        // Create an output file for the render data.
        //
        DPF(D_TERSE, ("SaveData %p", &m_SaveData));
        ntStatus = m_SaveData.SetDataFormat(DataFormat_);
        if (NT_SUCCESS(ntStatus))
        {
            ntStatus = m_SaveData.Initialize(m_pMiniport->IsOffloadPin(Pin_));
        }
    
        if (!NT_SUCCESS(ntStatus))
        {
            return ntStatus;
        }
    }

    //
    // Register this stream.
    //
    ntStatus = m_pMiniport->StreamCreated(m_ulPin, this);
    if (NT_SUCCESS(ntStatus))
    {
        m_bUnregisterStream = TRUE;
    }

    return ntStatus;
} // Init

//=============================================================================
#pragma code_seg("PAGE")
STDMETHODIMP_(NTSTATUS)
CMiniportWaveRTStream::NonDelegatingQueryInterface
( 
    _In_ REFIID  Interface,
    _COM_Outptr_ PVOID * Object 
)
/*++

Routine Description:

  QueryInterface

Arguments:

  Interface - GUID

  Object - interface pointer to be returned

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();

    ASSERT(Object);

    if (IsEqualGUIDAligned(Interface, IID_IUnknown))
    {
        *Object = PVOID(PUNKNOWN(PMINIPORTWAVERTSTREAM(this)));
    }
    else if (IsEqualGUIDAligned(Interface, IID_IMiniportWaveRTStream))
    {
        *Object = PVOID(PMINIPORTWAVERTSTREAM(this));
    }
    else if (IsEqualGUIDAligned(Interface, IID_IMiniportWaveRTStreamNotification))
    {
        *Object = PVOID(PMINIPORTWAVERTSTREAMNOTIFICATION(this));
    }
    else if (IsEqualGUIDAligned(Interface, IID_IMiniportWaveRTInputStream) && (this->m_bCapture))
    {
        // This interface is supported only on capture streams
        *Object = PVOID(PMINIPORTWAVERTINPUTSTREAM(this));
    }
    else if (IsEqualGUIDAligned(Interface, IID_IMiniportWaveRTOutputStream) && (!this->m_bCapture)
        && (!this->m_pMiniport->IsOffloadPin(this->m_ulPin)))
    {
        // This interface is supported only on host render streams
        *Object = PVOID(PMINIPORTWAVERTOUTPUTSTREAM(this));
    }
    else if (IsEqualGUIDAligned(Interface, IID_IMiniportStreamAudioEngineNode))
    {
        *Object = (PVOID)(IMiniportStreamAudioEngineNode*)this;
    }
    else if (IsEqualGUIDAligned(Interface, IID_IMiniportStreamAudioEngineNode2))
    {
        *Object = (PVOID)(IMiniportStreamAudioEngineNode2*)this;
    }
    else if (IsEqualGUIDAligned(Interface, IID_IDrmAudioStream))
    {
        *Object = (PVOID)(IDrmAudioStream*)this;
    }
    else
    {
        *Object = NULL;
    }

    if (*Object)
    {
        PUNKNOWN(*Object)->AddRef();
        return STATUS_SUCCESS;
    }

    return STATUS_INVALID_PARAMETER;
} // NonDelegatingQueryInterface

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS CMiniportWaveRTStream::AllocateBufferWithNotification
(
    _In_    ULONG               NotificationCount_,
    _In_    ULONG               RequestedSize_,
    _Out_   PMDL                *AudioBufferMdl_,
    _Out_   ULONG               *ActualSize_,
    _Out_   ULONG               *OffsetFromFirstPage_,
    _Out_   MEMORY_CACHING_TYPE *CacheType_
)
{
    PAGED_CODE();

    ULONG ulBufferDurationMs = 0;

    if ( (0 == RequestedSize_) || (RequestedSize_ < m_pWfExt->Format.nBlockAlign) )
    { 
        return STATUS_UNSUCCESSFUL; 
    }
    
    if ((NotificationCount_ == 0) || (RequestedSize_ % NotificationCount_ != 0))
    {
        return STATUS_INVALID_PARAMETER;
    }

    RequestedSize_ -= RequestedSize_ % (m_pWfExt->Format.nBlockAlign);
    
    if (!m_bCapture && !g_DoNotCreateDataFiles)
    {
        NTSTATUS ntStatus;
        
        // Sysvad uses following buffer to hold data before writing to a file.
        // Allocating larger buffer will reduce File I/O operations.
        ntStatus = m_SaveData.SetMaxWriteSize(RequestedSize_ * 4);
        if (!NT_SUCCESS(ntStatus))
        {
            return ntStatus;
        }
    }

    PHYSICAL_ADDRESS highAddress;
    highAddress.HighPart = 0;
    highAddress.LowPart = MAXULONG;

    PMDL pBufferMdl = m_pPortStream->AllocatePagesForMdl (highAddress, RequestedSize_);

    if (NULL == pBufferMdl)
    {
        return STATUS_UNSUCCESSFUL;
    }

    // From MSDN: 
    // "Since the Windows audio stack does not support a mechanism to express memory access 
    //  alignment requirements for buffers, audio drivers must select a caching type for mapped
    //  memory buffers that does not impose platform-specific alignment requirements. In other 
    //  words, the caching type used by the audio driver for mapped memory buffers, must not make 
    //  assumptions about the memory alignment requirements for any specific platform.
    //
    //  This method maps the physical memory pages in the MDL into kernel-mode virtual memory. 
    //  Typically, the miniport driver calls this method if it requires software access to the 
    //  scatter-gather list for an audio buffer. In this case, the storage for the scatter-gather 
    //  list must have been allocated by the IPortWaveRTStream::AllocatePagesForMdl or 
    //  IPortWaveRTStream::AllocateContiguousPagesForMdl method. 
    //
    //  A WaveRT miniport driver should not require software access to the audio buffer itself."
    //   
    m_pDmaBuffer = (BYTE*)m_pPortStream->MapAllocatedPages(pBufferMdl, MmCached);
    m_ulNotificationsPerBuffer = NotificationCount_;
    m_ulDmaBufferSize = RequestedSize_;
    ulBufferDurationMs = (RequestedSize_ * 1000) / m_ulDmaMovementRate;
    m_ulNotificationIntervalMs = ulBufferDurationMs / NotificationCount_;

    *AudioBufferMdl_ = pBufferMdl;
    *ActualSize_ = RequestedSize_;
    *OffsetFromFirstPage_ = 0;
    *CacheType_ = MmCached;

    return STATUS_SUCCESS;
}

//=============================================================================
#pragma code_seg("PAGE")
VOID CMiniportWaveRTStream::FreeBufferWithNotification
(
    _In_        PMDL    Mdl_,
    _In_        ULONG   Size_
)
{
    UNREFERENCED_PARAMETER(Size_);

    PAGED_CODE();

    if (Mdl_ != NULL)
    {
        if (m_pDmaBuffer != NULL)
        {
            m_pPortStream->UnmapAllocatedPages(m_pDmaBuffer, Mdl_);
            m_pDmaBuffer = NULL;
        }
        
        m_pPortStream->FreePagesFromMdl(Mdl_);
    }
    
    m_ulDmaBufferSize = 0;
    m_ulNotificationsPerBuffer = 0;

    return;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS CMiniportWaveRTStream::RegisterNotificationEvent
(
    _In_ PKEVENT NotificationEvent_
)
{
    UNREFERENCED_PARAMETER(NotificationEvent_);

    PAGED_CODE();

    NotificationListEntry *nleNew = (NotificationListEntry*)ExAllocatePool2( 
        POOL_FLAG_NON_PAGED,
        sizeof(NotificationListEntry),
        MINWAVERTSTREAM_POOLTAG);
    if (NULL == nleNew)
    {
        return STATUS_INSUFFICIENT_RESOURCES;
    }

    nleNew->NotificationEvent = NotificationEvent_;

    // Fail if the notification event already exists in our list.
    if (!IsListEmpty(&m_NotificationList))
    {
        PLIST_ENTRY leCurrent = m_NotificationList.Flink;
        while (leCurrent != &m_NotificationList)
        {
            NotificationListEntry* nleCurrent = CONTAINING_RECORD( leCurrent, NotificationListEntry, ListEntry);
            if (nleCurrent->NotificationEvent == NotificationEvent_)
            {
                ExFreePoolWithTag( nleNew, MINWAVERTSTREAM_POOLTAG );
                return STATUS_UNSUCCESSFUL;
            }

            leCurrent = leCurrent->Flink;
        }
    }

    InsertTailList(&m_NotificationList, &(nleNew->ListEntry));
    
    return STATUS_SUCCESS;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS CMiniportWaveRTStream::UnregisterNotificationEvent
(
    _In_ PKEVENT NotificationEvent_
)
{
    UNREFERENCED_PARAMETER(NotificationEvent_);

    PAGED_CODE();

    if (!IsListEmpty(&m_NotificationList))
    {
        PLIST_ENTRY leCurrent = m_NotificationList.Flink;
        while (leCurrent != &m_NotificationList)
        {
            NotificationListEntry* nleCurrent = CONTAINING_RECORD( leCurrent, NotificationListEntry, ListEntry);
            if (nleCurrent->NotificationEvent == NotificationEvent_)
            {
                RemoveEntryList( leCurrent );
                ExFreePoolWithTag( nleCurrent, MINWAVERTSTREAM_POOLTAG );
                return STATUS_SUCCESS;
            }

            leCurrent = leCurrent->Flink;
        }
    }

    return STATUS_NOT_FOUND;
}


//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS CMiniportWaveRTStream::GetClockRegister
(
    _Out_ PKSRTAUDIO_HWREGISTER Register_
)
{
    UNREFERENCED_PARAMETER(Register_);

    PAGED_CODE();

    return STATUS_NOT_IMPLEMENTED;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS CMiniportWaveRTStream::GetPositionRegister
(
    _Out_ PKSRTAUDIO_HWREGISTER Register_
)
{
    UNREFERENCED_PARAMETER(Register_);

    PAGED_CODE();

    return STATUS_NOT_IMPLEMENTED;
}

//=============================================================================
#pragma code_seg("PAGE")
VOID CMiniportWaveRTStream::GetHWLatency
(
    _Out_ PKSRTAUDIO_HWLATENCY  Latency_
)
{
    PAGED_CODE();

    ASSERT(Latency_);

    Latency_->ChipsetDelay = 0;
    Latency_->CodecDelay = 0;
    Latency_->FifoSize = 0;
}

//=============================================================================
#pragma code_seg("PAGE")
VOID CMiniportWaveRTStream::FreeAudioBuffer
(
_In_opt_    PMDL        Mdl_,
_In_        ULONG       Size_
)
{
    UNREFERENCED_PARAMETER(Size_);

    PAGED_CODE();

    if (Mdl_ != NULL)
    {
        if (m_pDmaBuffer != NULL)
        {
            m_pPortStream->UnmapAllocatedPages(m_pDmaBuffer, Mdl_);
            m_pDmaBuffer = NULL;
        }

        m_pPortStream->FreePagesFromMdl(Mdl_);
    }

    m_ulDmaBufferSize = 0;
    m_ulNotificationsPerBuffer = 0;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS CMiniportWaveRTStream::AllocateAudioBuffer
(
_In_    ULONG                   RequestedSize_,
_Out_   PMDL                   *AudioBufferMdl_,
_Out_   ULONG                  *ActualSize_,
_Out_   ULONG                  *OffsetFromFirstPage_,
_Out_   MEMORY_CACHING_TYPE    *CacheType_
)
{
    PAGED_CODE();

    if ((0 == RequestedSize_) || (RequestedSize_ < m_pWfExt->Format.nBlockAlign))
    {
        return STATUS_UNSUCCESSFUL;
    }

    RequestedSize_ -= RequestedSize_ % (m_pWfExt->Format.nBlockAlign);

    PHYSICAL_ADDRESS highAddress;
    highAddress.HighPart = 0;
    highAddress.LowPart = MAXULONG;

    PMDL pBufferMdl = m_pPortStream->AllocatePagesForMdl(highAddress, RequestedSize_);

    if (NULL == pBufferMdl)
    {
        return STATUS_UNSUCCESSFUL;
    }

    // From MSDN: 
    // "Since the Windows audio stack does not support a mechanism to express memory access 
    //  alignment requirements for buffers, audio drivers must select a caching type for mapped
    //  memory buffers that does not impose platform-specific alignment requirements. In other 
    //  words, the caching type used by the audio driver for mapped memory buffers, must not make 
    //  assumptions about the memory alignment requirements for any specific platform.
    //
    //  This method maps the physical memory pages in the MDL into kernel-mode virtual memory. 
    //  Typically, the miniport driver calls this method if it requires software access to the 
    //  scatter-gather list for an audio buffer. In this case, the storage for the scatter-gather 
    //  list must have been allocated by the IPortWaveRTStream::AllocatePagesForMdl or 
    //  IPortWaveRTStream::AllocateContiguousPagesForMdl method. 
    //
    //  A WaveRT miniport driver should not require software access to the audio buffer itself."
    //   
    m_pDmaBuffer = (BYTE*)m_pPortStream->MapAllocatedPages(pBufferMdl, MmCached);

    m_ulDmaBufferSize = RequestedSize_;
    m_ulNotificationsPerBuffer = 0;

    *AudioBufferMdl_ = pBufferMdl;
    *ActualSize_ = RequestedSize_;
    *OffsetFromFirstPage_ = 0;
    *CacheType_ = MmCached;

    return STATUS_SUCCESS;
}

//=============================================================================
#pragma code_seg()
NTSTATUS CMiniportWaveRTStream::GetPosition
(
    _Out_   KSAUDIO_POSITION    *Position_
)
{
    NTSTATUS ntStatus;

#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
    if (m_SidebandStarted)
    {
        ntStatus = GetSidebandStreamNtStatus();
        IF_FAILED_JUMP(ntStatus, Done);
    }
#endif // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)

    // Return failure if this is the keyword detector pin
    if (m_pMiniport->IsKeywordDetectorPin(m_ulPin))
    {
        return STATUS_NOT_SUPPORTED;
    }

    KIRQL oldIrql;
    KeAcquireSpinLock(&m_PositionSpinLock, &oldIrql);

    if (m_KsState == KSSTATE_RUN)
    {
        //
        // Get the current time and update position.
        //
        LARGE_INTEGER ilQPC = KeQueryPerformanceCounter(NULL);
        UpdatePosition(ilQPC);
    }

    Position_->PlayOffset = m_ullPlayPosition;
    Position_->WriteOffset = m_ullWritePosition;

    KeReleaseSpinLock(&m_PositionSpinLock, oldIrql);

    ntStatus = STATUS_SUCCESS;
    
#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
Done:
#endif // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
    return ntStatus;
}

//=============================================================================
// CMiniportWaveRTStream::GetReadPacket
//
//  Returns information about the next packet for the OS to read.
//
// Return value
//
//  Returns STATUS_DEVICE_NOT_READY if no new packets are available.
//
// IRQL - PASSIVE_LEVEL
//
// Remarks
//  Although called at passive level, this routine is non-paged code because
//  it is called in the streaming path where page faults should be avoided.
//
// ISSUE-2014/10/4 Will this work correctly across pause/play?
#pragma code_seg()
_IRQL_requires_max_(PASSIVE_LEVEL)
NTSTATUS CMiniportWaveRTStream::GetReadPacket
(
    _Out_ ULONG     *PacketNumber,
    _Out_ DWORD     *Flags,
    _Out_ ULONG64   *PerformanceCounterValue,
    _Out_ BOOL      *MoreData
)
{
    NTSTATUS ntStatus;
    ULONG availablePacketNumber;
    ULONG droppedPackets;

    // The call must be from event driven mode
    if(m_ulNotificationsPerBuffer == 0)
    {
        return STATUS_NOT_SUPPORTED;
    }
    
    *Flags = 0;

    if (m_KsState < KSSTATE_PAUSE)
    {
        return STATUS_INVALID_DEVICE_STATE;
    }

    // If this is the keyword detector pin, then stream from the keyword FIFO
    if (m_pMiniport->IsKeywordDetectorPin(m_ulPin))
    {
        // FUTURE-2014/11/18 Drive this with packet counter
        ntStatus = m_pMiniport->m_KeywordDetector.GetReadPacket(m_ulNotificationsPerBuffer, m_ulDmaBufferSize, m_pDmaBuffer, PacketNumber, PerformanceCounterValue, MoreData);
        if (NT_SUCCESS(ntStatus))
        {
            m_ulLastOsReadPacket = *PacketNumber;
        }
        return ntStatus;
    }

    KIRQL oldIrql;
    KeAcquireSpinLock(&m_PositionSpinLock, &oldIrql);

    LONGLONG packetCounter = m_llPacketCounter;
    ULONGLONG ullLinearPosition = m_ullLinearPosition;
    ULONGLONG hnsElapsedTimeCarryForward = m_hnsElapsedTimeCarryForward;
    ULONGLONG ullDmaTimeStamp = m_ullDmaTimeStamp;

    KeReleaseSpinLock(&m_PositionSpinLock, oldIrql);

    // The 0-based number of the last completed packet
    // FUTURE-2014/10/27 Update to allow different numbers of packets per WaveRT buffer
    availablePacketNumber = LODWORD(packetCounter - 1);  // Note this might be ULONG_MAX if called during the first packet

    // If no new packets are available...
    if (availablePacketNumber == m_ulLastOsReadPacket)
    {
        return STATUS_DEVICE_NOT_READY;
    }

    // If more than one packet has transferred since the last packet read by
    // the OS, then those were dropped. That is, a glitch occurred.
    droppedPackets = availablePacketNumber - m_ulLastOsReadPacket - 1;
    if (droppedPackets > 0)
    {
        // Trace a glitch
    }

    // Return next packet number to be read
    *PacketNumber = availablePacketNumber;

    // Compute and return timestamp corresponding to the end of the available packet. In a real hardware
    // driver, the timestamp would be computed in a driver and hardware specific manner. In this sample
    // driver, it is extrapolated from the sample driver's internal simulated position correlation
    // [m_ullLinearPosition @ m_ullDmaTimeStamp] and the sample's internal 64-bit packet counter, subtracting
    // 1 from the packet counter to compute the time at the start of that last completed packet.
    ULONGLONG linearPositionOfAvailablePacket = packetCounter * (m_ulDmaBufferSize / m_ulNotificationsPerBuffer);
    // Need to divide by (1000 * 10000 because m_ulDmaMovementRate is average bytes per sec
    ULONGLONG carryForwardBytes = (hnsElapsedTimeCarryForward * m_ulDmaMovementRate) / 10000000;
    ULONGLONG deltaLinearPosition = ullLinearPosition + carryForwardBytes - linearPositionOfAvailablePacket;
    ULONGLONG deltaTimeInHns = deltaLinearPosition * 10000000 / m_ulDmaMovementRate;
    ULONGLONG timeOfAvailablePacketInHns = ullDmaTimeStamp - deltaTimeInHns;
    ULONGLONG timeOfAvailablePacketInQpc = timeOfAvailablePacketInHns * m_ullPerformanceCounterFrequency.QuadPart / 10000000;

    *PerformanceCounterValue = timeOfAvailablePacketInQpc;

    // No flags are defined yet
    *Flags = 0;

    // This sample does not internally buffer data so there is never more data
    // than revealed by the results from this routine.
    *MoreData = FALSE;

    // Update the last packet read by the OS
    m_ulLastOsReadPacket = availablePacketNumber;

    return STATUS_SUCCESS;
}

#pragma code_seg()
_IRQL_requires_max_(PASSIVE_LEVEL)
NTSTATUS CMiniportWaveRTStream::SetWritePacket
(
    _In_ ULONG      PacketNumber,
    _In_ DWORD      Flags,
    _In_ ULONG      EosPacketLength
)
{
    NTSTATUS ntStatus;

    // The call must be from event driven mode
    if (m_ulNotificationsPerBuffer == 0)
    {
        return STATUS_NOT_SUPPORTED;
    }

    ULONG oldLastOsWritePacket = m_ulLastOsWritePacket;

    // This function should not be called once EoS has been set.
    if (m_bEoSReceived)
    {
        return STATUS_INVALID_DEVICE_STATE;
    }

    KIRQL oldIrql;
    KeAcquireSpinLock(&m_PositionSpinLock, &oldIrql);
    // 1-based count of completed packets, 0-based packet number of current packet
    LONGLONG currentPacket = m_llPacketCounter;
    KeReleaseSpinLock(&m_PositionSpinLock, oldIrql);

    // If not running, the current packet hasn't actually started transfering so OS should be writing
    // to the current packet. If running, then the current packing is already transfering to hardware
    // so the OS should write the packet after the current packet.
    ULONG expectedPacket = LODWORD(currentPacket);
    if (m_KsState == KSSTATE_RUN)
    {
        expectedPacket++;
    }

    // Check if OS PacketNumber is behind or too far ahead of current packet
    LONG deltaFromExpectedPacket = PacketNumber - expectedPacket;   // Modulo arithemetic
    if (deltaFromExpectedPacket < 0)
    {
        return STATUS_DATA_LATE_ERROR;
    }
    else if (deltaFromExpectedPacket > 0)
    {
        return STATUS_DATA_OVERRUN;
    }

    ULONG packetSize = (m_ulDmaBufferSize / m_ulNotificationsPerBuffer);
    ULONG packetIndex = PacketNumber % m_ulNotificationsPerBuffer;
    ULONG ulCurrentWritePosition = packetIndex * packetSize;

    // Check if EOS flag was passed
    if (Flags & KSSTREAM_HEADER_OPTIONSF_ENDOFSTREAM)
    {
        if (EosPacketLength > packetSize)
        {
            return STATUS_INVALID_PARAMETER;
        }
        else {
            // EOS position will be after the total completed packets, plus the packet in progress,
            // plus this EOS packet length
            m_ulLastOsWritePacket = PacketNumber;
            ulCurrentWritePosition += EosPacketLength;
            ntStatus = SetStreamCurrentWritePositionForLastBuffer(ulCurrentWritePosition);
        }
    }
    else
    {
        m_ulLastOsWritePacket = PacketNumber;

        // This function sets the current write position to the specified byte in the DMA buffer.
        // Will check if the write position is smaller than the DMA buffer size.
        // Will not return an error when the passed in parameter is 0.
        // Will also check if this function was called with the same write position(in event mode only)
        // Underruning will also be checked via timer mechanism
        KeAcquireSpinLock(&m_PositionSpinLock, &oldIrql);
        ntStatus = SetCurrentWritePositionInternal(ulCurrentWritePosition);
        KeReleaseSpinLock(&m_PositionSpinLock, oldIrql);
    }

    if (!NT_SUCCESS(ntStatus))
    {
        m_ulLastOsWritePacket = oldLastOsWritePacket;
    }

    return ntStatus;
}

//=============================================================================
#pragma code_seg()
_IRQL_requires_max_(PASSIVE_LEVEL)
NTSTATUS CMiniportWaveRTStream::GetOutputStreamPresentationPosition
(
    _Out_ KSAUDIO_PRESENTATION_POSITION *pPresentationPosition
)
{
    ASSERT (pPresentationPosition);
    
    // The call must be from event driven mode
    if(m_ulNotificationsPerBuffer == 0)
    {
        return STATUS_NOT_SUPPORTED;
    }
    
    return GetPresentationPosition(pPresentationPosition);
}

//=============================================================================
#pragma code_seg()
_IRQL_requires_max_(PASSIVE_LEVEL)
NTSTATUS CMiniportWaveRTStream::GetPacketCount
(
    _Out_ ULONG *pPacketCount
)
{
    ASSERT(pPacketCount);

    // The call must be from event driven mode
    if(m_ulNotificationsPerBuffer == 0)
    {
        return STATUS_NOT_SUPPORTED;
    }
    
    KIRQL oldIrql;
    KeAcquireSpinLock(&m_PositionSpinLock, &oldIrql);

    if (m_KsState == KSSTATE_RUN)
    {
        // Get the current time and update simulated position.
        LARGE_INTEGER ilQPC = KeQueryPerformanceCounter(NULL);
        UpdatePosition(ilQPC);
    }

    *pPacketCount = LODWORD(m_llPacketCounter);
    KeReleaseSpinLock(&m_PositionSpinLock, oldIrql);

    return STATUS_SUCCESS;
}

//=============================================================================
#pragma code_seg()
NTSTATUS CMiniportWaveRTStream::SetState
(
    _In_    KSSTATE State_
)
{
    NTSTATUS        ntStatus        = STATUS_SUCCESS;
    PADAPTERCOMMON  pAdapterComm    = m_pMiniport->GetAdapterCommObj();
    KIRQL oldIrql;

    // Spew an event for a pin state change request from portcls
    //Event type: eMINIPORT_PIN_STATE
    //Parameter 1: Current linear buffer position
    //Parameter 2: Current WaveRtBufferWritePosition
    //Parameter 3: Pin State 0->KS_STOP, 1->KS_ACQUIRE, 2->KS_PAUSE, 3->KS_RUN 
    //Parameter 4: 0
    pAdapterComm->WriteEtwEvent(eMINIPORT_PIN_STATE,
                                m_ullLinearPosition, // replace with the correct "Current linear buffer position"
                                m_ulCurrentWritePosition, // replace with the previous WaveRtBufferWritePosition that the driver received
                                State_, // replace with the correct "Data length completed"
                                0); // always zero
    switch (State_)
    {
        case KSSTATE_STOP:
            if (m_KsState == KSSTATE_ACQUIRE)
            {
                // Acquire stream resources
#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
                if (m_SidebandOpen)
                {
                    PSIDEBANDDEVICECOMMON sidebandDevice;

                    ASSERT(m_pMiniport->IsSidebandDevice());
                    sidebandDevice = m_pMiniport->GetSidebandDevice(); // weak ref.
                    ASSERT(sidebandDevice != NULL);

                    //
                    // Close the Sideband connection.
                    //
                    ntStatus = sidebandDevice->StreamClose(m_pMiniport->m_DeviceType);
                    if (!NT_SUCCESS(ntStatus))
                    {
                        DPF(D_ERROR, ("SetState: KSSTATE_PAUSE, StreamClose failed, 0x%x", ntStatus));
                    }

                    m_SidebandOpen = FALSE;
                }
#endif // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
            }
            KeAcquireSpinLock(&m_PositionSpinLock, &oldIrql);
            // Reset DMA
            m_llPacketCounter = 0;
            m_ullPlayPosition = 0;
            m_ullWritePosition = 0;
            m_ullLinearPosition = 0;
            m_ullPresentationPosition = 0;
            
            // Reset OS read/write positions
            m_ulLastOsReadPacket = ULONG_MAX;
            m_ulCurrentWritePosition = 0;
            m_ulLastOsWritePacket = ULONG_MAX;
            m_bEoSReceived = FALSE;
            m_bLastBufferRendered = FALSE;

            KeReleaseSpinLock(&m_PositionSpinLock, oldIrql);

            // Wait until all work items are completed.
            if (!m_bCapture && !g_DoNotCreateDataFiles)
            {
                m_SaveData.WaitAllWorkItems();
            }
            break;

        case KSSTATE_ACQUIRE:
            if (m_KsState == KSSTATE_STOP)
            {
                // Acquire stream resources
#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
                if (m_pMiniport->IsSidebandDevice())
                {
                    if (m_SidebandOpen == FALSE)
                    {
                        PSIDEBANDDEVICECOMMON sidebandDevice;

                        sidebandDevice = m_pMiniport->GetSidebandDevice(); // weak ref.
                        ASSERT(sidebandDevice != NULL);

                        //
                        // Open the Sideband connection.
                        //
                        ntStatus = sidebandDevice->StreamOpen(m_pMiniport->m_DeviceType);
                        IF_FAILED_ACTION_JUMP(
                            ntStatus,
                            DPF(D_ERROR, ("SetState: KSSTATE_ACQUIRE, StreamOpen failed, 0x%x", ntStatus)),
                            Done);

                        m_SidebandOpen = TRUE;
                    }
                }
#endif // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
            }
            break;
            
        case KSSTATE_PAUSE:

            if (m_KsState > KSSTATE_PAUSE)
            {
                //
                // Run -> Pause
                //
                if (m_pMiniport->IsKeywordDetectorPin(m_ulPin))
                {
                    m_pMiniport->m_KeywordDetector.Stop();
                }

                // Pause DMA
                if (m_ulNotificationIntervalMs > 0)
                {
                    ExCancelTimer(m_pNotificationTimer, NULL);
                    KeFlushQueuedDpcs(); 

                    // If pin is transitioning from RUN, save the time since last buffer completion event was sent 
                    // so if the pin goes to RUN state again we can send the buffer completion event at correct time.
                    if (m_ullLastDPCTimeStamp > 0)
                    {
                        LARGE_INTEGER qpc;
                        LARGE_INTEGER qpcFrequency;
                        LONGLONG  hnsCurrentTime;

                        qpc = KeQueryPerformanceCounter(&qpcFrequency);

                        // Convert ticks to 100ns units.
                        hnsCurrentTime = KSCONVERT_PERFORMANCE_TIME(m_ullPerformanceCounterFrequency.QuadPart, qpc);
                        m_hnsDPCTimeCarryForward = hnsCurrentTime - m_ullLastDPCTimeStamp + m_hnsDPCTimeCarryForward;
                    }
                }

#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
                if (m_SidebandStarted)
                {
                    PSIDEBANDDEVICECOMMON sidebandDevice;

                    ASSERT(m_pMiniport->IsSidebandDevice());
                    sidebandDevice = m_pMiniport->GetSidebandDevice(); // weak ref.
                    ASSERT(sidebandDevice != NULL);

                    //
                    // Close the Sideband connection.
                    //
                    ntStatus = sidebandDevice->StreamSuspend(m_pMiniport->m_DeviceType);
                    if (!NT_SUCCESS(ntStatus))
                    {
                        DPF(D_ERROR, ("SetState: KSSTATE_PAUSE, StreamClose failed, 0x%x", ntStatus));
                    }

                    m_SidebandStarted = FALSE;
                }
#endif // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)

            }
            // This call updates the linear buffer and presentation positions.
            GetPositions(NULL, NULL, NULL);
            break;

        case KSSTATE_RUN:

#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
            if (m_pMiniport->IsSidebandDevice())
            {
                if (m_SidebandStarted == FALSE)
                {
                    PSIDEBANDDEVICECOMMON sidebandDevice;

                    sidebandDevice = m_pMiniport->GetSidebandDevice(); // weak ref.
                    ASSERT(sidebandDevice != NULL);

                    //
                    // Start the Sideband connection.
                    //
                    ntStatus = sidebandDevice->StreamStart(m_pMiniport->m_DeviceType);
                    IF_FAILED_ACTION_JUMP(
                        ntStatus,
                        DPF(D_ERROR, ("SetState: KSSTATE_RUN, StreamStart failed, 0x%x", ntStatus)),
                        Done);

                    m_SidebandStarted = TRUE;
                }
            }
#endif // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)

            // Start DMA
            LARGE_INTEGER ullPerfCounterTemp;
            if (m_pMiniport->IsKeywordDetectorPin(m_ulPin))
            {
                m_pMiniport->m_KeywordDetector.Run();
            }
            ullPerfCounterTemp = KeQueryPerformanceCounter(&m_ullPerformanceCounterFrequency);
            m_ullLastDPCTimeStamp = m_ullDmaTimeStamp = KSCONVERT_PERFORMANCE_TIME(m_ullPerformanceCounterFrequency.QuadPart, ullPerfCounterTemp);

            if (m_ulNotificationIntervalMs > 0)
            {
                // Set timer for 1 ms. This will cause DPC to run every 1 ms but driver will send out 
                // notification events only after notification interval. This timer is used by Sysvad to 
                // emulate hardware and send out notification event. Real hardware should not use this
                // timer to fire notification event as it will drain power if the timer is running at 1 msec.
                ExSetTimer
                (
                    m_pNotificationTimer,
                    (-1) * HNSTIME_PER_MILLISECOND,
                    HNSTIME_PER_MILLISECOND, // 1 ms 
                    NULL
                 );

            }

            break;
    }

    m_KsState = State_;

#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
Done:
#endif  // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
    return ntStatus;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS CMiniportWaveRTStream::SetFormat
(
    _In_    KSDATAFORMAT    *DataFormat_
)
{
    UNREFERENCED_PARAMETER(DataFormat_);

    PAGED_CODE();

    //if (!m_fCapture && !g_DoNotCreateDataFiles)
    //{
    //    ntStatus = m_SaveData.SetDataFormat(Format);
    //}

    return STATUS_NOT_SUPPORTED;
}

#pragma code_seg()

//=============================================================================
#pragma code_seg()
VOID CMiniportWaveRTStream::UpdatePosition
(
    _In_ LARGE_INTEGER ilQPC
)
{
    // Convert ticks to 100ns units.
    LONGLONG  hnsCurrentTime = KSCONVERT_PERFORMANCE_TIME(m_ullPerformanceCounterFrequency.QuadPart, ilQPC);
    
    // Calculate the time elapsed since the last call to GetPosition() or since the
    // DMA engine started.  Note that the division by 10000 to convert to milliseconds
    // may cause us to lose some of the time, so we will carry the remainder forward 
    // to the next GetPosition() call.
    //
    ULONG TimeElapsedInMS = (ULONG)(hnsCurrentTime - m_ullDmaTimeStamp + m_hnsElapsedTimeCarryForward)/10000;
    
    // Carry forward the remainder of this division so we don't fall behind with our position too much.
    //
    m_hnsElapsedTimeCarryForward = (hnsCurrentTime - m_ullDmaTimeStamp + m_hnsElapsedTimeCarryForward) % 10000;
    
    // Calculate how many bytes in the DMA buffer would have been processed in the elapsed
    // time.  Note that the division by 1000 to convert to milliseconds may cause us to 
    // lose some bytes, so we will carry the remainder forward to the next GetPosition() call.
    //
    // need to divide by 1000 because m_ulDmaMovementRate is average bytes per sec.

    ULONG ByteDisplacement = ((m_ulDmaMovementRate * TimeElapsedInMS) + m_byteDisplacementCarryForward) / 1000 ;
    m_byteDisplacementCarryForward = ((m_ulDmaMovementRate * TimeElapsedInMS) + m_byteDisplacementCarryForward) % 1000;

    // Increment presentation position even after last buffer is rendered.
    m_ullPresentationPosition += ByteDisplacement;

    if (m_bCapture)
    {
        // Write sine wave to buffer.
        WriteBytes(ByteDisplacement);
    }
    else
    {
        if (m_bEoSReceived)
        {
            // since EoS flag is set, we'll need to make sure not to read data beyond EOS position.
            // If driver's current position is less than EoS position, then make sure not to read data beyond EoS.
            if (m_ullWritePosition <= m_ulCurrentWritePosition)
            {
                ByteDisplacement = min(ByteDisplacement, m_ulCurrentWritePosition - (ULONG)m_ullWritePosition);
            }
            // If our current position is ahead of EoS position and we'll wrap around after new position then adjust
            // new position if it crosses EoS.
            else if ((m_ullWritePosition + ByteDisplacement) % m_ulDmaBufferSize < m_ullWritePosition)
            {
                if ((m_ullWritePosition + ByteDisplacement) % m_ulDmaBufferSize > m_ulCurrentWritePosition)
                {
                    ByteDisplacement = ByteDisplacement - (((ULONG)m_ullWritePosition + ByteDisplacement) % m_ulDmaBufferSize - m_ulCurrentWritePosition);
                }
            }
        }

        // If the last packet was rendered(read in the sample driver's case), send out an etw event.
        if ( m_bEoSReceived && !m_bLastBufferRendered
            && (m_ullWritePosition + ByteDisplacement) % m_ulDmaBufferSize == m_ulCurrentWritePosition)
        {
            m_bLastBufferRendered = TRUE;
            PADAPTERCOMMON pAdapterComm = m_pMiniport->GetAdapterCommObj();
            //Event type : eMINIPORT_LAST_BUFFER_RENDERED
            //Parameter 1 : Current linear buffer position
            //Parameter 2 : the very last WaveRtBufferWritePosition that the driver received
            //Parameter 3 : 0
            //Parameter 4 : 0
            pAdapterComm->WriteEtwEvent(eMINIPORT_LAST_BUFFER_RENDERED,
                                        m_ullLinearPosition + ByteDisplacement, // Current linear buffer position  
                                        m_ulCurrentWritePosition, // The very last WaveRtBufferWritePosition that the driver received
                                        0,
                                        0);
        }

        if (!g_DoNotCreateDataFiles)
        {
            // Read from buffer and write to a file.
            ReadBytes(ByteDisplacement);
        }
    }
    
    // Increment the DMA position by the number of bytes displaced since the last
    // call to UpdatePosition() and ensure we properly wrap at buffer length.
    //
    m_ullPlayPosition = m_ullWritePosition =
        (m_ullWritePosition + ByteDisplacement) % m_ulDmaBufferSize;
    
    // m_ullDmaTimeStamp is updated in both GetPostion and GetLinearPosition calls
    // so m_ullLinearPosition needs to be updated accordingly here
    //
    m_ullLinearPosition += ByteDisplacement;
    
    // Update the DMA time stamp for the next call to GetPosition()
    //
    m_ullDmaTimeStamp = hnsCurrentTime;
}

//=============================================================================
#pragma code_seg()
VOID CMiniportWaveRTStream::WriteBytes
(
    _In_ ULONG ByteDisplacement
)
/*++

Routine Description:

This function writes the audio buffer using a sine wave generator
Arguments:

ByteDisplacement - # of bytes to process.

--*/
{
    ULONG bufferOffset = m_ullLinearPosition % m_ulDmaBufferSize;

    // Normally this will loop no more than once for a single wrap, but if
    // many bytes have been displaced then this may loops many times.
    while (ByteDisplacement > 0)
    {
        ULONG runWrite = min(ByteDisplacement, m_ulDmaBufferSize - bufferOffset);
            m_ToneGenerator.GenerateSine(m_pDmaBuffer + bufferOffset, runWrite);
        bufferOffset = (bufferOffset + runWrite) % m_ulDmaBufferSize;
        ByteDisplacement -= runWrite;
    }
}

//=============================================================================
#pragma code_seg()
VOID CMiniportWaveRTStream::ReadBytes
(
    _In_ ULONG ByteDisplacement
)
/*++

Routine Description:

This function reads the audio buffer and saves the data in a file.

Arguments:

ByteDisplacement - # of bytes to process.

--*/
{
    ULONG bufferOffset = m_ullLinearPosition % m_ulDmaBufferSize;

    // Normally this will loop no more than once for a single wrap, but if
    // many bytes have been displaced then this may loops many times.
    while (ByteDisplacement > 0)
    {
        ULONG runWrite = min(ByteDisplacement, m_ulDmaBufferSize - bufferOffset);
        m_SaveData.WriteData(m_pDmaBuffer + bufferOffset, runWrite);
        bufferOffset = (bufferOffset + runWrite) % m_ulDmaBufferSize;
        ByteDisplacement -= runWrite;
    }
}

//=============================================================================
#pragma code_seg("PAGE")
STDMETHODIMP_(NTSTATUS) 
CMiniportWaveRTStream::SetContentId
(
    _In_  ULONG                   contentId,
    _In_  PCDRMRIGHTS             drmRights
)
/*++

Routine Description:

  Sets DRM content Id for this stream. Also updates the Mixed content Id.

Arguments:

  contentId - new content id

  drmRights - rights for this stream.

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();

    DPF_ENTER(("[CMiniportWaveRT::SetContentId]"));

    NTSTATUS    ntStatus;
    ULONG       ulOldContentId = contentId;

    m_ulContentId = contentId;

    //
    // Miniport should create a mixed DrmRights.
    //
    ntStatus = m_pMiniport->UpdateDrmRights();

    //
    // Restore the passed-in content Id.
    //
    if (!NT_SUCCESS(ntStatus))
    {
        m_ulContentId = ulOldContentId;
    }

    //
    // SYSVAD writes each stream seperately to disk. If the rights for this
    // stream indicates that the stream is CopyProtected, stop writing to disk.
    //
    m_SaveData.Disable(drmRights->CopyProtect);

    //
    // From MSDN:
    //
    // This sample doesn't forward protected content, but if your driver uses 
    // lower layer drivers or a different stack to properly work, please see the 
    // following info from MSDN:
    //
    // "Before allowing protected content to flow through a data path, the system
    // verifies that the data path is secure. To do so, the system authenticates
    // each module in the data path beginning at the upstream end of the data path
    // and moving downstream. As each module is authenticated, that module gives
    // the system information about the next module in the data path so that it
    // can also be authenticated. To be successfully authenticated, a module's 
    // binary file must be signed as DRM-compliant.
    //
    // Two adjacent modules in the data path can communicate with each other in 
    // one of several ways. If the upstream module calls the downstream module 
    // through IoCallDriver, the downstream module is part of a WDM driver. In 
    // this case, the upstream module calls the DrmForwardContentToDeviceObject
    // function to provide the system with the device object representing the 
    // downstream module. (If the two modules communicate through the downstream
    // module's COM interface or content handlers, the upstream module calls 
    // DrmForwardContentToInterface or DrmAddContentHandlers instead.)
    //
    // DrmForwardContentToDeviceObject performs the same function as 
    // PcForwardContentToDeviceObject and IDrmPort2::ForwardContentToDeviceObject." 
    //
    // Other supported DRM DDIs for down-level module validation are: 
    // DrmForwardContentToInterfaces and DrmAddContentHandlers.
    //
    // For more information, see MSDN's DRM Functions and Interfaces.
    //

    return ntStatus;
} // SetContentId

#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)

//=============================================================================
#pragma code_seg()
NTSTATUS 
CMiniportWaveRTStream::GetSidebandStreamNtStatus()
/*++

Routine Description:

  Checks if the Sideband stream connection is up, if not, an error is returned.

Return Value:

  NT status code.

--*/
{
    DPF_ENTER(("[CMiniportWaveRTStream::GetSidebandStreamNtStatus]"));

    NTSTATUS  ntStatus  = STATUS_INVALID_DEVICE_STATE;
        
    if (m_SidebandStarted)
    {
        PSIDEBANDDEVICECOMMON sidebandDevice;
        
        ASSERT(m_pMiniport->IsSidebandDevice());
        sidebandDevice = m_pMiniport->GetSidebandDevice(); // weak ref.
        ASSERT(sidebandDevice != NULL);

        if (sidebandDevice->GetStreamStatus(m_pMiniport->m_DeviceType))
        {
            ntStatus = STATUS_SUCCESS;
        }
    }

    return ntStatus;        
}
#endif // defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS
CMiniportWaveRTStream::PropertyHandlerModulesListRequest
(
    _In_ PPCPROPERTY_REQUEST      PropertyRequest
)
{
    // This specific APO->driver communication example is mainly added to show 
    // how this communication is done. The instance module list lives on the 
    // stream object and it can only have modules associated with the underline
    // stream's pin.

    PAGED_CODE();

    DPF_ENTER(("[CMiniportWaveRTStream::PropertyHandlerModulesListRequest]"));

    return AudioModule_GenericHandler_ModulesListRequest(
                PropertyRequest,
                GetAudioModuleList(),
                GetAudioModuleListCount());
} // PropertyHandlerModulesListRequest

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS
CMiniportWaveRTStream::PropertyHandlerModuleCommand
(
    _In_ PPCPROPERTY_REQUEST      PropertyRequest
)
{
    PAGED_CODE();

    DPF_ENTER(("[CMiniportWaveRTStream::PropertyHandlerModuleCommand]"));

    return AudioModule_GenericHandler_ModuleCommand(
                PropertyRequest,
                GetAudioModuleList(),
                GetAudioModuleListCount());
} // PropertyHandlerModuleCommand

//=============================================================================
#pragma code_seg()
void
TimerNotifyRT
(
    _In_      PEX_TIMER    Timer,
    _In_opt_  PVOID        DeferredContext
)
{
    LARGE_INTEGER qpc;
    LARGE_INTEGER qpcFrequency;
    BOOL bufferCompleted = FALSE;

    UNREFERENCED_PARAMETER(Timer);

    _IRQL_limited_to_(DISPATCH_LEVEL);

    CMiniportWaveRTStream* _this = (CMiniportWaveRTStream*)DeferredContext;
    
    if (NULL == _this)
    {
        return;
    }

    KIRQL oldIrql;
    KeAcquireSpinLock(&_this->m_PositionSpinLock, &oldIrql);

    qpc = KeQueryPerformanceCounter(&qpcFrequency);

    // Convert ticks to 100ns units.
    LONGLONG  hnsCurrentTime = KSCONVERT_PERFORMANCE_TIME(_this->m_ullPerformanceCounterFrequency.QuadPart, qpc);

    // Calculate the time elapsed since the last we ran DPC that matched Notification interval. Note that the division by 10000 
    // to convert to milliseconds may cause us to lose some of the time, so we will carry the remainder forward.

    ULONG TimeElapsedInMS = (ULONG)(hnsCurrentTime - _this->m_ullLastDPCTimeStamp + _this->m_hnsDPCTimeCarryForward)/10000;

    if (TimeElapsedInMS >= _this->m_ulNotificationIntervalMs)
    {
        // Carry forward the time greater than notification interval to adjust time to signal next buffer completion event accordingly.
        _this->m_hnsDPCTimeCarryForward = hnsCurrentTime - _this->m_ullLastDPCTimeStamp + _this->m_hnsDPCTimeCarryForward - (_this->m_ulNotificationIntervalMs * 10000);
        // Save the last time DPC ran at notification interval
        _this->m_ullLastDPCTimeStamp = hnsCurrentTime;
        bufferCompleted = TRUE;
    }

    if (!bufferCompleted && !_this->m_bEoSReceived)
    {
        goto End;
    }

    _this->UpdatePosition(qpc);

    if (!_this->m_bEoSReceived)
    {
        _this->m_llPacketCounter++;
    }

#if defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)
    if (_this->m_SidebandStarted)
    {
        if (!NT_SUCCESS(_this->GetSidebandStreamNtStatus()))
        {
            goto End;
        }
    }
#endif  //defined(SYSVAD_BTH_BYPASS) || defined(SYSVAD_USB_SIDEBAND)

    _this->m_pMiniport->DpcRoutine(qpc.QuadPart, qpcFrequency.QuadPart);

    if (_this->m_KsState != KSSTATE_RUN)
    {
        goto End;
    }
    
    PADAPTERCOMMON  pAdapterComm = _this->m_pMiniport->GetAdapterCommObj();

    // Simple buffer underrun detection.
    if (!_this->IsCurrentWaveRTWritePositionUpdated() && !_this->m_bEoSReceived)
    {
        //Event type: eMINIPORT_GLITCH_REPORT
        //Parameter 1: Current linear buffer position 
        //Parameter 2: Previous WaveRtBufferWritePosition that the driver received 
        //Parameter 3: Major glitch code: 1:WaveRT buffer is underrun
        //Parameter 4: Minor code for the glitch cause
        pAdapterComm->WriteEtwEvent(eMINIPORT_GLITCH_REPORT, 
                                    _this->m_ullLinearPosition,
                                    _this->GetCurrentWaveRTWritePosition(),
                                    1,      // WaveRT buffer is underrun
                                    0); 
    }

    // Send buffer completion event if either of the following is true
    // 1. Driver consumed a complete buffer for this stream
    // 2. Driver consumed a partial buffer containing EoS for this stream

    if (!IsListEmpty(&_this->m_NotificationList) && 
        (bufferCompleted || _this->m_bLastBufferRendered))
    {
        PLIST_ENTRY leCurrent = _this->m_NotificationList.Flink;
        while (leCurrent != &_this->m_NotificationList)
        {
            NotificationListEntry* nleCurrent = CONTAINING_RECORD( leCurrent, NotificationListEntry, ListEntry);
            //Event type: eMINIPORT_BUFFER_COMPLETE
            //Parameter 1: Current linear buffer position
            //Parameter 2: Previous WaveRtBufferWritePosition that the driver received
            //Parameter 3: Data length completed
            //Parameter 4: 0
            pAdapterComm->WriteEtwEvent(eMINIPORT_BUFFER_COMPLETE,
                                        _this->m_ullLinearPosition,
                                        _this->GetCurrentWaveRTWritePosition(),
                                        _this->m_ulDmaBufferSize/_this->m_ulNotificationsPerBuffer, // replace with the correct "Data length completed"
                                        0); // always zero
            KeSetEvent(nleCurrent->NotificationEvent, 0, 0);

            leCurrent = leCurrent->Flink;
        }
    }

    if (_this->m_bLastBufferRendered)
    {
        ExCancelTimer(_this->m_pNotificationTimer, NULL);
    }

End:
    KeReleaseSpinLock(&_this->m_PositionSpinLock, oldIrql);
    return;
}
//=============================================================================


