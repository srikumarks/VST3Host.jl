# VST3Host.jl API Reference

## API Overview

The package provides Julian-style function names following Julia conventions.

### Plugin Management

| Function | Description |
|----------|-------------|
| `VST3Plugin(path, rate, size)` | Load and initialize plugin |
| `info(plugin)` | Get plugin information |
| `activate!(plugin)` | Activate for processing |
| `deactivate!(plugin)` | Deactivate plugin |
| `close(plugin)` | Cleanup and unload |

### Parameters

| Function | Description |
|----------|-------------|
| `parameters(plugin)` | Get all parameter information |
| `parameterinfo(plugin, index)` | Get specific parameter info by index |
| `getparameter(plugin, id)` | Get parameter value |
| `parameter(plugin, id)` | Alias for `getparameter` |
| `setparameter!(plugin, id, value)` | Set parameter value |
| `isdiscrete(param)` | Check if parameter is discrete |
| `formatparameter(param, value)` | Format value as string |

### Audio Processing

| Function | Description |
|----------|-------------|
| `process(plugin, input)` | Process audio block (allocating) |
| `process!(plugin, input, output)` | Process audio in-place |

### MIDI Events

| Function | Description |
|----------|-------------|
| `noteon(plugin, ch, note, vel, offset=0)` | Send Note On |
| `noteoff(plugin, ch, note, offset=0)` | Send Note Off |
| `controlchange(plugin, ch, cc, value, offset=0)` | Send Control Change |
| `programchange(plugin, ch, prog, offset=0)` | Send Program Change |

### Display

VST3Plugin objects have custom display methods:
- **Terminal/REPL**: Full plugin info with all parameters and current values
- **Jupyter Notebook**: HTML table with styled parameter display
- Simply evaluate the plugin variable or use `display(plugin)`

## Quick Examples

### Basic Usage
```julia
using VST3Host

# Load plugin
plugin = VST3Plugin("/path/to/plugin.vst3", 48000.0, 512)

# Display plugin info (automatic in REPL, or use display(plugin))
plugin  # Shows full info with all parameters

# Set parameter
setparameter!(plugin, 0, 0.5)

# Process audio
input = randn(Float32, 2, 512)
output = process(plugin, input)

close(plugin)
```

### MIDI Synth
```julia
using VST3Host

plugin = VST3Plugin("/path/to/synth.vst3", 48000.0, 512)
activate!(plugin)

input = zeros(Float32, 2, 512)

# Play note
noteon(plugin, 0, 60, 100)
output = process(plugin, input)
noteoff(plugin, 0, 60)

close(plugin)
```

### Program Change
```julia
# Method 1: MIDI Program Change
programchange(plugin, 0, 5)

# Method 2: Parameter (often better for VST3)
params = parameters(plugin)
# Find preset parameter
for (i, p) in enumerate(params)
    if occursin("preset", lowercase(p.title))
        setparameter!(plugin, p.id, 0.4)  # Normalized value
    end
end
```

## Type Reference

### VST3Plugin
```julia
mutable struct VST3Plugin
    handle::Ptr{Cvoid}
    sample_rate::Float64
    block_size::Int
    num_inputs::Int
    num_outputs::Int
    active::Bool
end
```

### PluginInfo
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

### ParameterInfo
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
