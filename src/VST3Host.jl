"""
    VST3Host

Julia package for hosting VST3 audio plugins with block-based processing and event support.

# Features
- Load and initialize VST3 plugins
- Block-based audio processing (any block size)
- Parameter discovery and automation
- MIDI event support (Note On/Off, CC, Program Change)
- Real-time parameter changes

# Example
```julia
using VST3Host
using SampledSignals

# Load plugin
plugin = VST3Plugin("/Library/Audio/Plug-Ins/VST3/MyPlugin.vst3", 44100.0, 512)

# Get plugin info and parameters
info(plugin)
params = parameters(plugin)

# Set parameter
setparameter!(plugin, 0, 0.5)

# Process audio block with SampleBuf
sr = 44100.0  # sample rate
input = SampleBuf(randn(Float32, 2, 512), sr)  # 2 channels, 512 samples
output = process(plugin, input)

# Send MIDI events
noteon(plugin, 0, 60, 100)  # channel 0, note 60 (C4), velocity 100
output = process(plugin, input)
noteoff(plugin, 0, 60)

# Cleanup
close(plugin)
```
"""
module VST3Host

# Export types
export VST3Plugin, PluginInfo, ParameterInfo

# Export main API
export info, parameters, parameter, parameterinfo
export setparameter!, getparameter
export process, process!
export activate!, deactivate!

# Export MIDI functions
export noteon, noteoff, controlchange, programchange

# Export utility functions
export formatparameter, isdiscrete

using Printf
using SampledSignals

# Find the shared library
const libvst3 = let
    lib_path = joinpath(@__DIR__, "..", "lib", "libvst3host")
    if Sys.isapple()
        lib_path * ".dylib"
    elseif Sys.islinux()
        lib_path * ".so"
    elseif Sys.iswindows()
        lib_path * ".dll"
    else
        error("Unsupported platform")
    end
end

# C structure definitions
struct CPluginInfo
    name::NTuple{128, UInt8}
    vendor::NTuple{128, UInt8}
    num_inputs::Int32
    num_outputs::Int32
    num_parameters::Int32
    sample_rate::Float64
end

struct CParameterInfo
    id::Int32
    title::NTuple{128, UInt8}
    short_title::NTuple{32, UInt8}
    units::NTuple{32, UInt8}
    default_value::Float64
    min_value::Float64
    max_value::Float64
    step_count::Int32
end

# Julia types
"""
    PluginInfo

Information about a VST3 plugin.

# Fields
- `name::String`: Plugin name
- `vendor::String`: Plugin vendor
- `num_inputs::Int`: Number of input channels
- `num_outputs::Int`: Number of output channels
- `num_parameters::Int`: Number of parameters
- `sample_rate::Float64`: Sample rate (Hz)
"""
struct PluginInfo
    name::String
    vendor::String
    num_inputs::Int
    num_outputs::Int
    num_parameters::Int
    sample_rate::Float64
end

"""
    ParameterInfo

Information about a plugin parameter.

# Fields
- `id::Int`: Parameter ID
- `title::String`: Full parameter name/title
- `short_title::String`: Abbreviated parameter name
- `units::String`: Parameter units (e.g., "dB", "Hz", "%")
- `default_value::Float64`: Default value (normalized 0-1)
- `min_value::Float64`: Minimum value (always 0.0 for VST3)
- `max_value::Float64`: Maximum value (always 1.0 for VST3)
- `step_count::Int`: Number of discrete steps (0 for continuous parameters)

# Notes
VST3 parameters are always normalized to the range [0, 1]. Use `format_parameter`
to get human-readable string representations.
"""
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

# Add pretty printing
function Base.show(io::IO, p::ParameterInfo)
    print(io, "Parameter #$(p.id): $(p.title)")
    if !isempty(p.short_title) && p.short_title != p.title
        print(io, " ($(p.short_title))")
    end
    if !isempty(p.units)
        print(io, " [$(p.units)]")
    end
    if p.step_count > 0
        print(io, " {discrete: $(p.step_count) steps}")
    else
        print(io, " {continuous}")
    end
    print(io, " default=$(round(p.default_value, digits=3))")
end

"""
    VST3Plugin

Handle to a loaded VST3 plugin.

# Fields
- `handle::Ptr{Cvoid}`: C pointer to plugin
- `sample_rate::Float64`: Sample rate
- `block_size::Int`: Maximum block size
- `num_inputs::Int`: Number of input channels
- `num_outputs::Int`: Number of output channels
"""
mutable struct VST3Plugin
    handle::Ptr{Cvoid}
    sample_rate::Float64
    block_size::Int
    num_inputs::Int
    num_outputs::Int
    active::Bool

    function VST3Plugin(path::String, sample_rate::Float64, block_size::Int)
        # Expand ~ and make path absolute
        expanded_path = abspath(expanduser(path))

        handle = ccall((:vst3_load_plugin, libvst3), Ptr{Cvoid}, (Cstring,), expanded_path)
        if handle == C_NULL
            error("Failed to load plugin: $expanded_path")
        end

        # Get plugin info
        info_c = Ref{CPluginInfo}()
        ret = ccall((:vst3_get_plugin_info, libvst3), Int32,
                    (Ptr{Cvoid}, Ptr{CPluginInfo}), handle, info_c)
        if ret != 0
            ccall((:vst3_unload_plugin, libvst3), Cvoid, (Ptr{Cvoid},), handle)
            error("Failed to get plugin info")
        end

        # Setup processing
        ret = ccall((:vst3_setup_processing, libvst3), Int32,
                    (Ptr{Cvoid}, Float64, Int32), handle, sample_rate, block_size)
        if ret != 0
            ccall((:vst3_unload_plugin, libvst3), Cvoid, (Ptr{Cvoid},), handle)
            error("Failed to setup processing")
        end

        plugin = new(handle, sample_rate, block_size,
                    info_c[].num_inputs, info_c[].num_outputs, false)

        finalizer(plugin) do p
            if p.handle != C_NULL
                if p.active
                    deactivate!(p)
                end
                ccall((:vst3_unload_plugin, libvst3), Cvoid, (Ptr{Cvoid},), p.handle)
                p.handle = C_NULL
            end
        end

        return plugin
    end
end

"""
    close(plugin::VST3Plugin)

Cleanup and unload the plugin. Deactivates the plugin if active and releases resources.

This is called automatically by the finalizer, but can be called explicitly for immediate cleanup.
"""
function Base.close(plugin::VST3Plugin)
    if plugin.handle != C_NULL
        if plugin.active
            deactivate!(plugin)
        end
        ccall((:vst3_unload_plugin, libvst3), Cvoid, (Ptr{Cvoid},), plugin.handle)
        plugin.handle = C_NULL
    end
    return nothing
end

# Helper to convert C string to Julia string
function cstring_to_string(ntuple)
    bytes = UInt8[b for b in ntuple if b != 0]
    return String(bytes)
end

"""
    info(plugin::VST3Plugin) -> PluginInfo

Get plugin information (name, vendor, I/O configuration, parameters).
"""
function info(plugin::VST3Plugin)
    info_c = Ref{CPluginInfo}()
    ret = ccall((:vst3_get_plugin_info, libvst3), Int32,
                (Ptr{Cvoid}, Ptr{CPluginInfo}), plugin.handle, info_c)
    if ret != 0
        error("Failed to get plugin info")
    end

    return PluginInfo(
        cstring_to_string(info_c[].name),
        cstring_to_string(info_c[].vendor),
        info_c[].num_inputs,
        info_c[].num_outputs,
        info_c[].num_parameters,
        info_c[].sample_rate
    )
end

"""
    parameters(plugin::VST3Plugin) -> Vector{ParameterInfo}

Get all parameter information from the plugin.
"""
function parameters(plugin::VST3Plugin)
    count = ccall((:vst3_get_parameter_count, libvst3), Int32, (Ptr{Cvoid},), plugin.handle)

    params = ParameterInfo[]
    for i in 0:(count-1)
        param_c = Ref{CParameterInfo}()
        ret = ccall((:vst3_get_parameter_info, libvst3), Int32,
                    (Ptr{Cvoid}, Int32, Ptr{CParameterInfo}),
                    plugin.handle, i, param_c)

        if ret == 0
            push!(params, ParameterInfo(
                param_c[].id,
                cstring_to_string(param_c[].title),
                cstring_to_string(param_c[].short_title),
                cstring_to_string(param_c[].units),
                param_c[].default_value,
                param_c[].min_value,
                param_c[].max_value,
                param_c[].step_count
            ))
        end
    end

    return params
end

"""
    getparameter(plugin::VST3Plugin, param_id::Int) -> Float64

Get current parameter value (normalized 0.0-1.0).
"""
function getparameter(plugin::VST3Plugin, param_id::Int)
    return ccall((:vst3_get_parameter, libvst3), Float64,
                 (Ptr{Cvoid}, Int32), plugin.handle, param_id)
end

"""
    setparameter!(plugin::VST3Plugin, param_id::Int, value::Float64)

Set parameter value (normalized 0.0-1.0).
"""
function setparameter!(plugin::VST3Plugin, param_id::Int, value::Float64)
    @assert 0.0 <= value <= 1.0 "Parameter value must be between 0 and 1"
    ret = ccall((:vst3_set_parameter, libvst3), Int32,
                (Ptr{Cvoid}, Int32, Float64), plugin.handle, param_id, value)
    if ret != 0
        error("Failed to set parameter")
    end
    return nothing
end

"""
    activate!(plugin::VST3Plugin)

Activate the plugin for processing.
"""
function activate!(plugin::VST3Plugin)
    if !plugin.active
        ret = ccall((:vst3_set_active, libvst3), Int32,
                    (Ptr{Cvoid}, Int32), plugin.handle, 1)
        if ret != 0
            error("Failed to activate plugin")
        end
        plugin.active = true
    end
    return nothing
end

"""
    deactivate!(plugin::VST3Plugin)

Deactivate the plugin.
"""
function deactivate!(plugin::VST3Plugin)
    if plugin.active
        ret = ccall((:vst3_set_active, libvst3), Int32,
                    (Ptr{Cvoid}, Int32), plugin.handle, 0)
        if ret != 0
            @warn "Failed to deactivate plugin"
        end
        plugin.active = false
    end
    return nothing
end

"""
    process(plugin::VST3Plugin, input::Matrix{Float32}) -> Matrix{Float32}

Process audio block. Input should be (channels × samples).
Returns output with (num_outputs × samples).

Automatically activates the plugin if not already active.
"""
"""
    process(plugin::VST3Plugin, input::SampleBuf{Float32})

Process a buffer of audio and return output as SampleBuf.

# Arguments
- `input::SampleBuf{Float32}`: Input audio buffer
- Returns output as a new SampleBuf with shape (num_outputs, num_samples)
"""
function process(plugin::VST3Plugin, input::SampleBuf{Float32})
    num_samples = nsamples(input)
    sr = samplerate(input)
    output = SampleBuf(zeros(Float32, plugin.num_outputs, num_samples), sr)
    process!(plugin, input, output)
    return output
end

# Convenience overload for Matrix for backward compatibility
function process(plugin::VST3Plugin, input::Matrix{Float32})
    num_samples = size(input, 2)
    # Use plugin's sample rate as default
    sr = plugin.sample_rate
    sample_buf = SampleBuf(input, sr)
    output_buf = process(plugin, sample_buf)
    return Array(output_buf)
end

"""
    process!(plugin::VST3Plugin, input::SampleBuf{Float32}, output::SampleBuf{Float32})

Process audio in-place, writing to pre-allocated output buffer.

Automatically activates the plugin if not already active.

# Arguments
- `input::SampleBuf{Float32}`: Input audio buffer
- `output::SampleBuf{Float32}`: Output buffer (will be filled with processed audio)
"""
function process!(plugin::VST3Plugin, input::SampleBuf{Float32}, output::SampleBuf{Float32})
    input_data = Array(input)
    output_data = Array(output)

    @assert size(input_data, 2) == size(output_data, 2) "Input and output must have same number of samples"
    @assert size(input_data, 2) <= plugin.block_size "Block size exceeds maximum"
    @assert size(input_data, 1) <= plugin.num_inputs "Too many input channels"
    @assert size(output_data, 1) <= plugin.num_outputs "Too many output channels"

    # Auto-activate if needed
    if !plugin.active
        activate!(plugin)
    end

    num_samples = size(input_data, 2)
    num_in_channels = size(input_data, 1)
    num_out_channels = size(output_data, 1)

    # Create pointers to each channel
    input_ptrs = [pointer(input_data, (i-1)*num_samples + 1) for i in 1:num_in_channels]
    output_ptrs = [pointer(output_data, (i-1)*num_samples + 1) for i in 1:num_out_channels]

    ret = ccall((:vst3_process, libvst3), Int32,
                (Ptr{Cvoid}, Ptr{Ptr{Float32}}, Ptr{Ptr{Float32}}, Int32, Int32, Int32),
                plugin.handle, input_ptrs, output_ptrs, num_samples, num_in_channels, num_out_channels)

    if ret != 0
        error("Processing failed")
    end

    return nothing
end

# Convenience overload for Matrix for backward compatibility
function process!(plugin::VST3Plugin, input::Matrix{Float32}, output::Matrix{Float32})
    sr = plugin.sample_rate
    input_buf = SampleBuf(input, sr)
    output_buf = SampleBuf(output, sr)
    process!(plugin, input_buf, output_buf)
    return nothing
end

"""
    noteon(plugin::VST3Plugin, channel::Int, note::Int, velocity::Int, offset::Int=0)

Send MIDI Note On event.

# Arguments
- `channel`: MIDI channel (0-15)
- `note`: Note number (0-127, middle C = 60)
- `velocity`: Note velocity (0-127)
- `offset`: Sample offset in next block (default: 0)
"""
function noteon(plugin::VST3Plugin, channel::Int, note::Int, velocity::Int, offset::Int=0)
    @assert 0 <= channel <= 15 "MIDI channel must be 0-15"
    @assert 0 <= note <= 127 "MIDI note must be 0-127"
    @assert 0 <= velocity <= 127 "MIDI velocity must be 0-127"
    @assert 0 <= offset < plugin.block_size "Sample offset out of range"

    ret = ccall((:vst3_send_note_on, libvst3), Int32,
                (Ptr{Cvoid}, Int32, Int32, Int32, Int32),
                plugin.handle, channel, note, velocity, offset)

    if ret != 0
        error("Failed to send note-on event")
    end
    return nothing
end

"""
    noteoff(plugin::VST3Plugin, channel::Int, note::Int, offset::Int=0)

Send MIDI Note Off event.

# Arguments
- `channel`: MIDI channel (0-15)
- `note`: Note number (0-127)
- `offset`: Sample offset in next block (default: 0)
"""
function noteoff(plugin::VST3Plugin, channel::Int, note::Int, offset::Int=0)
    @assert 0 <= channel <= 15 "MIDI channel must be 0-15"
    @assert 0 <= note <= 127 "MIDI note must be 0-127"
    @assert 0 <= offset < plugin.block_size "Sample offset out of range"

    ret = ccall((:vst3_send_note_off, libvst3), Int32,
                (Ptr{Cvoid}, Int32, Int32, Int32),
                plugin.handle, channel, note, offset)

    if ret != 0
        error("Failed to send note-off event")
    end
    return nothing
end

"""
    controlchange(plugin::VST3Plugin, channel::Int, controller::Int, value::Int, offset::Int=0)

Send MIDI Control Change (CC) event.

# Arguments
- `channel`: MIDI channel (0-15)
- `controller`: CC number (0-127)
- `value`: CC value (0-127)
- `offset`: Sample offset in next block (default: 0)
"""
function controlchange(plugin::VST3Plugin, channel::Int, controller::Int, value::Int, offset::Int=0)
    @assert 0 <= channel <= 15 "MIDI channel must be 0-15"
    @assert 0 <= controller <= 127 "CC number must be 0-127"
    @assert 0 <= value <= 127 "CC value must be 0-127"
    @assert 0 <= offset < plugin.block_size "Sample offset out of range"

    ret = ccall((:vst3_send_midi_cc, libvst3), Int32,
                (Ptr{Cvoid}, Int32, Int32, Int32, Int32),
                plugin.handle, channel, controller, value, offset)

    if ret != 0
        error("Failed to send MIDI CC event")
    end
    return nothing
end

"""
    programchange(plugin::VST3Plugin, channel::Int, program::Int, offset::Int=0)

Send MIDI Program Change event.

# Arguments
- `channel`: MIDI channel (0-15)
- `program`: Program number (0-127)
- `offset`: Sample offset in next block (default: 0)

# Note
VST3 plugins may not respond to MIDI program changes. Check for
preset parameters with `parameters(plugin)` and use `setparameter!()`
if available.
"""
function programchange(plugin::VST3Plugin, channel::Int, program::Int, offset::Int=0)
    @assert 0 <= channel <= 15 "MIDI channel must be 0-15"
    @assert 0 <= program <= 127 "Program number must be 0-127"
    @assert 0 <= offset < plugin.block_size "Sample offset out of range"

    ret = ccall((:vst3_send_program_change, libvst3), Int32,
                (Ptr{Cvoid}, Int32, Int32, Int32),
                plugin.handle, channel, program, offset)

    if ret != 0
        error("Failed to send program change event")
    end
    return nothing
end

"""
    parameterinfo(plugin::VST3Plugin, index::Int) -> ParameterInfo

Get information about a specific parameter by index (0-based).
"""
function parameterinfo(plugin::VST3Plugin, index::Int)
    param_c = Ref{CParameterInfo}()
    ret = ccall((:vst3_get_parameter_info, libvst3), Int32,
                (Ptr{Cvoid}, Int32, Ptr{CParameterInfo}),
                plugin.handle, index, param_c)

    if ret != 0
        error("Failed to get parameter info for index $index")
    end

    return ParameterInfo(
        param_c[].id,
        cstring_to_string(param_c[].title),
        cstring_to_string(param_c[].short_title),
        cstring_to_string(param_c[].units),
        param_c[].default_value,
        param_c[].min_value,
        param_c[].max_value,
        param_c[].step_count
    )
end

"""
    isdiscrete(param::ParameterInfo) -> Bool

Check if parameter is discrete (has finite steps) vs continuous.
"""
isdiscrete(param::ParameterInfo) = param.step_count > 0

"""
    formatparameter(param::ParameterInfo, value::Float64) -> String

Format parameter value as human-readable string with units.

For continuous parameters, returns the value with units.
For discrete parameters, returns the step number.
"""
function formatparameter(param::ParameterInfo, value::Float64)
    if isdiscrete(param)
        # Discrete parameter - show step number
        step = round(Int, value * param.step_count)
        return "$(step)/$(param.step_count)"
    else
        # Continuous parameter - show value with units
        if isempty(param.units)
            return @sprintf("%.3f", value)
        else
            return @sprintf("%.3f %s", value, param.units)
        end
    end
end

# Convenience alias for getting parameter as a readable value
parameter(plugin::VST3Plugin, param_id::Int) = getparameter(plugin, param_id)

# Display methods for VST3Plugin

"""
Compact display for VST3Plugin (one-line summary)
"""
function Base.show(io::IO, plugin::VST3Plugin)
    plugin_info = info(plugin)
    print(io, "VST3Plugin(\"$(plugin_info.name)\", $(plugin_info.sample_rate)Hz, $(plugin.block_size) samples)")
end

"""
Full terminal display for VST3Plugin
"""
function Base.show(io::IO, ::MIME"text/plain", plugin::VST3Plugin)
    plugin_info = info(plugin)
    params = parameters(plugin)

    println(io, "═"^70)
    println(io, "VST3 Plugin: $(plugin_info.name)")
    println(io, "Vendor: $(plugin_info.vendor)")
    println(io, "─"^70)
    println(io, "Configuration:")
    println(io, "  Sample Rate: $(plugin_info.sample_rate) Hz")
    println(io, "  Block Size:  $(plugin.block_size) samples")
    println(io, "  Inputs:      $(plugin_info.num_inputs) channels")
    println(io, "  Outputs:     $(plugin_info.num_outputs) channels")
    println(io, "  Active:      $(plugin.active)")
    println(io, "─"^70)
    println(io, "Parameters: $(length(params))")

    if !isempty(params)
        println(io, "")
        for (idx, param) in enumerate(params)
            value = getparameter(plugin, param.id)
            formatted = formatparameter(param, value)

            print(io, "  [$idx] $(param.title)")
            if !isempty(param.units)
                print(io, " [$(param.units)]")
            end
            print(io, " = $formatted")

            if isdiscrete(param)
                print(io, " (discrete, $(param.step_count) steps)")
            end
            println(io)

            # Show default value
            default_str = formatparameter(param, param.default_value)
            println(io, "       Default: $default_str")
        end
    end

    print(io, "═"^70)
end

"""
HTML display for VST3Plugin (Jupyter notebooks)
"""
function Base.show(io::IO, ::MIME"text/html", plugin::VST3Plugin)
    plugin_info = info(plugin)
    params = parameters(plugin)

    println(io, "<div style='font-family: monospace; border: 2px solid #333; padding: 15px; margin: 10px 0; border-radius: 5px;'>")
    println(io, "<h3 style='margin-top: 0; color: #2c5aa0;'>🎵 VST3 Plugin: $(plugin_info.name)</h3>")
    println(io, "<p><strong>Vendor:</strong> $(plugin_info.vendor)</p>")

    println(io, "<table style='width: 100%; border-collapse: collapse; margin: 10px 0;'>")
    println(io, "<tr><th style='text-align: left; padding: 5px; background: #f0f0f0;'>Configuration</th><th style='text-align: left; padding: 5px; background: #f0f0f0;'>Value</th></tr>")
    println(io, "<tr><td style='padding: 5px;'>Sample Rate</td><td style='padding: 5px;'>$(plugin_info.sample_rate) Hz</td></tr>")
    println(io, "<tr><td style='padding: 5px;'>Block Size</td><td style='padding: 5px;'>$(plugin.block_size) samples</td></tr>")
    println(io, "<tr><td style='padding: 5px;'>Inputs</td><td style='padding: 5px;'>$(plugin_info.num_inputs) channels</td></tr>")
    println(io, "<tr><td style='padding: 5px;'>Outputs</td><td style='padding: 5px;'>$(plugin_info.num_outputs) channels</td></tr>")
    println(io, "<tr><td style='padding: 5px;'>Active</td><td style='padding: 5px;'>$(plugin.active ? "✓" : "✗")</td></tr>")
    println(io, "</table>")

    if !isempty(params)
        println(io, "<h4 style='color: #2c5aa0;'>Parameters ($(length(params)))</h4>")
        println(io, "<table style='width: 100%; border-collapse: collapse; font-size: 0.9em;'>")
        println(io, "<tr>")
        println(io, "<th style='text-align: left; padding: 5px; background: #f0f0f0; border: 1px solid #ddd;'>#</th>")
        println(io, "<th style='text-align: left; padding: 5px; background: #f0f0f0; border: 1px solid #ddd;'>Parameter</th>")
        println(io, "<th style='text-align: left; padding: 5px; background: #f0f0f0; border: 1px solid #ddd;'>Current Value</th>")
        println(io, "<th style='text-align: left; padding: 5px; background: #f0f0f0; border: 1px solid #ddd;'>Default</th>")
        println(io, "<th style='text-align: left; padding: 5px; background: #f0f0f0; border: 1px solid #ddd;'>Type</th>")
        println(io, "</tr>")

        for (idx, param) in enumerate(params)
            value = getparameter(plugin, param.id)
            formatted = formatparameter(param, value)
            default_str = formatparameter(param, param.default_value)

            param_name = param.title
            if !isempty(param.units)
                param_name *= " [$(param.units)]"
            end

            param_type = isdiscrete(param) ? "Discrete ($(param.step_count))" : "Continuous"

            println(io, "<tr>")
            println(io, "<td style='padding: 5px; border: 1px solid #ddd;'>$idx</td>")
            println(io, "<td style='padding: 5px; border: 1px solid #ddd;'>$param_name</td>")
            println(io, "<td style='padding: 5px; border: 1px solid #ddd;'><strong>$formatted</strong></td>")
            println(io, "<td style='padding: 5px; border: 1px solid #ddd;'>$default_str</td>")
            println(io, "<td style='padding: 5px; border: 1px solid #ddd;'>$param_type</td>")
            println(io, "</tr>")
        end

        println(io, "</table>")
    end

    print(io, "</div>")
end

end # module

