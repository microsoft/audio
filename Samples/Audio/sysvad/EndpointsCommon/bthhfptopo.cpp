/*++

Copyright (c) Microsoft Corporation All Rights Reserved

Module Name:

    bthhfptopo.cpp

Abstract:

    Implementation of topology miniport for the Bluetooth Hands-Free Profile (external).

--*/
 #ifdef SYSVAD_BTH_BYPASS

#pragma warning (disable : 4127)

#include <sysvad.h>
#include "simple.h"
#include "mintopo.h"
#include "bthhfptopo.h"

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS
PropertyHandler_BthHfpVolumeLevel_BasicSupport
( 
    _In_ PPCPROPERTY_REQUEST      PropertyRequest
)
/*++

Routine Description:

  Handles basic support for Bluetooth HFP ( KSPROPSETID_Audio, KSPROPERTY_AUDIO_VOLUMELEVEL )

Arguments:

  PropertyRequest - 

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();
    DPF_ENTER(("[PropertyHandler_BthHfpVolumeLevel_BasicSupport]"));

    NTSTATUS                ntStatus          = STATUS_SUCCESS;
    ULONG                   cbDescriptionSize = sizeof(KSPROPERTY_DESCRIPTION);
    ASSERT(PropertyRequest);

    if (PropertyRequest->ValueSize >= cbDescriptionSize)
    {
        PCMiniportTopology      miniport            = (PCMiniportTopology)PropertyRequest->MajorTarget;
        ULONG                   volumeSettingsSize  = 0;
        PKSPROPERTY_VALUES      volumeSettings;
        PKSPROPERTY_DESCRIPTION propDesc;
        PSIDEBANDDEVICECOMMON   bthHfpDevice;

        propDesc        = PKSPROPERTY_DESCRIPTION(PropertyRequest->Value);
        bthHfpDevice    = miniport->GetSidebandDevice(); // weak ref.
        ASSERT(bthHfpDevice != NULL);
        
        volumeSettings  = (PKSPROPERTY_VALUES)bthHfpDevice->GetVolumeSettings(miniport->m_DeviceType, &volumeSettingsSize);
        ASSERT(volumeSettings != NULL);
        ASSERT(volumeSettingsSize != 0);
        
        ULONG cbMemberListSize = volumeSettingsSize - sizeof(KSPROPERTY_VALUES);
        ULONG cbFullProperty    = cbDescriptionSize + cbMemberListSize;

        //
        // Init description prop header.
        //
        propDesc->AccessFlags       = KSPROPERTY_TYPE_ALL;
        propDesc->DescriptionSize   = cbFullProperty;
        propDesc->PropTypeSet       = volumeSettings->PropTypeSet;
        propDesc->MembersListCount  = volumeSettings->MembersListCount;
        propDesc->Reserved          = 0;

        // if return buffer can hold range description, return it
        if(PropertyRequest->ValueSize >= cbFullProperty)
        {
            RtlCopyMemory((PVOID)(propDesc + 1), volumeSettings->MembersList, cbMemberListSize);
            // set the return value size
            PropertyRequest->ValueSize = cbFullProperty;
        } 
        else
        {
            // otherwise only return description header
            // set the return value size
            PropertyRequest->ValueSize = cbDescriptionSize;
        }
    } 
    else if(PropertyRequest->ValueSize >= sizeof(ULONG))
    {
        // if return buffer can hold a ULONG, return the access flags
        PULONG AccessFlags = PULONG(PropertyRequest->Value);

        PropertyRequest->ValueSize = sizeof(ULONG);
        *AccessFlags = KSPROPERTY_TYPE_ALL;
    }
    else
    {
        PropertyRequest->ValueSize = 0;
        ntStatus = STATUS_BUFFER_TOO_SMALL;
    }

    return ntStatus;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS
PropertyHandler_BthHfpJackDescription
( 
    _In_ PPCPROPERTY_REQUEST      PropertyRequest, 
    _In_ ULONG                    cJackDescriptions,
    _In_reads_(cJackDescriptions) PKSJACK_DESCRIPTION * JackDescriptions
)
/*++

Routine Description:

  Handles ( KSPROPSETID_Jack, KSPROPERTY_JACK_DESCRIPTION )

Arguments:

  PropertyRequest - 

  cJackDescriptions -

  JackDescriptions - 

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();

    ASSERT(PropertyRequest);

    DPF_ENTER(("[PropertyHandler_BthHfpJackDescription]"));

    NTSTATUS                ntStatus            = STATUS_INVALID_DEVICE_REQUEST;
    ULONG                   nPinId              = (ULONG)-1;
    PCMiniportTopology      miniport            = (PCMiniportTopology)PropertyRequest->MajorTarget;

    if (PropertyRequest->InstanceSize >= sizeof(ULONG))
    {
        nPinId = *(PULONG(PropertyRequest->Instance));

        if ((nPinId < cJackDescriptions) && (JackDescriptions[nPinId] != NULL))
        {
            if (PropertyRequest->Verb & KSPROPERTY_TYPE_BASICSUPPORT)
            {
                ntStatus = 
                    PropertyHandler_BasicSupport
                    (
                        PropertyRequest,
                        KSPROPERTY_TYPE_BASICSUPPORT | KSPROPERTY_TYPE_GET,
                        VT_ILLEGAL
                    );
            }
            else
            {
                ULONG cbNeeded = sizeof(KSMULTIPLE_ITEM) + sizeof(KSJACK_DESCRIPTION);

                if (PropertyRequest->ValueSize == 0)
                {
                    PropertyRequest->ValueSize = cbNeeded;
                    ntStatus = STATUS_BUFFER_OVERFLOW;
                }
                else if (PropertyRequest->ValueSize < cbNeeded)
                {
                    ntStatus = STATUS_BUFFER_TOO_SMALL;
                }
                else
                {
                    if (PropertyRequest->Verb & KSPROPERTY_TYPE_GET)
                    {
                        PSIDEBANDDEVICECOMMON bthHfpDevice    = NULL;
                        PKSMULTIPLE_ITEM    pMI             = (PKSMULTIPLE_ITEM)PropertyRequest->Value;
                        PKSJACK_DESCRIPTION pDesc           = (PKSJACK_DESCRIPTION)(pMI+1);

                        bthHfpDevice = miniport->GetSidebandDevice(); // weak ref.
                        ASSERT(bthHfpDevice != NULL);
                        
                        pMI->Size = cbNeeded;
                        pMI->Count = 1;

                        RtlCopyMemory(pDesc, JackDescriptions[nPinId], sizeof(KSJACK_DESCRIPTION));

                        pDesc->IsConnected = bthHfpDevice->GetConnectionStatus() ? TRUE : FALSE;
                        
                        ntStatus = STATUS_SUCCESS;
                    }
                }
            }
        }
    }

    return ntStatus;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS
PropertyHandler_BthHfpJackDescription2
( 
    _In_ PPCPROPERTY_REQUEST      PropertyRequest,
    _In_ ULONG                    cJackDescriptions,
    _In_reads_(cJackDescriptions) PKSJACK_DESCRIPTION * JackDescriptions
)
/*++

Routine Description:

  Handles ( KSPROPSETID_Jack, KSPROPERTY_JACK_DESCRIPTION2 )

Arguments:

  PropertyRequest - 

  cJackDescriptions -

  JackDescriptions - 

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();

    ASSERT(PropertyRequest);

    DPF_ENTER(("[PropertyHandler_BthHfpJackDescription2]"));

    NTSTATUS                ntStatus = STATUS_INVALID_DEVICE_REQUEST;
    ULONG                   nPinId = (ULONG)-1;
    
    if (PropertyRequest->InstanceSize >= sizeof(ULONG))
    {
        nPinId = *(PULONG(PropertyRequest->Instance));

        if ((nPinId < cJackDescriptions) && (JackDescriptions[nPinId] != NULL))
        {
            if (PropertyRequest->Verb & KSPROPERTY_TYPE_BASICSUPPORT)
            {
                ntStatus = 
                    PropertyHandler_BasicSupport
                    (
                        PropertyRequest,
                        KSPROPERTY_TYPE_BASICSUPPORT | KSPROPERTY_TYPE_GET,
                        VT_ILLEGAL
                    );
            }
            else
            {
                ULONG cbNeeded = sizeof(KSMULTIPLE_ITEM) + sizeof(KSJACK_DESCRIPTION2);

                if (PropertyRequest->ValueSize == 0)
                {
                    PropertyRequest->ValueSize = cbNeeded;
                    ntStatus = STATUS_BUFFER_OVERFLOW;
                }
                else if (PropertyRequest->ValueSize < cbNeeded)
                {
                    ntStatus = STATUS_BUFFER_TOO_SMALL;
                }
                else
                {
                    if (PropertyRequest->Verb & KSPROPERTY_TYPE_GET)
                    {
                        PKSMULTIPLE_ITEM pMI = (PKSMULTIPLE_ITEM)PropertyRequest->Value;
                        PKSJACK_DESCRIPTION2 pDesc = (PKSJACK_DESCRIPTION2)(pMI+1);

                        pMI->Size = cbNeeded;
                        pMI->Count = 1;
                        
                        RtlZeroMemory(pDesc, sizeof(KSJACK_DESCRIPTION2));

                        //
                        // Specifies the lower 16 bits of the DWORD parameter. This parameter indicates whether 
                        // the jack is currently active, streaming, idle, or hardware not ready.
                        //
                        pDesc->DeviceStateInfo = 0;

                        //
                        // From MSDN:
                        // "If an audio device lacks jack presence detection, the IsConnected member of
                        // the KSJACK_DESCRIPTION structure must always be set to TRUE. To remove the 
                        // ambiguity that results from this dual meaning of the TRUE value for IsConnected, 
                        // a client application can call IKsJackDescription2::GetJackDescription2 to read 
                        // the JackCapabilities flag of the KSJACK_DESCRIPTION2 structure. If this flag has
                        // the JACKDESC2_PRESENCE_DETECT_CAPABILITY bit set, it indicates that the endpoint 
                        // does in fact support jack presence detection. In that case, the return value of 
                        // the IsConnected member can be interpreted to accurately reflect the insertion status
                        // of the jack."
                        //
                        // Bit definitions:
                        // 0x00000001 - JACKDESC2_PRESENCE_DETECT_CAPABILITY
                        // 0x00000002 - JACKDESC2_DYNAMIC_FORMAT_CHANGE_CAPABILITY 
                        //
                        pDesc->JackCapabilities = JACKDESC2_PRESENCE_DETECT_CAPABILITY;
                        
                        ntStatus = STATUS_SUCCESS;
                    }
                }
            }
        }
    }

    return ntStatus;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS
PropertyHandler_BthHfpJackContainerId
( 
    _In_ PPCPROPERTY_REQUEST      PropertyRequest,
    _In_ ULONG                    cJackDescriptions,
    _In_reads_(cJackDescriptions) PKSJACK_DESCRIPTION * JackDescriptions
)
/*++

Routine Description:

  Handles ( KSPROPSETID_Jack, KSPROPERTY_JACK_CONTAINERID )

Arguments:

  PropertyRequest - 

  cJackDescriptions -

  JackDescriptions - 

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();

    ASSERT(PropertyRequest);

    DPF_ENTER(("[PropertyHandler_BthHfpJackContainerId]"));

    NTSTATUS                ntStatus    = STATUS_INVALID_DEVICE_REQUEST;
    PCMiniportTopology      miniport    = (PCMiniportTopology)PropertyRequest->MajorTarget;
    ULONG                   nPinId      = (ULONG)-1;
    
    if (PropertyRequest->InstanceSize >= sizeof(ULONG))
    {
        nPinId = *(PULONG(PropertyRequest->Instance));

        // This property is only valid on bridge pins.
        if ((nPinId < cJackDescriptions) && (JackDescriptions[nPinId] != NULL))
        {
            if (PropertyRequest->Verb & KSPROPERTY_TYPE_BASICSUPPORT)
            {
                ntStatus = 
                    PropertyHandler_BasicSupport
                    (
                        PropertyRequest,
                        KSPROPERTY_TYPE_BASICSUPPORT | KSPROPERTY_TYPE_GET,
                        VT_ILLEGAL
                    );
            }
            else
            {
                ULONG cbNeeded = sizeof(GUID);

                if (PropertyRequest->ValueSize == 0)
                {
                    PropertyRequest->ValueSize = cbNeeded;
                    ntStatus = STATUS_BUFFER_OVERFLOW;
                }
                else if (PropertyRequest->ValueSize < cbNeeded)
                {
                    ntStatus = STATUS_BUFFER_TOO_SMALL;
                }
                else
                {
                    if (PropertyRequest->Verb & KSPROPERTY_TYPE_GET)
                    {
                        PSIDEBANDDEVICECOMMON bthHfpDevice = NULL;
                        
                        GUID* guid = (GUID *)PropertyRequest->Value;
                        
                        bthHfpDevice = miniport->GetSidebandDevice(); // weak ref.
                        ASSERT(bthHfpDevice != NULL);

                        *guid = bthHfpDevice->GetContainerId(miniport->m_DeviceType);

                        ntStatus = STATUS_SUCCESS;
                    }
                }
            }
        }
    }

    return ntStatus;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS
PropertyHandler_BthHfpOneShotReconnect
( 
    _In_ PPCPROPERTY_REQUEST      PropertyRequest 
)
/*++

Routine Description:

  Handles ( KSPROPSETID_BtAudio, KSPROPERTY_ONESHOT_RECONNECT )

Arguments:

  PropertyRequest - 

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();

    ASSERT(PropertyRequest);

    DPF_ENTER(("[PropertyHandler_BthHfpOneShotReconnect]"));

    NTSTATUS                ntStatus    = STATUS_INVALID_DEVICE_REQUEST;
    PCMiniportTopology      miniport    = (PCMiniportTopology)PropertyRequest->MajorTarget;
    
    if (PropertyRequest->Verb & KSPROPERTY_TYPE_BASICSUPPORT)
    {
        ntStatus = 
            PropertyHandler_BasicSupport
            (
                PropertyRequest,
                KSPROPERTY_TYPE_BASICSUPPORT | KSPROPERTY_TYPE_GET,
                VT_ILLEGAL
            );
    }
    else if (PropertyRequest->Verb & KSPROPERTY_TYPE_GET)
    {
        PSIDEBANDDEVICECOMMON bthHfpDevice = NULL;
        
        bthHfpDevice = miniport->GetSidebandDevice(); // weak ref.
        ASSERT(bthHfpDevice != NULL);

        ntStatus = bthHfpDevice->Connect();
    }

    return ntStatus;
}

//=============================================================================
#pragma code_seg("PAGE")
NTSTATUS
PropertyHandler_BthHfpOneDisconnect
( 
    _In_ PPCPROPERTY_REQUEST      PropertyRequest 
)
/*++

Routine Description:

  Handles ( KSPROPSETID_BtAudio, KSPROPERTY_ONESHOT_DISCONNECT )

Arguments:

  PropertyRequest - 

Return Value:

  NT status code.

--*/
{
    PAGED_CODE();

    ASSERT(PropertyRequest);

    DPF_ENTER(("[PropertyHandler_BthHfpOneDisconnect]"));

    NTSTATUS                ntStatus    = STATUS_INVALID_DEVICE_REQUEST;
    PCMiniportTopology      miniport    = (PCMiniportTopology)PropertyRequest->MajorTarget;
    
    if (PropertyRequest->Verb & KSPROPERTY_TYPE_BASICSUPPORT)
    {
        ntStatus = 
            PropertyHandler_BasicSupport
            (
                PropertyRequest,
                KSPROPERTY_TYPE_BASICSUPPORT | KSPROPERTY_TYPE_GET,
                VT_ILLEGAL
            );
    }
    else if (PropertyRequest->Verb & KSPROPERTY_TYPE_GET)
    {
        PSIDEBANDDEVICECOMMON bthHfpDevice = NULL;
        
        bthHfpDevice = miniport->GetSidebandDevice(); // weak ref.
        ASSERT(bthHfpDevice != NULL);

        ntStatus = bthHfpDevice->Disconnect();
    }

    return ntStatus;
}

//=============================================================================
#pragma code_seg()
NTSTATUS 
PropertyHandler_BthHfpTopoNodeEvent
(
    _In_    PPCEVENT_REQUEST    EventRequest
)
{
    ASSERT(EventRequest);

    DPF_ENTER(("[PropertyHandler_BthHfpTopoNodeEvent]"));

    // The major target is the object pointer to the topology miniport.
    PCMiniportTopology  pMiniport = (PCMiniportTopology)EventRequest->MajorTarget;
    ASSERT (pMiniport);

    switch (EventRequest->Verb)
    {
        // Do we support event handling?!?
        case PCEVENT_VERB_SUPPORT:
            DPF(D_VERBOSE, ("BasicSupport Query for event."));
            break;

        // We should add the event now!
        case PCEVENT_VERB_ADD:
            DPF(D_VERBOSE, ("Adding event."));

            // If we have the interface and EventEntry is defined ...
            if (EventRequest->EventEntry)
            {
                pMiniport->AddEventToEventList(EventRequest->EventEntry);
            }
            else
            {
                return STATUS_UNSUCCESSFUL;
            }
            break;

        case PCEVENT_VERB_REMOVE:
            // We cannot remove the event but we can stop generating the
            // events. However, it also doesn't hurt to always generate them ...
            DPF(D_VERBOSE, ("Removing event."));
            break;

        default:
            return STATUS_INVALID_PARAMETER;
    }

    return STATUS_SUCCESS;
}

#pragma code_seg()
#endif  // SYSVAD_BTH_BYPASS



