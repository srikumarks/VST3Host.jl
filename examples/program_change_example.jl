using VST3Host
using WAV

"""
Example: MIDI Program Change with VST3 synth

This example demonstrates how to change presets/programs in a VST3 synth
using MIDI Program Change messages and parameter changes.
"""

function test_program_change(synth_path::String, output_file::String;
                             sample_rate::Float64=44100.0, block_size::Int=512)
    # Load synth plugin
    println("Loading synthesizer...")
    plugin = VST3Plugin(synth_path, sample_rate, block_size)

    plugin_info = info(plugin)
    println("  Plugin: $(plugin_info.name)")

    # Check for preset/program parameters
    println("\nLooking for preset/program parameters...")
    params = parameters(plugin)

    preset_params = []
    for (idx, param) in enumerate(params)
        param_name_lower = lowercase(param.title)
        if occursin("preset", param_name_lower) ||
           occursin("program", param_name_lower) ||
           occursin("patch", param_name_lower)
            println("  Found: [$idx] $(param.title)")
            if isdiscrete(param)
                println("    Type: Discrete ($(param.step_count) presets)")
            else
                println("    Type: Continuous")
            end
            push!(preset_params, (idx, param))
        end
    end

    # Test note duration
    note_duration = 1.0  # 1 second per program
    num_programs = 4  # Test 4 different programs

    # Calculate total duration
    total_duration = num_programs * note_duration
    num_samples = round(Int, total_duration * sample_rate)

    # Prepare output buffer
    output = zeros(Float32, plugin_info.num_outputs, num_samples)
    input = zeros(Float32, max(plugin_info.num_inputs, 1), block_size)

    # Activate plugin
    activate!(plugin)

    println("\nTesting program changes...")
    current_sample = 0

    for prog in 0:(num_programs-1)
        start_sample = current_sample
        end_sample = min(current_sample + round(Int, note_duration * sample_rate), num_samples)

        println("\n--- Program $prog ---")

        # Method 1: Try MIDI Program Change
        programchange(plugin, 0, prog, 0)

        # Method 2: If there's a preset parameter, try changing it
        if !isempty(preset_params)
            param_idx, param = preset_params[1]
            if isdiscrete(param)
                # Discrete parameter - set to specific step
                value = prog / param.step_count
                value = clamp(value, 0.0, 1.0)
            else
                # Continuous parameter - divide range
                value = prog / (num_programs - 1)
            end
            setparameter!(plugin, param.id, value)
            println("  Set parameter '$(param.title)' to $(formatparameter(param, value))")
        end

        # Send a test note
        noteon(plugin, 0, 60, 100, 0)  # C4

        # Process blocks for this program
        while current_sample < end_sample
            block_start = current_sample + 1
            block_end = min(current_sample + block_size, end_sample)
            actual_block_size = block_end - block_start + 1

            output_block = process(plugin, input)

            # Copy to output
            if block_start <= num_samples
                copy_end = min(block_end, num_samples)
                output[:, block_start:copy_end] = output_block[:, 1:(copy_end - block_start + 1)]
            end

            current_sample += block_size
        end

        # Note off
        noteoff(plugin, 0, 60, 0)

        # Process a bit more to let note decay
        for _ in 1:4
            process(plugin, input)
        end

        current_sample = end_sample
    end

    deactivate!(plugin)

    # Save output
    println("\nSaving output: $output_file")
    wavwrite(output', output_file, Fs=sample_rate)

    close(plugin)
    println("Done!")

    if isempty(preset_params)
        println("\n⚠ Note: This plugin doesn't expose preset parameters.")
        println("Program changes may or may not work depending on the plugin.")
        println("Check the plugin's documentation for preset management.")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    # Example usage - update with your synth path
    test_program_change(
        "/Library/Audio/Plug-Ins/VST3/YourSynth.vst3",
        "program_change_test.wav",
        sample_rate=44100.0,
        block_size=512
    )
end
