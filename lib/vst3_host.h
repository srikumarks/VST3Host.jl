#ifndef VST3_HOST_H
#define VST3_HOST_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle to VST3 plugin */
typedef struct VST3Plugin VST3Plugin;

/* Parameter information */
typedef struct {
    int32_t id;
    char title[128];
    char short_title[32];
    char units[32];
    double default_value;
    double min_value;
    double max_value;
    int32_t step_count;
} VST3ParameterInfo;

/* Plugin information */
typedef struct {
    char name[128];
    char vendor[128];
    int32_t num_inputs;
    int32_t num_outputs;
    int32_t num_parameters;
    double sample_rate;
} VST3PluginInfo;

/* Load a VST3 plugin from bundle path */
VST3Plugin* vst3_load_plugin(const char* bundle_path);

/* Get plugin information */
int vst3_get_plugin_info(VST3Plugin* plugin, VST3PluginInfo* info);

/* Get number of parameters */
int vst3_get_parameter_count(VST3Plugin* plugin);

/* Get parameter information by index */
int vst3_get_parameter_info(VST3Plugin* plugin, int32_t index, VST3ParameterInfo* info);

/* Get parameter value (normalized 0.0 - 1.0) */
double vst3_get_parameter(VST3Plugin* plugin, int32_t param_id);

/* Set parameter value (normalized 0.0 - 1.0) */
int vst3_set_parameter(VST3Plugin* plugin, int32_t param_id, double value);

/* Initialize plugin for processing */
int vst3_setup_processing(VST3Plugin* plugin, double sample_rate, int32_t max_samples_per_block);

/* Activate/deactivate processing */
int vst3_set_active(VST3Plugin* plugin, int active);

/* Process audio block */
int vst3_process(VST3Plugin* plugin, float** inputs, float** outputs,
                 int32_t num_samples, int32_t num_input_channels,
                 int32_t num_output_channels);

/* MIDI event functions */
int vst3_send_note_on(VST3Plugin* plugin, int32_t channel, int32_t note, int32_t velocity, int32_t sample_offset);
int vst3_send_note_off(VST3Plugin* plugin, int32_t channel, int32_t note, int32_t sample_offset);
int vst3_send_midi_cc(VST3Plugin* plugin, int32_t channel, int32_t cc, int32_t value, int32_t sample_offset);
int vst3_send_program_change(VST3Plugin* plugin, int32_t channel, int32_t program, int32_t sample_offset);

/* Unload plugin */
void vst3_unload_plugin(VST3Plugin* plugin);

#ifdef __cplusplus
}
#endif

#endif /* VST3_HOST_H */
