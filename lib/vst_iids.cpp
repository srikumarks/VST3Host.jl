// VST3 Interface IDs definitions
// This file provides the missing IID definitions for VST3 interfaces

#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstmessage.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstunits.h"
#include "pluginterfaces/vst/ivsttestplugprovider.h"
#include "pluginterfaces/vst/ivstpluginterfacesupport.h"
#include "pluginterfaces/vst/ivstattributes.h"
#include "pluginterfaces/vst/ivstprocesscontext.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/ivstmidicontrollers.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"

namespace Steinberg {
namespace Vst {

// Core interfaces
DEF_CLASS_IID (IAudioProcessor)
DEF_CLASS_IID (IComponent)
DEF_CLASS_IID (IEditController)
DEF_CLASS_IID (IEditController2)
DEF_CLASS_IID (IConnectionPoint)

// Event and MIDI interfaces
DEF_CLASS_IID (IEventList)
DEF_CLASS_IID (IMidiMapping)

// Parameter interfaces
DEF_CLASS_IID (IParameterChanges)
DEF_CLASS_IID (IParamValueQueue)

// Unit interfaces
DEF_CLASS_IID (IUnitInfo)
DEF_CLASS_IID (IUnitData)
DEF_CLASS_IID (IProgramListData)

// Message interfaces
DEF_CLASS_IID (IMessage)
DEF_CLASS_IID (IAttributeList)

// Host interfaces
DEF_CLASS_IID (IHostApplication)

// Plugin provider interfaces
DEF_CLASS_IID (ITestPlugProvider)
DEF_CLASS_IID (ITestPlugProvider2)

// Support interfaces
DEF_CLASS_IID (IPlugInterfaceSupport)

// Note: ThreadChecker is now provided by threadchecker_mac.mm

} // namespace Vst

// Base StringConvert implementation
namespace StringConvert {

std::string convert(const std::u16string& str) {
    std::string result;
    for (char16_t c : str) {
        if (c < 128) {
            result += static_cast<char>(c);
        } else {
            result += '?';  // Simple fallback for non-ASCII
        }
    }
    return result;
}

std::u16string convert(const std::string& str) {
    std::u16string result;
    for (char c : str) {
        result += static_cast<char16_t>(static_cast<unsigned char>(c));
    }
    return result;
}

std::string convert(const char* str, uint32_t max) {
    std::string result;
    for (uint32_t i = 0; i < max && str[i] != '\0'; ++i) {
        result += str[i];
    }
    return result;
}

} // namespace StringConvert

} // namespace Steinberg
