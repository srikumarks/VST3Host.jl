#include "vst3_host.h"

#include <stdio.h>
#include <string.h>
#include <vector>
#include <memory>

// VST3 SDK includes
#include "public.sdk/source/vst/hosting/module.h"
#include "public.sdk/source/vst/hosting/plugprovider.h"
#include "public.sdk/source/vst/hosting/hostclasses.h"
#include "public.sdk/source/vst/hosting/processdata.h"
#include "public.sdk/source/vst/hosting/parameterchanges.h"
#include "public.sdk/source/vst/hosting/eventlist.h"
#include "public.sdk/source/vst/utility/stringconvert.h"
#include "pluginterfaces/vst/ivstaudioprocessor.h"
#include "pluginterfaces/vst/ivsteditcontroller.h"
#include "pluginterfaces/vst/ivstcomponent.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "pluginterfaces/vst/ivstevents.h"
#include "pluginterfaces/vst/vsttypes.h"

using namespace Steinberg;
using namespace Steinberg::Vst;

// Global host context
static FUnknown* gHostContext = nullptr;

/* Plugin structure */
struct VST3Plugin {
    std::shared_ptr<VST3::Hosting::Module> module;
    IPtr<IComponent> component;
    IPtr<IAudioProcessor> processor;
    IPtr<IEditController> controller;

    int32_t num_inputs;
    int32_t num_outputs;
    double sample_rate;
    int32_t max_block_size;

    std::vector<float*> input_buffers;
    std::vector<float*> output_buffers;

    HostProcessData processData;
    ParameterChanges inputParameterChanges;
    ParameterChanges outputParameterChanges;
    EventList inputEvents;
    EventList outputEvents;
};

extern "C" {

VST3Plugin* vst3_load_plugin(const char* bundle_path) {
    if (!bundle_path) {
        fprintf(stderr, "Error: null bundle path\n");
        return nullptr;
    }

    // Initialize host context if not already done
    if (!gHostContext) {
        gHostContext = new HostApplication();
    }

    printf("Loading VST3 plugin from: %s\n", bundle_path);

    // Create module
    std::string error;
    auto module = VST3::Hosting::Module::create(bundle_path, error);
    if (!module) {
        fprintf(stderr, "Error: Failed to load module: %s\n", error.c_str());
        return nullptr;
    }

    // Get factory
    auto factory = module->getFactory();

    // Find the first audio effect class
    VST3::Hosting::ClassInfo audioEffectClass;
    bool found = false;

    for (auto& classInfo : factory.classInfos()) {
        if (classInfo.category() == kVstAudioEffectClass) {
            audioEffectClass = classInfo;
            found = true;
            printf("Found audio effect: %s\n", classInfo.name().c_str());
            break;
        }
    }

    if (!found) {
        fprintf(stderr, "Error: No audio effect class found in plugin\n");
        return nullptr;
    }

    // Create plugin structure
    VST3Plugin* plugin = new VST3Plugin();
    plugin->module = module;
    plugin->num_inputs = 0;
    plugin->num_outputs = 0;
    plugin->sample_rate = 0;
    plugin->max_block_size = 0;

    // Create component
    plugin->component = factory.createInstance<IComponent>(audioEffectClass.ID());
    if (!plugin->component) {
        fprintf(stderr, "Error: Failed to create component\n");
        delete plugin;
        return nullptr;
    }

    // Initialize component
    if (plugin->component->initialize(gHostContext) != kResultOk) {
        fprintf(stderr, "Error: Failed to initialize component\n");
        delete plugin;
        return nullptr;
    }

    // Get processor interface
    plugin->processor = FUnknownPtr<IAudioProcessor>(plugin->component);
    if (!plugin->processor) {
        fprintf(stderr, "Error: Component does not support IAudioProcessor\n");
        plugin->component->terminate();
        delete plugin;
        return nullptr;
    }

    // Get controller
    TUID controllerCID;
    if (plugin->component->getControllerClassId(controllerCID) == kResultOk) {
        plugin->controller = factory.createInstance<IEditController>(VST3::UID(controllerCID));
        if (plugin->controller) {
            plugin->controller->initialize(gHostContext);

            // Connect component and controller
            FUnknownPtr<IConnectionPoint> componentCP(plugin->component);
            FUnknownPtr<IConnectionPoint> controllerCP(plugin->controller);

            if (componentCP && controllerCP) {
                componentCP->connect(controllerCP);
                controllerCP->connect(componentCP);
            }
        }
    }

    // Query bus information
    int32_t numInputBuses = plugin->component->getBusCount(kAudio, kInput);
    int32_t numOutputBuses = plugin->component->getBusCount(kAudio, kOutput);

    // Get channel counts from first bus
    if (numInputBuses > 0) {
        BusInfo busInfo;
        if (plugin->component->getBusInfo(kAudio, kInput, 0, busInfo) == kResultOk) {
            plugin->num_inputs = busInfo.channelCount;
        }
    }

    if (numOutputBuses > 0) {
        BusInfo busInfo;
        if (plugin->component->getBusInfo(kAudio, kOutput, 0, busInfo) == kResultOk) {
            plugin->num_outputs = busInfo.channelCount;
        }
    }

    printf("Plugin loaded successfully\n");
    printf("  Input channels: %d\n", plugin->num_inputs);
    printf("  Output channels: %d\n", plugin->num_outputs);

    return plugin;
}

int vst3_get_plugin_info(VST3Plugin* plugin, VST3PluginInfo* info) {
    if (!plugin || !info) return -1;

    // Get factory info
    auto factoryInfo = plugin->module->getFactory().info();

    // Get class info
    std::string pluginName = "Unknown";
    std::string vendor = factoryInfo.vendor();

    for (auto& classInfo : plugin->module->getFactory().classInfos()) {
        if (classInfo.category() == kVstAudioEffectClass) {
            pluginName = classInfo.name();
            if (!classInfo.vendor().empty()) {
                vendor = classInfo.vendor();
            }
            break;
        }
    }

    strncpy(info->name, pluginName.c_str(), sizeof(info->name) - 1);
    info->name[sizeof(info->name) - 1] = '\0';

    strncpy(info->vendor, vendor.c_str(), sizeof(info->vendor) - 1);
    info->vendor[sizeof(info->vendor) - 1] = '\0';

    info->num_inputs = plugin->num_inputs;
    info->num_outputs = plugin->num_outputs;
    info->num_parameters = plugin->controller ? plugin->controller->getParameterCount() : 0;
    info->sample_rate = plugin->sample_rate;

    return 0;
}

int vst3_get_parameter_count(VST3Plugin* plugin) {
    if (!plugin || !plugin->controller) return 0;
    return plugin->controller->getParameterCount();
}

int vst3_get_parameter_info(VST3Plugin* plugin, int32_t index, VST3ParameterInfo* info) {
    if (!plugin || !plugin->controller || !info) return -1;

    ParameterInfo paramInfo;
    if (plugin->controller->getParameterInfo(index, paramInfo) != kResultOk) {
        return -1;
    }

    info->id = paramInfo.id;

    // Convert UTF-16 strings to UTF-8
    namespace StringConvert = Steinberg::Vst::StringConvert;

    std::string title = StringConvert::convert(paramInfo.title);
    strncpy(info->title, title.c_str(), sizeof(info->title) - 1);
    info->title[sizeof(info->title) - 1] = '\0';

    std::string shortTitle = StringConvert::convert(paramInfo.shortTitle);
    strncpy(info->short_title, shortTitle.c_str(), sizeof(info->short_title) - 1);
    info->short_title[sizeof(info->short_title) - 1] = '\0';

    std::string units = StringConvert::convert(paramInfo.units);
    strncpy(info->units, units.c_str(), sizeof(info->units) - 1);
    info->units[sizeof(info->units) - 1] = '\0';

    info->default_value = paramInfo.defaultNormalizedValue;
    info->step_count = paramInfo.stepCount;

    // VST3 doesn't directly provide min/max, they're normalized 0-1
    info->min_value = 0.0;
    info->max_value = 1.0;

    return 0;
}

double vst3_get_parameter(VST3Plugin* plugin, int32_t param_id) {
    if (!plugin || !plugin->controller) return 0.0;
    return plugin->controller->getParamNormalized(param_id);
}

int vst3_set_parameter(VST3Plugin* plugin, int32_t param_id, double value) {
    if (!plugin || !plugin->controller) return -1;

    if (plugin->controller->setParamNormalized(param_id, value) != kResultOk) {
        return -1;
    }

    // Also notify component if connected
    if (plugin->component) {
        FUnknownPtr<IConnectionPoint> componentCP(plugin->component);
        if (componentCP) {
            // The parameter change will be communicated through the connection
        }
    }

    return 0;
}

int vst3_setup_processing(VST3Plugin* plugin, double sample_rate, int32_t max_samples_per_block) {
    if (!plugin || !plugin->processor) return -1;

    plugin->sample_rate = sample_rate;
    plugin->max_block_size = max_samples_per_block;

    // Activate buses
    if (plugin->num_inputs > 0) {
        plugin->component->activateBus(kAudio, kInput, 0, true);
    }

    if (plugin->num_outputs > 0) {
        plugin->component->activateBus(kAudio, kOutput, 0, true);
    }

    // Setup processing
    ProcessSetup setup;
    setup.processMode = kRealtime;
    setup.symbolicSampleSize = kSample32;
    setup.maxSamplesPerBlock = max_samples_per_block;
    setup.sampleRate = sample_rate;

    if (plugin->processor->setupProcessing(setup) != kResultOk) {
        fprintf(stderr, "Error: setupProcessing failed\n");
        return -1;
    }

    // Initialize process data
    plugin->processData.prepare(*plugin->component, max_samples_per_block, kSample32);

    return 0;
}

int vst3_set_active(VST3Plugin* plugin, int active) {
    if (!plugin || !plugin->component) return -1;

    if (active) {
        if (plugin->component->setActive(true) != kResultOk) {
            fprintf(stderr, "Error: Failed to activate component\n");
            return -1;
        }

        if (plugin->processor->setProcessing(true) != kResultOk) {
            fprintf(stderr, "Error: Failed to start processing\n");
            return -1;
        }
    } else {
        plugin->processor->setProcessing(false);
        plugin->component->setActive(false);
    }

    return 0;
}

int vst3_process(VST3Plugin* plugin, float** inputs, float** outputs,
                 int32_t num_samples, int32_t num_input_channels,
                 int32_t num_output_channels) {
    if (!plugin || !plugin->processor) return -1;

    // Setup process data
    plugin->processData.processContext = nullptr;
    plugin->processData.numSamples = num_samples;

    // Setup input/output parameter changes
    plugin->processData.inputParameterChanges = &plugin->inputParameterChanges;
    plugin->processData.outputParameterChanges = &plugin->outputParameterChanges;

    // Setup input/output events
    plugin->processData.inputEvents = &plugin->inputEvents;
    plugin->processData.outputEvents = &plugin->outputEvents;

    // Setup input buffers
    if (num_input_channels > 0 && plugin->processData.numInputs > 0) {
        for (int32_t ch = 0; ch < num_input_channels && ch < plugin->num_inputs; ch++) {
            plugin->processData.inputs[0].channelBuffers32[ch] = inputs[ch];
        }
        plugin->processData.inputs[0].numChannels = num_input_channels;
    }

    // Setup output buffers
    if (num_output_channels > 0 && plugin->processData.numOutputs > 0) {
        for (int32_t ch = 0; ch < num_output_channels && ch < plugin->num_outputs; ch++) {
            plugin->processData.outputs[0].channelBuffers32[ch] = outputs[ch];
        }
        plugin->processData.outputs[0].numChannels = num_output_channels;
    }

    // Process
    if (plugin->processor->process(plugin->processData) != kResultOk) {
        return -1;
    }

    // Clear input events after processing
    plugin->inputEvents.clear();

    return 0;
}

int vst3_send_note_on(VST3Plugin* plugin, int32_t channel, int32_t note, int32_t velocity, int32_t sample_offset) {
    if (!plugin) return -1;

    Event event = {};
    event.busIndex = 0;
    event.sampleOffset = sample_offset;
    event.ppqPosition = 0;
    event.flags = Event::kIsLive;
    event.type = Event::kNoteOnEvent;
    event.noteOn.channel = channel;
    event.noteOn.pitch = note;
    event.noteOn.velocity = velocity / 127.0f;  // Normalize to 0.0-1.0
    event.noteOn.length = 0;
    event.noteOn.tuning = 0.0f;
    event.noteOn.noteId = -1;

    plugin->inputEvents.addEvent(event);
    return 0;
}

int vst3_send_note_off(VST3Plugin* plugin, int32_t channel, int32_t note, int32_t sample_offset) {
    if (!plugin) return -1;

    Event event = {};
    event.busIndex = 0;
    event.sampleOffset = sample_offset;
    event.ppqPosition = 0;
    event.flags = Event::kIsLive;
    event.type = Event::kNoteOffEvent;
    event.noteOff.channel = channel;
    event.noteOff.pitch = note;
    event.noteOff.velocity = 0.0f;
    event.noteOff.tuning = 0.0f;
    event.noteOff.noteId = -1;

    plugin->inputEvents.addEvent(event);
    return 0;
}

int vst3_send_midi_cc(VST3Plugin* plugin, int32_t channel, int32_t cc, int32_t value, int32_t sample_offset) {
    if (!plugin) return -1;

    // VST3 uses LegacyMIDICCOutEvent for MIDI CC
    Event event = {};
    event.busIndex = 0;
    event.sampleOffset = sample_offset;
    event.ppqPosition = 0;
    event.flags = Event::kIsLive;
    event.type = Event::kLegacyMIDICCOutEvent;
    event.midiCCOut.channel = channel;
    event.midiCCOut.controlNumber = cc;
    event.midiCCOut.value = value;
    event.midiCCOut.value2 = 0;

    plugin->inputEvents.addEvent(event);
    return 0;
}

int vst3_send_program_change(VST3Plugin* plugin, int32_t channel, int32_t program, int32_t sample_offset) {
    if (!plugin) return -1;

    // MIDI Program Change is sent as two CC messages in VST3:
    // Bank Select MSB (CC 0) = 0
    // Program Change is typically done via parameter change or the preset system
    // For standard MIDI compatibility, we'll send it as a legacy MIDI event

    // Some plugins support this, but VST3 prefers using the preset/program interface
    // We'll send both a CC 0 (bank select) set to 0 and then handle program via parameters

    Event event = {};
    event.busIndex = 0;
    event.sampleOffset = sample_offset;
    event.ppqPosition = 0;
    event.flags = Event::kIsLive;
    event.type = Event::kLegacyMIDICCOutEvent;
    event.midiCCOut.channel = channel;
    event.midiCCOut.controlNumber = 0;  // Bank Select MSB
    event.midiCCOut.value = 0;
    event.midiCCOut.value2 = 0;

    plugin->inputEvents.addEvent(event);

    // Add program change as CC 32 (unofficial but some plugins recognize it)
    Event pcEvent = {};
    pcEvent.busIndex = 0;
    pcEvent.sampleOffset = sample_offset;
    pcEvent.ppqPosition = 0;
    pcEvent.flags = Event::kIsLive;
    pcEvent.type = Event::kLegacyMIDICCOutEvent;
    pcEvent.midiCCOut.channel = channel;
    pcEvent.midiCCOut.controlNumber = 32;  // Program change (non-standard)
    pcEvent.midiCCOut.value = program;
    pcEvent.midiCCOut.value2 = 0;

    plugin->inputEvents.addEvent(pcEvent);

    return 0;
}

void vst3_unload_plugin(VST3Plugin* plugin) {
    if (!plugin) return;

    // Disconnect connection points
    if (plugin->component && plugin->controller) {
        FUnknownPtr<IConnectionPoint> componentCP(plugin->component);
        FUnknownPtr<IConnectionPoint> controllerCP(plugin->controller);

        if (componentCP && controllerCP) {
            componentCP->disconnect(controllerCP);
            controllerCP->disconnect(componentCP);
        }
    }

    // Terminate interfaces
    if (plugin->controller) {
        plugin->controller->terminate();
        plugin->controller = nullptr;
    }

    if (plugin->component) {
        plugin->component->terminate();
        plugin->component = nullptr;
    }

    plugin->processor = nullptr;
    plugin->module = nullptr;

    delete plugin;
}

} // extern "C"
