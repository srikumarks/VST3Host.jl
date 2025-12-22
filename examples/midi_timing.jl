using VST3Host
using SampledSignals

"""
Example: MIDI event timing and offset computation

This example demonstrates how to:
1. Get the plugin's sampling rate and block size
2. Track current timestamp during audio processing
3. Compute sample offsets for scheduling MIDI events
4. Trigger notes at precise times within buffers
"""

function schedule_midi_events(plugin_path::String; sample_rate::Float64=44100.0, block_size::Int=512)
    plugin = VST3Plugin(plugin_path, sample_rate, block_size)
    plugin_info = info(plugin)

    println("Plugin: $(plugin_info.name)")
    println("Sample Rate: $(plugin_info.sample_rate) Hz")
    println("Block Size: $(plugin.block_size) samples")
    println()

    # Schedule some notes at specific times (in seconds)
    notes_schedule = [
        (time=0.0,   note=60, velocity=100, duration=0.5),
        (time=0.5,   note=64, velocity=100, duration=0.5),
        (time=1.0,   note=67, velocity=100, duration=0.5),
        (time=1.5,   note=72, velocity=100, duration=0.5),
    ]

    total_duration = 2.0  # seconds
    num_samples = round(Int, total_duration * plugin_info.sample_rate)
    num_blocks = div(num_samples, block_size)

    output = zeros(Float32, plugin_info.num_outputs, num_samples)
    input_data = zeros(Float32, plugin_info.num_inputs, block_size)

    activate!(plugin)

    current_sample = 0

    for block_idx in 1:num_blocks
        current_time = current_sample / plugin_info.sample_rate
        block_end_time = (current_sample + block_size) / plugin_info.sample_rate

        println("Block $block_idx: time $(round(current_time, digits=2))s - $(round(block_end_time, digits=2))s")

        # Method 1: Compute offset for events in this block
        for (note_time, note, velocity, duration) in notes_schedule
            # Check if note should start in this buffer
            if current_time <= note_time < block_end_time
                # Calculate sample offset within this buffer
                offset = round(Int, (note_time - current_time) * plugin_info.sample_rate)
                println("  → Note On at offset $offset (time $(round(note_time, digits=2))s)")
                noteon(plugin, 0, note, velocity, offset=offset)
            end

            # Check if note should end in this buffer
            note_end_time = note_time + duration
            if current_time <= note_end_time < block_end_time
                offset = round(Int, (note_end_time - current_time) * plugin_info.sample_rate)
                println("  → Note Off at offset $offset (time $(round(note_end_time, digits=2))s)")
                noteoff(plugin, 0, note, offset=offset)
            end
        end

        # Process block
        input = SampleBuf(input_data, sample_rate)
        output_block = process(plugin, input)
        output_data = Array(output_block)
        output[:, current_sample+1:current_sample+block_size] = output_data

        current_sample += block_size
    end

    deactivate!(plugin)
    close(plugin)

    println("\nDone!")
end

# ============================================================================
# Alternative: Event-driven scheduling with lookahead
# ============================================================================

function event_driven_scheduling(plugin_path::String; sample_rate::Float64=44100.0, block_size::Int=512)
    plugin = VST3Plugin(plugin_path, sample_rate, block_size)
    plugin_info = info(plugin)

    # Events with absolute sample positions
    events = [
        (sample=0,      type=:note_on,  note=60, velocity=100),
        (sample=22050,  type=:note_off, note=60),
        (sample=22050,  type=:note_on,  note=64, velocity=100),
        (sample=44100,  type=:note_off, note=64),
    ]

    total_samples = 88200
    num_blocks = div(total_samples, block_size)

    output = zeros(Float32, plugin_info.num_outputs, total_samples)
    input_data = zeros(Float32, plugin_info.num_inputs, block_size)

    activate!(plugin)

    current_sample = 0
    event_idx = 1

    for block_idx in 1:num_blocks
        # Process events that occur in this block
        while event_idx <= length(events)
            event = events[event_idx]

            if current_sample <= event.sample < current_sample + block_size
                # Event occurs in this block
                offset = event.sample - current_sample

                if event.type == :note_on
                    println("Block $block_idx: Note On $(event.note) at offset $offset")
                    noteon(plugin, 0, event.note, event.velocity, offset=offset)
                elseif event.type == :note_off
                    println("Block $block_idx: Note Off at offset $offset")
                    noteoff(plugin, 0, event.note, offset=offset)
                end

                event_idx += 1
            else
                break  # Event is in a future block
            end
        end

        # Process block
        input = SampleBuf(input_data, sample_rate)
        output_block = process(plugin, input)
        output_data = Array(output_block)
        output[:, current_sample+1:current_sample+block_size] = output_data

        current_sample += block_size
    end

    deactivate!(plugin)
    close(plugin)
end

# ============================================================================
# Example usage
# ============================================================================

if abspath(PROGRAM_FILE) == @__FILE__
    println("=== Method 1: Time-based scheduling ===")
    schedule_midi_events(
        "/Library/Audio/Plug-Ins/VST3/YourSynth.vst3",
        sample_rate=44100.0,
        block_size=512
    )

    println("\n=== Method 2: Event-driven scheduling ===")
    event_driven_scheduling(
        "/Library/Audio/Plug-Ins/VST3/YourSynth.vst3",
        sample_rate=44100.0,
        block_size=512
    )
end
