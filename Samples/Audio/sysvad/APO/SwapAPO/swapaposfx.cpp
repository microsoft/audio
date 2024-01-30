//
// SwapAPOSFX.cpp -- Copyright (c) Microsoft Corporation. All rights reserved.
//
// Description:
//
//  Implementation of CSwapAPOSFX
//

#include <atlbase.h>
#include <atlcom.h>
#include <atlcoll.h>
#include <atlsync.h>
#include <mmreg.h>

#include <audioenginebaseapo.h>
#include <baseaudioprocessingobject.h>
#include <resource.h>

#include <float.h>

#include "SwapAPO.h"
#include <devicetopology.h>
#include <CustomPropKeys.h>
#include <propvarutil.h>


// Static declaration of the APO_REG_PROPERTIES structure
// associated with this APO.  The number in <> brackets is the
// number of IIDs supported by this APO.  If more than one, then additional
// IIDs are added at the end
#pragma warning (disable : 4815)
const AVRT_DATA CRegAPOProperties<1> CSwapAPOSFX::sm_RegProperties(
    __uuidof(SwapAPOSFX),                           // clsid of this APO
    L"CSwapAPOSFX",                                 // friendly name of this APO
    L"Copyright (c) Microsoft Corporation",         // copyright info
    1,                                              // major version #
    0,                                              // minor version #
    __uuidof(ISwapAPOSFX)                           // iid of primary interface

//
// If you need to change any of these attributes, uncomment everything up to
// the point that you need to change something.  If you need to add IIDs, uncomment
// everything and add additional IIDs at the end.
//
//  , DEFAULT_APOREG_FLAGS
//  , DEFAULT_APOREG_MININPUTCONNECTIONS
//  , DEFAULT_APOREG_MAXINPUTCONNECTIONS
//  , DEFAULT_APOREG_MINOUTPUTCONNECTIONS
//  , DEFAULT_APOREG_MAXOUTPUTCONNECTIONS
//  , DEFAULT_APOREG_MAXINSTANCES
//
    );

#pragma AVRT_CODE_BEGIN
//-------------------------------------------------------------------------
// Description:
//
//  Do the actual processing of data.
//
// Parameters:
//
//      u32NumInputConnections      - [in] number of input connections
//      ppInputConnections          - [in] pointer to list of input APO_CONNECTION_PROPERTY pointers
//      u32NumOutputConnections      - [in] number of output connections
//      ppOutputConnections         - [in] pointer to list of output APO_CONNECTION_PROPERTY pointers
//
// Return values:
//
//      void
//
// Remarks:
//
//  This function processes data in a manner dependent on the implementing
//  object.  This routine can not fail and can not block, or call any other
//  routine that blocks, or touch pagable memory.
//
STDMETHODIMP_(void) CSwapAPOSFX::APOProcess(
    UINT32 u32NumInputConnections,
    APO_CONNECTION_PROPERTY** ppInputConnections,
    UINT32 u32NumOutputConnections,
    APO_CONNECTION_PROPERTY** ppOutputConnections)
{
    UNREFERENCED_PARAMETER(u32NumInputConnections);
    UNREFERENCED_PARAMETER(u32NumOutputConnections);

    FLOAT32 *pf32InputFrames, *pf32OutputFrames;

    ATLASSERT(m_bIsLocked);

    // assert that the number of input and output connectins fits our registration properties
    ATLASSERT(m_pRegProperties->u32MinInputConnections <= u32NumInputConnections);
    ATLASSERT(m_pRegProperties->u32MaxInputConnections >= u32NumInputConnections);
    ATLASSERT(m_pRegProperties->u32MinOutputConnections <= u32NumOutputConnections);
    ATLASSERT(m_pRegProperties->u32MaxOutputConnections >= u32NumOutputConnections);

    // check APO_BUFFER_FLAGS.
    switch( ppInputConnections[0]->u32BufferFlags )
    {
        case BUFFER_INVALID:
        {
            ATLASSERT(false);  // invalid flag - should never occur.  don't do anything.
            break;
        }
        case BUFFER_VALID:
        case BUFFER_SILENT:
        {
            // get input pointer to connection buffer
            pf32InputFrames = reinterpret_cast<FLOAT32*>(ppInputConnections[0]->pBuffer);
            ATLASSERT( IS_VALID_TYPED_READ_POINTER(pf32InputFrames) );

            // get output pointer to connection buffer
            pf32OutputFrames = reinterpret_cast<FLOAT32*>(ppOutputConnections[0]->pBuffer);
            ATLASSERT( IS_VALID_TYPED_WRITE_POINTER(pf32OutputFrames) );

            if (BUFFER_SILENT == ppInputConnections[0]->u32BufferFlags)
            {
                WriteSilence( pf32InputFrames,
                              ppInputConnections[0]->u32ValidFrameCount,
                              GetSamplesPerFrame() );
            }

            // swap the input buffer in-place
            if (
                !IsEqualGUID(m_AudioProcessingMode, AUDIO_SIGNALPROCESSINGMODE_RAW) &&
                m_fEnableSwapSFX
            )
            {
                ProcessSwap(pf32InputFrames, pf32InputFrames,
                            ppInputConnections[0]->u32ValidFrameCount,
                            m_u32SamplesPerFrame);
            }

            // copy the memory only if there is an output connection, and input/output pointers are unequal
            if ( (0 != u32NumOutputConnections) &&
                  (ppOutputConnections[0]->pBuffer != ppInputConnections[0]->pBuffer) )
            {
                CopyFrames( pf32OutputFrames, pf32InputFrames,
                            ppInputConnections[0]->u32ValidFrameCount,
                            GetSamplesPerFrame() );
            }

            // pass along buffer flags
            ppOutputConnections[0]->u32BufferFlags = ppInputConnections[0]->u32BufferFlags;

            // Set the valid frame count.
            ppOutputConnections[0]->u32ValidFrameCount = ppInputConnections[0]->u32ValidFrameCount;

            break;
        }
        default:
        {
            ATLASSERT(false);  // invalid flag - should never occur
            break;
        }
    } // switch

} // APOProcess
#pragma AVRT_CODE_END

//-------------------------------------------------------------------------
// Description:
//
//  Report delay added by the APO between samples given on input
//  and samples given on output.
//
// Parameters:
//
//      pTime                       - [out] hundreds-of-nanoseconds of delay added
//
// Return values:
//
//      S_OK on success, a failure code on failure
STDMETHODIMP CSwapAPOSFX::GetLatency(HNSTIME* pTime)  
{  
    ASSERT_NONREALTIME();  
    HRESULT hr = S_OK;  
  
    IF_TRUE_ACTION_JUMP(NULL == pTime, hr = E_POINTER, Exit);  
  
    *pTime = 0;
  
Exit:  
    return hr;  
}

//-------------------------------------------------------------------------
// Description:
//
//  Verifies that the APO is ready to process and locks its state if so.
//
// Parameters:
//
//      u32NumInputConnections - [in] number of input connections attached to this APO
//      ppInputConnections - [in] connection descriptor of each input connection attached to this APO
//      u32NumOutputConnections - [in] number of output connections attached to this APO
//      ppOutputConnections - [in] connection descriptor of each output connection attached to this APO
//
// Return values:
//
//      S_OK                                Object is locked and ready to process.
//      E_POINTER                           Invalid pointer passed to function.
//      APOERR_INVALID_CONNECTION_FORMAT    Invalid connection format.
//      APOERR_NUM_CONNECTIONS_INVALID      Number of input or output connections is not valid on
//                                          this APO.
STDMETHODIMP CSwapAPOSFX::LockForProcess(UINT32 u32NumInputConnections,
    APO_CONNECTION_DESCRIPTOR** ppInputConnections,  
    UINT32 u32NumOutputConnections, APO_CONNECTION_DESCRIPTOR** ppOutputConnections)
{
    ASSERT_NONREALTIME();
    HRESULT hr = S_OK;
    
    hr = CBaseAudioProcessingObject::LockForProcess(u32NumInputConnections,
        ppInputConnections, u32NumOutputConnections, ppOutputConnections);
    IF_FAILED_JUMP(hr, Exit);
    
Exit:
    return hr;
}

// The method that this long comment refers to is "Initialize()"
//-------------------------------------------------------------------------
// Description:
//
//  Generic initialization routine for APOs.
//
// Parameters:
//
//     cbDataSize - [in] the size in bytes of the initialization data.
//     pbyData - [in] initialization data specific to this APO
//
// Return values:
//
//     S_OK                         Successful completion.
//     E_POINTER                    Invalid pointer passed to this function.
//     E_INVALIDARG                 Invalid argument
//     AEERR_ALREADY_INITIALIZED    APO is already initialized
//
// Remarks:
//
//  This method initializes the APO.  The data is variable length and
//  should have the form of:
//
//    struct MyAPOInitializationData
//    {
//        APOInitBaseStruct APOInit;
//        ... // add additional fields here
//    };
//
//  If the APO needs no initialization or needs no data to initialize
//  itself, it is valid to pass NULL as the pbyData parameter and 0 as
//  the cbDataSize parameter.
//
//  As part of designing an APO, decide which parameters should be
//  immutable (set once during initialization) and which mutable (changeable
//  during the lifetime of the APO instance).  Immutable parameters must
//  only be specifiable in the Initialize call; mutable parameters must be
//  settable via methods on whichever parameter control interface(s) your
//  APO provides. Mutable values should either be set in the initialize
//  method (if they are required for proper operation of the APO prior to
//  LockForProcess) or default to reasonable values upon initialize and not
//  be required to be set before LockForProcess.
//
//  Within the mutable parameters, you must also decide which can be changed
//  while the APO is locked for processing and which cannot.
//
//  All parameters should be considered immutable as a first choice, unless
//  there is a specific scenario which requires them to be mutable; similarly,
//  no mutable parameters should be changeable while the APO is locked, unless
//  a specific scenario requires them to be.  Following this guideline will
//  simplify the APO's state diagram and implementation and prevent certain
//  types of bug.
//
//  If a parameter changes the APOs latency or MaxXXXFrames values, it must be
//  immutable.
//
//  The default version of this function uses no initialization data, but does verify
//  the passed parameters and set the m_bIsInitialized member to true.
//
//  Note: This method may not be called from a real-time processing thread.
//

HRESULT CSwapAPOSFX::Initialize(UINT32 cbDataSize, BYTE* pbyData)
{
    HRESULT                     hr = S_OK;
    CComPtr<IDeviceTopology>    spMyDeviceTopology;
    CComPtr<IConnector>         spMyConnector;
    GUID                        processingMode;

    IF_TRUE_ACTION_JUMP( ((NULL == pbyData) && (0 != cbDataSize)), hr = E_INVALIDARG, Exit);
    IF_TRUE_ACTION_JUMP( ((NULL != pbyData) && (0 == cbDataSize)), hr = E_INVALIDARG, Exit);

    if (cbDataSize == sizeof(APOInitSystemEffects3))
    {
        APOInitSystemEffects3* papoSysFxInit3 = (APOInitSystemEffects3*)pbyData;

        // Try to get the logging service, but ignore errors as failure to do logging it is not fatal.
        hr = papoSysFxInit3->pServiceProvider->QueryService(SID_AudioProcessingObjectLoggingService, IID_PPV_ARGS(&m_apoLoggingService));
        IF_FAILED_JUMP(hr, Exit);

        // SampleApo supports the new IAudioSystemEffects3 interface so it will receive APOInitSystemEffects3
        // in pbyData if the audio driver has declared support for this.

        // Windows should pass a valid collection.
        ATLASSERT(papoSysFxInit3->pDeviceCollection != nullptr);
        IF_TRUE_ACTION_JUMP(papoSysFxInit3->pDeviceCollection == nullptr, hr = E_INVALIDARG, Exit);

        // Use IMMDevice to activate IAudioSystemEffectsPropertyStore that contains the default, user and
        // volatile settings.
        IMMDeviceCollection* deviceCollection = reinterpret_cast<APOInitSystemEffects3*>(pbyData)->pDeviceCollection;
        UINT32 numDevices;
        // Get the endpoint on which this APO has been created
        // (It is the last device in the device collection)
        hr = deviceCollection->GetCount(&numDevices);
        IF_FAILED_JUMP(hr, Exit);

        hr = numDevices > 0 ? S_OK : E_UNEXPECTED;
        IF_FAILED_JUMP(hr, Exit);

        hr = deviceCollection->Item(numDevices - 1, &m_audioEndpoint);
        IF_FAILED_JUMP(hr, Exit);

        wil::unique_prop_variant activationParam;
        hr = InitPropVariantFromCLSID(SWAP_APO_SFX_CONTEXT, &activationParam);
        IF_FAILED_JUMP(hr, Exit);

        wil::com_ptr_nothrow<IAudioSystemEffectsPropertyStore> effectsPropertyStore;
        hr = m_audioEndpoint->Activate(__uuidof(effectsPropertyStore), CLSCTX_ALL, &activationParam, effectsPropertyStore.put_void());
        IF_FAILED_JUMP(hr, Exit);

        // This is where an APO might want to open the volatile or default property stores as well
        // Use STGM_READWRITE if IPropertyStore::SetValue is needed.
        hr = effectsPropertyStore->OpenUserPropertyStore(STGM_READ, m_userStore.put());
        IF_FAILED_JUMP(hr, Exit);

        // Get the IDeviceTopology and IConnector interfaces to communicate with this
        // APO's counterpart audio driver. This can be used for any proprietary
        // communication.
        hr = papoSysFxInit3->pDeviceCollection->Item(papoSysFxInit3->nSoftwareIoDeviceInCollection, &m_deviceTopologyMMDevice);
        IF_FAILED_JUMP(hr, Exit);

        hr = m_deviceTopologyMMDevice->Activate(__uuidof(IDeviceTopology), CLSCTX_ALL, NULL, (void**)&spMyDeviceTopology);
        IF_FAILED_JUMP(hr, Exit);

        hr = spMyDeviceTopology->GetConnector(papoSysFxInit3->nSoftwareIoConnectorIndex, &spMyConnector);
        IF_FAILED_JUMP(hr, Exit);

        // Save the processing mode being initialized.
        processingMode = papoSysFxInit3->AudioProcessingMode;
    }
    else if (cbDataSize == sizeof(APOInitSystemEffects2))
    {
        //
        // Initialize for mode-specific signal processing
        //
        APOInitSystemEffects2* papoSysFxInit2 = (APOInitSystemEffects2*)pbyData;

        // Save reference to the effects property store. This saves effects settings
        // and is the communication medium between this APO and any associated UI.
        m_spAPOSystemEffectsProperties = papoSysFxInit2->pAPOSystemEffectsProperties;

        // Windows should pass a valid collection.
        ATLASSERT(papoSysFxInit2->pDeviceCollection != nullptr);
        IF_TRUE_ACTION_JUMP(papoSysFxInit2->pDeviceCollection == nullptr, hr = E_INVALIDARG, Exit);

        // Get the IDeviceTopology and IConnector interfaces to communicate with this
        // APO's counterpart audio driver. This can be used for any proprietary
        // communication.
        hr = papoSysFxInit2->pDeviceCollection->Item(papoSysFxInit2->nSoftwareIoDeviceInCollection, &m_deviceTopologyMMDevice);
        IF_FAILED_JUMP(hr, Exit);

        hr = m_deviceTopologyMMDevice->Activate(__uuidof(IDeviceTopology), CLSCTX_ALL, NULL, (void**)&spMyDeviceTopology);
        IF_FAILED_JUMP(hr, Exit);

        hr = spMyDeviceTopology->GetConnector(papoSysFxInit2->nSoftwareIoConnectorIndex, &spMyConnector);
        IF_FAILED_JUMP(hr, Exit);

        // Save the processing mode being initialized.
        processingMode = papoSysFxInit2->AudioProcessingMode;

    }
    else if (cbDataSize == sizeof(APOInitSystemEffects))
    {
        //
        // Initialize for default signal processing
        //
        APOInitSystemEffects* papoSysFxInit = (APOInitSystemEffects*)pbyData;

        // Save reference to the effects property store. This saves effects settings
        // and is the communication medium between this APO and any associated UI.
        m_spAPOSystemEffectsProperties = papoSysFxInit->pAPOSystemEffectsProperties;

        // Assume default processing mode
        processingMode = AUDIO_SIGNALPROCESSINGMODE_DEFAULT;
    }
    else
    {
        // Invalid initialization size
        hr = E_INVALIDARG;
        goto Exit;
    }

    // Validate then save the processing mode. Note an endpoint effects APO
    // does not depend on the mode. Windows sets the APOInitSystemEffects2
    // AudioProcessingMode member to GUID_NULL for an endpoint effects APO.
    IF_TRUE_ACTION_JUMP((processingMode != AUDIO_SIGNALPROCESSINGMODE_DEFAULT        &&
                         processingMode != AUDIO_SIGNALPROCESSINGMODE_RAW            &&
                         processingMode != AUDIO_SIGNALPROCESSINGMODE_COMMUNICATIONS &&
                         processingMode != AUDIO_SIGNALPROCESSINGMODE_SPEECH         &&
                         processingMode != AUDIO_SIGNALPROCESSINGMODE_MEDIA          &&
                         processingMode != AUDIO_SIGNALPROCESSINGMODE_MOVIE          &&
                         processingMode != AUDIO_SIGNALPROCESSINGMODE_NOTIFICATION), hr = E_INVALIDARG, Exit);
    m_AudioProcessingMode = processingMode;

    //
    // An APO that implements signal processing more complex than this sample
    // would configure its processing for the processingMode determined above.
    // If necessary, the APO would also use the IDeviceTopology and IConnector
    // interfaces retrieved above to communicate with its counterpart audio
    // driver to configure any additional signal processing in the driver and
    // associated hardware.
    //

    //
    //  Get the current values
    //
    if (m_userStore != nullptr)
    {
        m_fEnableSwapSFX = GetCurrentEffectsSetting(m_userStore.get(), PKEY_Endpoint_Enable_Channel_Swap_SFX, m_AudioProcessingMode);
    }

    if (m_spAPOSystemEffectsProperties != NULL)
    {
        m_fEnableSwapSFX = GetCurrentEffectsSetting(m_spAPOSystemEffectsProperties, PKEY_Endpoint_Enable_Channel_Swap_SFX, m_AudioProcessingMode);
    }
    
    RtlZeroMemory(m_effectInfos, sizeof(m_effectInfos));
    m_effectInfos[0] = { SwapEffectId, TRUE, m_fEnableSwapSFX ? AUDIO_SYSTEMEFFECT_STATE_ON : AUDIO_SYSTEMEFFECT_STATE_OFF };

    if (cbDataSize != sizeof(APOInitSystemEffects3))
    {
        //
        //  Register for notification of registry updates
        //
        hr = m_spEnumerator.CoCreateInstance(__uuidof(MMDeviceEnumerator));
        IF_FAILED_JUMP(hr, Exit);

        hr = m_spEnumerator->RegisterEndpointNotificationCallback(this);
        IF_FAILED_JUMP(hr, Exit);

        m_bRegisteredEndpointNotificationCallback = TRUE;
    }

    m_bIsInitialized = true;

Exit:
    return hr;
}

//-------------------------------------------------------------------------
//
// GetEffectsList
//
//  Retrieves the list of signal processing effects currently active and
//  stores an event to be signaled if the list changes.
//
// Parameters
//
//  ppEffectsIds - returns a pointer to a list of GUIDs each identifying a
//      class of effect. The caller is responsible for freeing this memory by
//      calling CoTaskMemFree.
//
//  pcEffects - returns a count of GUIDs in the list.
//
//  Event - passes an event handle. The APO signals this event when the list
//      of effects changes from the list returned from this function. The APO
//      uses this event until either this function is called again or the APO
//      is destroyed. The passed handle may be NULL. In this case, the APO
//      stops using any previous handle and does not signal an event.
//
// Remarks
//
//  An APO imlements this method to allow Windows to discover the current
//  effects applied by the APO. The list of effects may depend on what signal
//  processing mode the APO initialized (see AudioProcessingMode in the
//  APOInitSystemEffects2 structure) as well as any end user configuration.
//
//  If there are no effects then the function still succeeds, ppEffectsIds
//  returns a NULL pointer, and pcEffects returns a count of 0.
//
STDMETHODIMP CSwapAPOSFX::GetEffectsList(_Outptr_result_buffer_maybenull_(*pcEffects) LPGUID *ppEffectsIds, _Out_ UINT *pcEffects, _In_ HANDLE Event)
{
    HRESULT hr;
    BOOL effectsLocked = FALSE;
    UINT cEffects = 0;
    
    IF_TRUE_ACTION_JUMP(ppEffectsIds == NULL, hr = E_POINTER, Exit);
    IF_TRUE_ACTION_JUMP(pcEffects == NULL, hr = E_POINTER, Exit);

    // Synchronize access to the effects list and effects changed event
    m_EffectsLock.Enter();
    effectsLocked = TRUE;

    // Always close existing effects change event handle
    if (m_hEffectsChangedEvent != NULL)
    {
        CloseHandle(m_hEffectsChangedEvent);
        m_hEffectsChangedEvent = NULL;
    }

    // If an event handle was specified, save it here (duplicated to control lifetime)
    if (Event != NULL)
    {
        if (!DuplicateHandle(GetCurrentProcess(), Event, GetCurrentProcess(), &m_hEffectsChangedEvent, EVENT_MODIFY_STATE, FALSE, 0))
        {
            hr = HRESULT_FROM_WIN32(GetLastError());
            goto Exit;
        }
    }

    // naked scope to force the initialization of list[] to be after we enter the critical section
    {
        struct EffectControl
        {
            GUID effect;
            BOOL control;
        };
        
        EffectControl list[] =
        {
            { SwapEffectId,  m_fEnableSwapSFX  },
        };
    
        if (!IsEqualGUID(m_AudioProcessingMode, AUDIO_SIGNALPROCESSINGMODE_RAW))
        {
            // count the active effects
            for (UINT i = 0; i < ARRAYSIZE(list); i++)
            {
                if (list[i].control)
                {
                    cEffects++;
                }
            }
        }

        if (0 == cEffects)
        {
            *ppEffectsIds = NULL;
            *pcEffects = 0;
        }
        else
        {
            GUID *pEffectsIds = (LPGUID)CoTaskMemAlloc(sizeof(GUID) * cEffects);
            if (pEffectsIds == nullptr)
            {
                hr = E_OUTOFMEMORY;
                goto Exit;
            }
            
            // pick up the active effects
            UINT j = 0;
            for (UINT i = 0; i < ARRAYSIZE(list); i++)
            {
                if (list[i].control)
                {
                    pEffectsIds[j++] = list[i].effect;
                }
            }

            *ppEffectsIds = pEffectsIds;
            *pcEffects = cEffects;
        }
        
        hr = S_OK;
    }
    
Exit:
    if (effectsLocked)
    {
        m_EffectsLock.Leave();
    }
    return hr;
}

HRESULT CSwapAPOSFX::GetControllableSystemEffectsList(_Outptr_result_buffer_maybenull_(*numEffects) AUDIO_SYSTEMEFFECT** effects, _Out_ UINT* numEffects, _In_opt_ HANDLE event)
{
    RETURN_HR_IF_NULL(E_POINTER, effects);
    RETURN_HR_IF_NULL(E_POINTER, numEffects);

    *effects = nullptr;
    *numEffects = 0;

    // Always close existing effects change event handle
    if (m_hEffectsChangedEvent != NULL)
    {
        CloseHandle(m_hEffectsChangedEvent);
        m_hEffectsChangedEvent = NULL;
    }

    // If an event handle was specified, save it here (duplicated to control lifetime)
    if (event != NULL)
    {
        if (!DuplicateHandle(GetCurrentProcess(), event, GetCurrentProcess(), &m_hEffectsChangedEvent, EVENT_MODIFY_STATE, FALSE, 0))
        {
            RETURN_IF_FAILED(HRESULT_FROM_WIN32(GetLastError()));
        }
    }

    if (!IsEqualGUID(m_AudioProcessingMode, AUDIO_SIGNALPROCESSINGMODE_RAW))
    {
        wil::unique_cotaskmem_array_ptr<AUDIO_SYSTEMEFFECT> audioEffects(
            static_cast<AUDIO_SYSTEMEFFECT*>(CoTaskMemAlloc(NUM_OF_EFFECTS * sizeof(AUDIO_SYSTEMEFFECT))), NUM_OF_EFFECTS);
        RETURN_IF_NULL_ALLOC(audioEffects.get());

        for (UINT i = 0; i < NUM_OF_EFFECTS; i++)
        {
            audioEffects[i].id = m_effectInfos[i].id;
            audioEffects[i].state = m_effectInfos[i].state;
            audioEffects[i].canSetState = m_effectInfos[i].canSetState;
        }

        *numEffects = (UINT)audioEffects.size();
        *effects = audioEffects.release();
    }

    return S_OK;
}

HRESULT CSwapAPOSFX::SetAudioSystemEffectState(GUID effectId, AUDIO_SYSTEMEFFECT_STATE state)
{
    for (auto effectInfo : m_effectInfos)
    {
        if (effectId == effectInfo.id)
        {
            AUDIO_SYSTEMEFFECT_STATE oldState = effectInfo.state;
            effectInfo.state = state;

            // Synchronize access to the effects list and effects changed event
            m_EffectsLock.Enter();

            // If anything changed and a change event handle exists
            if (oldState != effectInfo.state)
            {
                SetEvent(m_hEffectsChangedEvent);
                m_apoLoggingService->ApoLog(APO_LOG_LEVEL_INFO, L"CSwapAPOSFX::SetAudioSystemEffectState - effect: " GUID_FORMAT_STRING L", state: %i", effectInfo.id, effectInfo.state);
            }

            m_EffectsLock.Leave();
            
            return S_OK;
        }
    }

    return E_NOTFOUND;
}

//-------------------------------------------------------------------------
// Description:
//
//
//
// Parameters:
//
//
//
// Return values:
//
//
//
// Remarks:
//
//
HRESULT CSwapAPOSFX::OnPropertyValueChanged(LPCWSTR pwstrDeviceId, const PROPERTYKEY key)
{
    HRESULT     hr = S_OK;

    UNREFERENCED_PARAMETER(pwstrDeviceId);

    if (!m_spAPOSystemEffectsProperties)
    {
        return hr;
    }

    // If either the master disable or our APO's enable properties changed...
    if (PK_EQUAL(key, PKEY_Endpoint_Enable_Channel_Swap_SFX) ||
        PK_EQUAL(key, PKEY_AudioEndpoint_Disable_SysFx))
    {
        LONG nChanges = 0;

        // Synchronize access to the effects list and effects changed event
        m_EffectsLock.Enter();

        struct KeyControl
        {
            PROPERTYKEY key;
            LONG *value;
        };
        
        KeyControl controls[] =
        {
            { PKEY_Endpoint_Enable_Channel_Swap_SFX, &m_fEnableSwapSFX  },
        };
        
        for (int i = 0; i < ARRAYSIZE(controls); i++)
        {
            LONG fOldValue;
            LONG fNewValue = true;
            
            // Get the state of whether channel swap MFX is enabled or not
            fNewValue = GetCurrentEffectsSetting(m_spAPOSystemEffectsProperties, controls[i].key, m_AudioProcessingMode);

            // Swap in the new setting
            fOldValue = InterlockedExchange(controls[i].value, fNewValue);
            
            if (fNewValue != fOldValue)
            {
                nChanges++;
            }
        }
        
        // If anything changed and a change event handle exists
        if ((nChanges > 0) && (m_hEffectsChangedEvent != NULL))
        {
            SetEvent(m_hEffectsChangedEvent);
        }

        m_EffectsLock.Leave();
    }

    return hr;
}

HRESULT CSwapAPOSFX::GetApoNotificationRegistrationInfo2(APO_NOTIFICATION_TYPE maxType, _Out_writes_(*count) APO_NOTIFICATION_DESCRIPTOR **apoNotifications, _Out_ DWORD *count)
{
    *apoNotifications = nullptr;
    *count = 0;

    // Let the OS know what notifications we are interested in by returning an array of
    // APO_NOTIFICATION_DESCRIPTORs.

    DWORD numDescriptors = 1;

    // Since APO_NOTIFICATION_TYPE_AUDIO_ENVIRONMENT_STATE_CHANGE may not be available,
    // Adjust our array accordingly
    if (maxType >=  APO_NOTIFICATION_TYPE_AUDIO_ENVIRONMENT_STATE_CHANGE)
    {
        // Audio environment state change notifications are supported
        m_bAudioEnvironmentStateNotificationsAvailable = TRUE;
        numDescriptors++;
    }

    wil::unique_cotaskmem_ptr<APO_NOTIFICATION_DESCRIPTOR[]> apoNotificationDescriptors;

    apoNotificationDescriptors.reset(static_cast<APO_NOTIFICATION_DESCRIPTOR*>(
        CoTaskMemAlloc(sizeof(APO_NOTIFICATION_DESCRIPTOR) * numDescriptors)));
    RETURN_IF_NULL_ALLOC(apoNotificationDescriptors);

    // Our APO wants to get notified when a endpoint property changes on the audio endpoint.
    apoNotificationDescriptors[0].type = APO_NOTIFICATION_TYPE_ENDPOINT_PROPERTY_CHANGE;
    (void)m_audioEndpoint.query_to(&apoNotificationDescriptors[0].audioEndpointPropertyChange.device);

    if (m_bAudioEnvironmentStateNotificationsAvailable)
    {
        // ... and when there are Audio Environment State changes (like Spatial Status)
        // In the case of APO_NOTIFICATION_TYPE_AUDIO_ENVIRONMENT_STATE_CHANGE, only
        // the type needs to be set.  Notifications will be relative to the endpoint device
        // this APO is instantiated on.
        //
        // HandleNotification will be called immediately after registering for this
        // notification with the initial spatial audio status.
        apoNotificationDescriptors[1].type = APO_NOTIFICATION_TYPE_AUDIO_ENVIRONMENT_STATE_CHANGE;
    }
    
    *apoNotifications = apoNotificationDescriptors.release();
    *count = numDescriptors;

    return S_OK;
}

void CSwapAPOSFX::HandleNotification(APO_NOTIFICATION *apoNotification)
{
    if (apoNotification->type == APO_NOTIFICATION_TYPE_ENDPOINT_PROPERTY_CHANGE)
    {
        // If either the master disable or our APO's enable properties changed...
        if (PK_EQUAL(apoNotification->audioEndpointPropertyChange.propertyKey, PKEY_Endpoint_Enable_Channel_Swap_SFX) ||
            PK_EQUAL(apoNotification->audioEndpointPropertyChange.propertyKey, PKEY_AudioEndpoint_Disable_SysFx))
        {
            struct KeyControl
            {
                PROPERTYKEY key;
                LONG* value;
            };

            KeyControl controls[] = {
                {PKEY_Endpoint_Enable_Channel_Swap_SFX, &m_fEnableSwapSFX},
            };

            m_apoLoggingService->ApoLog(APO_LOG_LEVEL_INFO, L"CSwapAPOSFX::HandleNotification - pkey: " GUID_FORMAT_STRING L" %d", GUID_FORMAT_ARGS(apoNotification->audioEndpointPropertyChange.propertyKey.fmtid), apoNotification->audioEndpointPropertyChange.propertyKey.pid);

            for (int i = 0; i < ARRAYSIZE(controls); i++)
            {
                LONG fNewValue = true;

                // Get the state of whether channel swap MFX is enabled or not
                fNewValue = GetCurrentEffectsSetting(m_userStore.get(), controls[i].key, m_AudioProcessingMode);

                SetAudioSystemEffectState(m_effectInfos[i].id, fNewValue ? AUDIO_SYSTEMEFFECT_STATE_ON : AUDIO_SYSTEMEFFECT_STATE_OFF);
            }
        }
    }
    else if (apoNotification->type == APO_NOTIFICATION_TYPE_AUDIO_ENVIRONMENT_STATE_CHANGE)
    {
        wil::unique_prop_variant var;
        if (SUCCEEDED(apoNotification->audioEnvironmentChange.propertyStore->GetValue( 
            PKEY_AudioEnvironment_SpatialAudioActive, &var)) && 
            var.vt == VT_BOOL)
        {
            m_bIsSpatialAudioInUse = var.boolVal;
            m_apoLoggingService->ApoLog(APO_LOG_LEVEL_VERBOSE, L"HandleNotification Spatial Enabled State = %d", m_bIsSpatialAudioInUse);
        }
    }
}

//-------------------------------------------------------------------------
// Description:
//
//  Destructor.
//
// Parameters:
//
//     void
//
// Return values:
//
//      void
//
// Remarks:
//
//      This method deletes whatever was allocated.
//
//      This method may not be called from a real-time processing thread.
//
CSwapAPOSFX::~CSwapAPOSFX(void)
{
    //
    // unregister for callbacks
    //
    if (m_bRegisteredEndpointNotificationCallback)
    {
        m_spEnumerator->UnregisterEndpointNotificationCallback(this);
    }

    if (m_hEffectsChangedEvent != NULL)
    {
        CloseHandle(m_hEffectsChangedEvent);
    }
} // ~CSwapAPOSFX
