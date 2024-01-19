/*++

Copyright (c) Microsoft Corporation All Rights Reserved

Module Name:

    micarraywavtable.h

Abstract:

    Declaration of wave miniport tables for the mic array.

--*/

#ifndef _SYSVAD_MICARRAYWAVTABLE_H_
#define _SYSVAD_MICARRAYWAVTABLE_H_

//
// Mic array range.
//
#define MICARRAY_RAW_CHANNELS                   2       // Channels for raw mode
#define MICARRAY_PROCESSED_CHANNELS             1       // Channels for default mode
#define MICARRAY_DEVICE_MAX_CHANNELS            2       // Max channels overall
#define MICARRAY_16_BITS_PER_SAMPLE_PCM         16      // 16 Bits Per Sample
#define MICARRAY_32_BITS_PER_SAMPLE_PCM         32      // 32 Bits Per Sample
#define MICARRAY_RAW_SAMPLE_RATE                48000   // Raw sample rate
#define MICARRAY_PROCESSED_MIN_SAMPLE_RATE      8000    // Min Sample Rate
#define MICARRAY_PROCESSED_MAX_SAMPLE_RATE      48000   // Max Sample Rate

//
// Max # of pin instances.
//
#define MICARRAY_MAX_INPUT_STREAMS              4

//=============================================================================
static 
KSDATAFORMAT_WAVEFORMATEXTENSIBLE MicArrayPinSupportedDeviceFormats[] =
{
    // 0 - Note the ENDPOINT_MINIPAIR structures for the mic arrays use this first element as the proposed DEFAULT format
    // 48 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,
                48000,
                96000,
                2,
                16,
                sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)
            },
            16,
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
    // 1
    // 8 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,
                8000,
                16000,
                2,
                16,
                sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)
            },
            16,
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
    // 2
    // 11.025 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,
                11025,
                22050,
                2,
                16,
                sizeof(WAVEFORMATEXTENSIBLE)-sizeof(WAVEFORMATEX)
            },
            16,
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
    // 3 - Note the ENDPOINT_MINIPAIR structures for the mic arrays use this element as the proposed SPEECH format
    // 16 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,      // One channel
                16000,  // 16KHz
                32000,  // average bytes per second
                2,      // 2 bytes per frame
                16,     // 16 bits per sample container
                sizeof(WAVEFORMATEXTENSIBLE)-sizeof(WAVEFORMATEX)
            },
            16,         // valid bits per sample
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
    // 4
    // 22.05 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,
                22050,
                44100,
                2,
                16,
                sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)
            },
            16,
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
    // 5 - Note the ENDPOINT_MINIPAIR structures for the mic arrays use this element as the proposed COMMUNICATIONS format
    // 24 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,
                24000,
                48000,
                2,
                16,
                sizeof(WAVEFORMATEXTENSIBLE)-sizeof(WAVEFORMATEX)
            },
            16,
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
    // 6
    // 32 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,
                32000,
                64000,
                2,
                16,
                sizeof(WAVEFORMATEXTENSIBLE)-sizeof(WAVEFORMATEX)
            },
            16,
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
    // 7
    // 44.1 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,
                44100,
                88200,
                2,
                16,
                sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)
            },
            16,
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
    // 8 - Note the ENDPOINT_MINIPAIR structures for the mic arrays use this last element as the proposed RAW format
    // 48 KHz 32-bit 2 channels
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                2,
                48000,
                384000,
                8,
                32,
                sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX)
            },
            32,
            0,                                      // No channel configuration for unprocessed mic array
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
};

//
// Supported modes (only on streaming pins).
//
static
MODE_AND_DEFAULT_FORMAT MicArrayPinSupportedDeviceModes[] =
{
    {
        STATIC_AUDIO_SIGNALPROCESSINGMODE_RAW,
        &MicArrayPinSupportedDeviceFormats[SIZEOF_ARRAY(MicArrayPinSupportedDeviceFormats)-1].DataFormat
    },
    {
        STATIC_AUDIO_SIGNALPROCESSINGMODE_DEFAULT,
        &MicArrayPinSupportedDeviceFormats[0].DataFormat
    },
    {
        STATIC_AUDIO_SIGNALPROCESSINGMODE_SPEECH,
        &MicArrayPinSupportedDeviceFormats[3].DataFormat
    },
    {
        STATIC_AUDIO_SIGNALPROCESSINGMODE_COMMUNICATIONS,
        &MicArrayPinSupportedDeviceFormats[5].DataFormat
    }
};

//=============================================================================
static
KSDATAFORMAT_WAVEFORMATEXTENSIBLE KeywordPinSupportedDeviceFormats[] =
{
    // 0 - Note the ENDPOINT_MINIPAIR structures for the mic arrays use this element as the proposed SPEECH format for KWD pin
    // 16 KHz 16-bit mono
    {
        {
            sizeof(KSDATAFORMAT_WAVEFORMATEXTENSIBLE),
            0,
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        {
            {
                WAVE_FORMAT_EXTENSIBLE,
                1,      // One channel
                16000,  // 16KHz
                32000,  // average bytes per second
                2,      // 2 bytes per frame
                16,     // 16 bits per sample container
                sizeof(WAVEFORMATEXTENSIBLE)-sizeof(WAVEFORMATEX)
            },
            16,         // valid bits per sample
            KSAUDIO_SPEAKER_MONO,
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM)
        }
    },
};

static
MODE_AND_DEFAULT_FORMAT KeywordPinSupportedDeviceModes[] =
{
    {
        STATIC_AUDIO_SIGNALPROCESSINGMODE_SPEECH,
        &KeywordPinSupportedDeviceFormats[SIZEOF_ARRAY(KeywordPinSupportedDeviceFormats) - 1].DataFormat
    },
};

//
// The entries here must follow the same order as the filter's pin
// descriptor array.
//
static 
PIN_DEVICE_FORMATS_AND_MODES MicArrayPinDeviceFormatsAndModes[] = 
{
    {
        BridgePin,
        NULL,
        0,
        NULL,
        0
    },
    {
        SystemCapturePin,
        MicArrayPinSupportedDeviceFormats,
        SIZEOF_ARRAY(MicArrayPinSupportedDeviceFormats),
        MicArrayPinSupportedDeviceModes,
        SIZEOF_ARRAY(MicArrayPinSupportedDeviceModes)
    },
    {
        KeywordCapturePin,
        KeywordPinSupportedDeviceFormats,
        SIZEOF_ARRAY(KeywordPinSupportedDeviceFormats),
        KeywordPinSupportedDeviceModes,
        SIZEOF_ARRAY(KeywordPinSupportedDeviceModes)
    }
};

//=============================================================================
// Data ranges
//
// See CMiniportWaveRT::DataRangeIntersection.
//
// Both mono and two-channel formats are supported for the mic arrays. The
// design of this sample driver's data range intersection handler requires a
// separate data for each supported channel count.
//
static
KSDATARANGE_AUDIO MicArrayPinDataRangesRawStream[] =
{
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_RAW_CHANNELS,           
        MICARRAY_32_BITS_PER_SAMPLE_PCM,    
        MICARRAY_32_BITS_PER_SAMPLE_PCM,    
        MICARRAY_RAW_SAMPLE_RATE,            
        MICARRAY_RAW_SAMPLE_RATE             
    },
};

static
KSDATARANGE_AUDIO MicArrayPinDataRangesProcessedStream[] =
{
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_PROCESSED_CHANNELS,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_PROCESSED_MIN_SAMPLE_RATE,
        MICARRAY_PROCESSED_MIN_SAMPLE_RATE
    },
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_PROCESSED_CHANNELS,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        11025,
        11025
    },
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_PROCESSED_CHANNELS,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        16000,
        16000
    },
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_PROCESSED_CHANNELS,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        22050,
        22050
    },
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_PROCESSED_CHANNELS,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        24000,
        24000
    },
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_PROCESSED_CHANNELS,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        32000,
        32000
    },
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_PROCESSED_CHANNELS,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        44100,
        44100
    },
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        MICARRAY_PROCESSED_CHANNELS,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_16_BITS_PER_SAMPLE_PCM,
        MICARRAY_PROCESSED_MAX_SAMPLE_RATE,
        MICARRAY_PROCESSED_MAX_SAMPLE_RATE
    },
};

// if MicArrayPinDataRangesProcessedStream is changed, we MUST update MicArrayPinDataRangePointersStream too!
C_ASSERT(SIZEOF_ARRAY(MicArrayPinDataRangesProcessedStream) == 8);

static
PKSDATARANGE MicArrayPinDataRangePointersStream[] =
{
    // All supported device formats should be listed in the DataRange.
    PKSDATARANGE(&MicArrayPinDataRangesProcessedStream[0]),
    PKSDATARANGE(&PinDataRangeAttributeList),
    PKSDATARANGE(&MicArrayPinDataRangesProcessedStream[1]),
    PKSDATARANGE(&PinDataRangeAttributeList),
    PKSDATARANGE(&MicArrayPinDataRangesProcessedStream[2]),
    PKSDATARANGE(&PinDataRangeAttributeList),
    PKSDATARANGE(&MicArrayPinDataRangesProcessedStream[3]),
    PKSDATARANGE(&PinDataRangeAttributeList),
    PKSDATARANGE(&MicArrayPinDataRangesProcessedStream[4]),
    PKSDATARANGE(&PinDataRangeAttributeList),
    PKSDATARANGE(&MicArrayPinDataRangesProcessedStream[5]),
    PKSDATARANGE(&PinDataRangeAttributeList),
    PKSDATARANGE(&MicArrayPinDataRangesProcessedStream[6]),
    PKSDATARANGE(&PinDataRangeAttributeList),
    PKSDATARANGE(&MicArrayPinDataRangesProcessedStream[7]),
    PKSDATARANGE(&PinDataRangeAttributeList),
    PKSDATARANGE(&MicArrayPinDataRangesRawStream[0]),
    PKSDATARANGE(&PinDataRangeAttributeList),
};

//=============================================================================
static
KSDATARANGE MicArrayPinDataRangesBridge[] =
{
    {
        sizeof(KSDATARANGE),
        0,
        0,
        0,
        STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
        STATICGUIDOF(KSDATAFORMAT_SUBTYPE_ANALOG),
        STATICGUIDOF(KSDATAFORMAT_SPECIFIER_NONE)
    }
};

static
PKSDATARANGE MicArrayPinDataRangePointersBridge[] =
{
    &MicArrayPinDataRangesBridge[0]
};

static
KSDATARANGE_AUDIO KeywordPinDataRangesStream[] =
{
    {
        {
            sizeof(KSDATARANGE_AUDIO),
            KSDATARANGE_ATTRIBUTES,         // An attributes list follows this data range
            0,
            0,
            STATICGUIDOF(KSDATAFORMAT_TYPE_AUDIO),
            STATICGUIDOF(KSDATAFORMAT_SUBTYPE_PCM),
            STATICGUIDOF(KSDATAFORMAT_SPECIFIER_WAVEFORMATEX)
        },
        1,      // max channels
        16,     // min bits per sample
        16,     // max bits per sample
        16000,  // min sample rate
        16000   // max sample rate
    },
};

static
PKSDATARANGE KeywordPinDataRangePointersStream[] =
{
    PKSDATARANGE(&KeywordPinDataRangesStream[0]),
    PKSDATARANGE(&PinDataRangeAttributeList),
};

//=============================================================================
static
PCPIN_DESCRIPTOR MicArrayWaveMiniportPins[] =
{
    // Wave In Bridge Pin (Capture - From Topology) KSPIN_WAVE_BRIDGE
    {
        0,
        0,
        0,
        NULL,
        {
            0,
            NULL,
            0,
            NULL,
            SIZEOF_ARRAY(MicArrayPinDataRangePointersBridge),
            MicArrayPinDataRangePointersBridge,
            KSPIN_DATAFLOW_IN,
            KSPIN_COMMUNICATION_NONE,
            &KSCATEGORY_AUDIO,
            NULL,
            0
        }
    },
    // Wave In Streaming Pin (Capture) KSPIN_WAVE_HOST
    {
        MICARRAY_MAX_INPUT_STREAMS,
        MICARRAY_MAX_INPUT_STREAMS,
        0,
        NULL,
        {
            0,
            NULL,
            0,
            NULL,
            SIZEOF_ARRAY(MicArrayPinDataRangePointersStream),
            MicArrayPinDataRangePointersStream,
            KSPIN_DATAFLOW_OUT,
            KSPIN_COMMUNICATION_SINK,
            &KSCATEGORY_AUDIO,
            &KSAUDFNAME_RECORDING_CONTROL,  
            0
        }
    },
    // Keyword Detector Streaming Pin (Capture) KSPIN_WAVEIN_KEYWORD
    {
        1,
        1,
        0,
        NULL,
        {
            0,
            NULL,
            0,
            NULL,
            SIZEOF_ARRAY(KeywordPinDataRangePointersStream),
            KeywordPinDataRangePointersStream,
            KSPIN_DATAFLOW_OUT,
            KSPIN_COMMUNICATION_SINK,
            &KSNODETYPE_AUDIO_KEYWORDDETECTOR,
            NULL,
            0
        }
    }
};

//=============================================================================
static
PCNODE_DESCRIPTOR MicArrayWaveMiniportNodes[] =
{
    // KSNODE_WAVE_ADC
    {
        0,                      // Flags
        NULL,                   // AutomationTable
        &KSNODETYPE_ADC,        // Type
        NULL                    // Name
    }
};

//=============================================================================
static
PCCONNECTION_DESCRIPTOR MicArrayWaveMiniportConnections[] =
{
    { PCFILTER_NODE,        KSPIN_WAVE_BRIDGE,      KSNODE_WAVE_ADC,     1 },    
    { KSNODE_WAVE_ADC,      0,                      PCFILTER_NODE,       KSPIN_WAVEIN_HOST },
    { KSNODE_WAVE_ADC,      0,                      PCFILTER_NODE,       KSPIN_WAVEIN_KEYWORD },
};

//=============================================================================
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Get_SoundDetectorSupportedPatterns);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Set_SoundDetectorPatterns);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Get_SoundDetectorArmed);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Set_SoundDetectorArmed);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Get_SoundDetectorMatchResult);

DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Get_SoundDetectorSupportedPatterns2);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Set_SoundDetectorPatterns2);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Get_SoundDetectorArmed2);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Set_SoundDetectorArmed2);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Set_SoundDetectorReset2);
DECLARE_CLASSPROPERTYHANDLER(CMiniportWaveRT, Get_SoundDetectorStreamingSupport2);


static
SYSVADPROPERTY_ITEM PropertiesMicArrayWaveFilter[] =
{
    {
        {
            &KSPROPSETID_General,
            KSPROPERTY_GENERAL_COMPONENTID,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_BASICSUPPORT,
            PropertyHandler_WaveFilter,
        },
        0,
        0,
        NULL,
        NULL,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_Pin,
            KSPROPERTY_PIN_PROPOSEDATAFORMAT,
            KSPROPERTY_TYPE_SET | KSPROPERTY_TYPE_BASICSUPPORT,
            PropertyHandler_WaveFilter,
        },
        0,
        0,
        NULL,
        NULL,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_Pin,
            KSPROPERTY_PIN_PROPOSEDATAFORMAT2,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_BASICSUPPORT,
            PropertyHandler_WaveFilter,
        },
        0,
        0,
        NULL,
        NULL,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_AudioEffectsDiscovery,
            KSPROPERTY_AUDIOEFFECTSDISCOVERY_EFFECTSLIST,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_BASICSUPPORT,
            PropertyHandler_WaveFilter
        },
        0,
        0,
        NULL,
        NULL,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector,
            KSPROPERTY_SOUNDDETECTOR_SUPPORTEDPATTERNS,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        0,
        sizeof(CONTOSO_SUPPORTEDPATTERNSVALUE),
        CMiniportWaveRT_Get_SoundDetectorSupportedPatterns,
        NULL,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector,
            KSPROPERTY_SOUNDDETECTOR_PATTERNS,
            KSPROPERTY_TYPE_SET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        0,
        (sizeof(KSMULTIPLE_ITEM) + sizeof(CONTOSO_KEYWORDCONFIGURATION)),
        NULL,
        CMiniportWaveRT_Set_SoundDetectorPatterns,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector,
            KSPROPERTY_SOUNDDETECTOR_ARMED,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_SET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        0,
        sizeof(BOOL),
        CMiniportWaveRT_Get_SoundDetectorArmed,
        CMiniportWaveRT_Set_SoundDetectorArmed,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector,
            KSPROPERTY_SOUNDDETECTOR_MATCHRESULT,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        0,
        sizeof(CONTOSO_KEYWORDDETECTIONRESULT),
        CMiniportWaveRT_Get_SoundDetectorMatchResult,
        NULL,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector2,
            KSPROPERTY_SOUNDDETECTOR_SUPPORTEDPATTERNS,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        sizeof(KSSOUNDDETECTORPROPERTY) - sizeof(KSPROPERTY),
        sizeof(CONTOSO_SUPPORTEDPATTERNSVALUE),
        CMiniportWaveRT_Get_SoundDetectorSupportedPatterns2,
        NULL,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector2,
            KSPROPERTY_SOUNDDETECTOR_PATTERNS,
            KSPROPERTY_TYPE_SET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        sizeof(KSSOUNDDETECTORPROPERTY) - sizeof(KSPROPERTY),
        (sizeof(KSMULTIPLE_ITEM) + sizeof(CONTOSO_KEYWORDCONFIGURATION)),
        NULL,
        CMiniportWaveRT_Set_SoundDetectorPatterns2,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector2,
            KSPROPERTY_SOUNDDETECTOR_ARMED,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_SET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        sizeof(KSSOUNDDETECTORPROPERTY) - sizeof(KSPROPERTY),
        sizeof(BOOL),
        CMiniportWaveRT_Get_SoundDetectorArmed2,
        CMiniportWaveRT_Set_SoundDetectorArmed2,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector2,
            KSPROPERTY_SOUNDDETECTOR_RESET,
            KSPROPERTY_TYPE_SET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        sizeof(KSSOUNDDETECTORPROPERTY) - sizeof(KSPROPERTY),
        sizeof(BOOL),
        NULL,
        CMiniportWaveRT_Set_SoundDetectorReset2,
        NULL,
        NULL,
        0
    },
    {
        {
            &KSPROPSETID_SoundDetector2,
            KSPROPERTY_SOUNDDETECTOR_STREAMINGSUPPORT,
            KSPROPERTY_TYPE_GET | KSPROPERTY_TYPE_BASICSUPPORT,
            SysvadPropertyDispatch,
        },
        sizeof(KSSOUNDDETECTORPROPERTY) - sizeof(KSPROPERTY),
        sizeof(BOOL),
        CMiniportWaveRT_Get_SoundDetectorStreamingSupport2,
        NULL,
        NULL,
        NULL,
        0
    },
};

NTSTATUS CMiniportWaveRT_EventHandler_SoundDetectorMatchDetected(
    _In_  PPCEVENT_REQUEST EventRequest
    );

static
PCEVENT_ITEM EventsMicArrayWaveFilter[] =
{
    {
        &KSEVENTSETID_SoundDetector,
        KSEVENT_SOUNDDETECTOR_MATCHDETECTED,
        KSEVENT_TYPE_ENABLE | KSEVENT_TYPE_BASICSUPPORT,
        CMiniportWaveRT_EventHandler_SoundDetectorMatchDetected,
    }
};

DEFINE_PCAUTOMATION_TABLE_PROP_EVENT(AutomationMicArrayWaveFilter, PropertiesMicArrayWaveFilter, EventsMicArrayWaveFilter);

//=============================================================================
static
PCFILTER_DESCRIPTOR MicArrayWaveMiniportFilterDescriptor =
{
    0,                                              // Version
    &AutomationMicArrayWaveFilter,                  // AutomationTable
    sizeof(PCPIN_DESCRIPTOR),                       // PinSize
    SIZEOF_ARRAY(MicArrayWaveMiniportPins),         // PinCount
    MicArrayWaveMiniportPins,                       // Pins
    sizeof(PCNODE_DESCRIPTOR),                      // NodeSize
    SIZEOF_ARRAY(MicArrayWaveMiniportNodes),        // NodeCount
    MicArrayWaveMiniportNodes,                      // Nodes
    SIZEOF_ARRAY(MicArrayWaveMiniportConnections),  // ConnectionCount
    MicArrayWaveMiniportConnections,                // Connections
    0,                                              // CategoryCount
    NULL                                            // Categories  - use defaults (audio, render, capture)
};

#endif // _SYSVAD_MICARRAYWAVTABLE_H_

