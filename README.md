**DISCLOSURE**: This wrapper is largely generated through interacting with
Claude Code. The interaction history files are also included in the project for
reference.

# VST3Host.jl

A Julia package for hosting VST3 audio plugins with support for block-based
processing, parameter automation, and MIDI events.

## Features

- ✅ Load and initialize VST3 plugins
- ✅ Block-based audio processing (any block size from 1 sample up)
- ✅ Complete parameter discovery with metadata
- ✅ Parameter automation during processing
- ✅ MIDI note events (Note On/Off)
- ✅ MIDI CC (Control Change) events
- ✅ Real-time safe processing
- ✅ Automatic memory management
- ✅ WAV file I/O integration

## Installation

### Prerequisites

1. Julia 1.6 or later
2. VST3 SDK (already included in parent directory)
3. C++ compiler (for building the shared library)

### Build the shared library

```bash
cd jl/lib
make
```

This creates `libvst3host.dylib` (macOS) / `libvst3host.so` (Linux).

### Install Julia dependencies

```julia
using Pkg
Pkg.add("WAV")
```

## Quick Start

```julia
using VST3Host
using SampledSignals

# Load a plugin
plugin = VST3Plugin("/path/to/plugin.vst3", 44100.0, 512)

# Display plugin info (automatic in REPL, or use display(plugin))
plugin  # Shows full info with all parameters

# Set a parameter (normalized 0-1)
setparameter!(plugin, 0, 0.5)

# Process audio (2 channels × 512 samples) with SampleBuf
sr = 44100.0
input = SampleBuf(randn(Float32, 2, 512), sr)
output = process(plugin, input)

# Send MIDI
noteon(plugin, 0, 60, 100)   # Channel 0, Note 60 (C4), Velocity 100
output = process(plugin, input)
noteoff(plugin, 0, 60)

# Cleanup (automatic via finalizer, but can be explicit)
close(plugin)
```

## API Reference

### Plugin Management

#### `VST3Plugin(path, sample_rate, block_size)`
Load and initialize a VST3 plugin.

**Arguments:**
- `path::String`: Path to .vst3 bundle
- `sample_rate::Float64`: Sample rate (e.g., 44100.0)
- `block_size::Int`: Maximum block size for processing

**Returns:** `VST3Plugin` instance

**Example:**
```julia
plugin = VST3Plugin("/Library/Audio/Plug-Ins/VST3/Reverb.vst3", 48000.0, 256)
```

#### `activate!(plugin)`
Activate the plugin for audio processing. Called automatically by `process`.

#### `deactivate!(plugin)`
Deactivate the plugin. Called automatically when closing.

#### `close(plugin)`
Cleanup and unload the plugin. Called automatically by garbage collector.

### Plugin Information

#### `info(plugin) -> PluginInfo`
Get basic plugin information.

**Returns:** `PluginInfo` with fields:
- `name::String`
- `vendor::String`
- `num_inputs::Int`
- `num_outputs::Int`
- `num_parameters::Int`
- `sample_rate::Float64`

#### Display Plugin Info
Simply type `plugin` in the REPL or use `display(plugin)` to see:
- Plugin name, vendor, and configuration
- All parameters with current values and defaults
- Automatic formatting for terminal or Jupyter notebooks

### Parameters

#### `parameters(plugin) -> Vector{ParameterInfo}`
Get information about all parameters.

**Returns:** Vector of `ParameterInfo` with fields:
- `id::Int`: Parameter ID
- `title::String`: Full parameter name
- `short_title::String`: Abbreviated name
- `units::String`: Units (e.g., "dB", "Hz", "%")
- `default_value::Float64`: Default (normalized 0-1)
- `min_value::Float64`: Always 0.0 for VST3
- `max_value::Float64`: Always 1.0 for VST3
- `step_count::Int`: Number of steps (0 = continuous)

#### `parameterinfo(plugin, index) -> ParameterInfo`
Get information about a specific parameter by index (0-based).

#### `getparameter(plugin, param_id) -> Float64`
Get current parameter value (normalized 0-1).

#### `parameter(plugin, param_id) -> Float64`
Alias for `getparameter`.

#### `setparameter!(plugin, param_id, value)`
Set parameter value (normalized 0-1).

**Arguments:**
- `param_id::Int`: Parameter ID
- `value::Float64`: New value (must be 0.0-1.0)

#### `formatparameter(param::ParameterInfo, value) -> String`
Format a parameter value as human-readable string.

#### `isdiscrete(param::ParameterInfo) -> Bool`
Check if parameter is discrete (vs. continuous).

### Audio Processing

#### `process(plugin, input) -> SampleBuf{Float32}`
Process a block of audio and return output.

**Arguments:**
- `input::SampleBuf{Float32}`: Input audio buffer with sample rate metadata

**Returns:** Output audio as SampleBuf with shape (num_outputs × num_samples)

**Notes:**
- Block size must be ≤ `plugin.block_size`
- Automatically activates plugin if needed
- Input channels should match plugin's `num_inputs`
- Input and output preserve sample rate information

**Example:**
```julia
# Process 128 samples at 44100 Hz
sr = 44100.0
input = SampleBuf(randn(Float32, 2, 128), sr)
output = process(plugin, input)

# For backward compatibility, Matrix{Float32} still works:
input_matrix = randn(Float32, 2, 128)
output = process(plugin, input_matrix)  # Returns Matrix{Float32}
```

#### `process!(plugin, input, output)`
Process audio in-place (modifies `output`).

**Arguments:**
- `input::SampleBuf{Float32}`: Input audio buffer
- `output::SampleBuf{Float32}`: Output buffer (pre-allocated, will be modified)

**Note:** Also accepts `Matrix{Float32}` for backward compatibility

### MIDI Events

#### `noteon(plugin, channel, note, velocity, offset=0)`
Send MIDI Note On event.

**Arguments:**
- `channel::Int`: MIDI channel (0-15)
- `note::Int`: Note number (0-127, where 60 = C4)
- `velocity::Int`: Note velocity (0-127)
- `offset::Int`: Sample position in next block (default: 0)

**Example:**
```julia
noteon(plugin, 0, 60, 100)  # C4 at full velocity
```

#### `noteoff(plugin, channel, note, offset=0)`
Send MIDI Note Off event.

**Arguments:**
- `channel::Int`: MIDI channel (0-15)
- `note::Int`: Note number (0-127)
- `offset::Int`: Sample position in next block (default: 0)

#### `controlchange(plugin, channel, controller, value, offset=0)`
Send MIDI Control Change (CC) event.

**Arguments:**
- `channel::Int`: MIDI channel (0-15)
- `controller::Int`: CC number (0-127)
- `value::Int`: CC value (0-127)
- `offset::Int`: Sample position in next block (default: 0)

**Example:**
```julia
controlchange(plugin, 0, 1, 64)  # Modulation wheel to 50%
```

#### `programchange(plugin, channel, program, offset=0)`
Send MIDI Program Change event.

**Arguments:**
- `channel::Int`: MIDI channel (0-15)
- `program::Int`: Program number (0-127)
- `offset::Int`: Sample position in next block (default: 0)

**Note:** VST3 plugins may not respond to MIDI program changes. Check for preset parameters and use `setparameter!` if available.

## Examples

See the `examples/` directory for complete examples:

- `basic_usage.jl` - Load plugin and inspect parameters
- `block_processing.jl` - Process WAV file in blocks
- `parameter_automation.jl` - Automate parameters during processing
- `synth_example.jl` - Generate melody with MIDI notes

## Block-Based Processing Patterns

### Pattern 1: Fixed Block Size
```julia
block_size = 256
for i in 1:block_size:length(audio)
    block = audio[:, i:min(i+block_size-1, end)]
    output_block = process(plugin, block)
    # Store output_block
end
```

### Pattern 2: Variable Block Size
```julia
# Process blocks of varying sizes (useful for low-latency)
for block in [64, 128, 256, 512]
    input = randn(Float32, 2, block)
    output = process(plugin, input)
end
```

### Pattern 3: Real-time with Events
```julia
# Process with MIDI events at specific sample positions
block_size = 512

# Schedule note at sample 256 of this block
if should_trigger_note
    noteon(plugin, 0, note, velocity, 256)
end

output = process(plugin, input)
```

## Type Reference

### `PluginInfo`
```julia
struct PluginInfo
    name::String
    vendor::String
    num_inputs::Int
    num_outputs::Int
    num_parameters::Int
    sample_rate::Float64
end
```

### `ParameterInfo`
```julia
struct ParameterInfo
    id::Int
    title::String
    short_title::String
    units::String
    default_value::Float64
    min_value::Float64
    max_value::Float64
    step_count::Int
end
```

### `VST3Plugin`
```julia
mutable struct VST3Plugin
    handle::Ptr{Cvoid}      # C plugin handle
    sample_rate::Float64
    block_size::Int
    num_inputs::Int
    num_outputs::Int
    active::Bool
end
```

## Performance Tips

1. **Reuse buffers**: Pre-allocate output buffers and use `process!`
2. **Appropriate block sizes**: 128-512 samples is typical
3. **Avoid reallocations**: Use fixed-size blocks when possible
4. **Parameter changes**: Set parameters before processing, not during
5. **Activation**: Plugin is automatically activated on first `process`

## Thread Safety

- Plugin instances are NOT thread-safe
- Use one plugin instance per thread
- Parameter changes should be done from the same thread as processing

## Troubleshooting

### Library not found
Make sure `libvst3host.dylib` is built and in `jl/lib/`:
```bash
cd jl/lib && make
ls -l libvst3host.dylib
```

### Plugin fails to load
- Check plugin path is correct
- Plugin must be a valid VST3 bundle (.vst3)
- Check console for error messages

### Audio glitches
- Ensure block size is ≤ plugin's maximum
- Check sample rate matches input audio
- Verify buffer sizes are correct

## License

Same as parent VST3 host project.

## Contributing

Contributions welcome! Areas for improvement:
- More event types (sysex, aftertouch, etc.)
- Process context (tempo, time signature, etc.)
- Preset loading/saving
- GUI integration
- Windows/Linux library building

## See Also

- [VST3 SDK Documentation](https://steinbergmedia.github.io/vst3_doc/)
- Parent project C and Zig implementations
