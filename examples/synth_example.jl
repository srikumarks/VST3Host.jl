using VST3Host
using WAV
using SampledSignals

"""
Example: MIDI note processing with a VST3 synthesizer

This example shows how to:
1. Send MIDI note events to a synth plugin
2. Process the resulting audio in blocks
3. Create a simple melody
"""

function generate_melody(synth_path::String, output_file::String;
                         sample_rate::Float64=44100.0, block_size::Int=512)
    # Load synth plugin
    println("Loading synthesizer...")
    plugin = VST3Plugin(synth_path, sample_rate, block_size)

    plugin_info = info(plugin)
    println("  Plugin: $(plugin_info.name)")
    println("  Outputs: $(plugin_info.num_outputs) channels")

    # Define a simple melody (MIDI note numbers)
    # C4, E4, G4, C5, G4, E4, C4
    melody_notes = [60, 64, 67, 72, 67, 64, 60]
    note_duration = 0.5  # seconds per note

    # Calculate total duration
    total_duration = length(melody_notes) * note_duration
    num_samples = round(Int, total_duration * sample_rate)

    # Prepare output buffer
    output = zeros(Float32, plugin_info.num_outputs, num_samples)

    # Prepare silent input (synth generates audio from MIDI)
    input_data = zeros(Float32, max(plugin_info.num_inputs, 1), block_size)

    # Activate plugin
    activate!(plugin)

    println("\nGenerating melody...")
    current_sample = 0
    current_note_idx = 1
    current_note = -1
    samples_per_note = round(Int, note_duration * sample_rate)

    while current_sample < num_samples
        # Check if we need to trigger a new note
        note_position = div(current_sample, samples_per_note)

        if note_position + 1 <= length(melody_notes)
            new_note = melody_notes[note_position + 1]

            if new_note != current_note
                # Note off for previous note
                if current_note >= 0
                    noteoff(plugin, 0, current_note, 0)
                end

                # Note on for new note
                noteon(plugin, 0, new_note, 100, 0)  # velocity 100
                current_note = new_note

                note_name = midi_note_to_name(new_note)
                time = current_sample / sample_rate
                println("  $(round(time, digits=2))s: Note $note_name ($new_note)")
            end
        end

        # Process block
        block_start = current_sample + 1
        block_end = min(current_sample + block_size, num_samples)
        actual_block_size = block_end - block_start + 1

        input = SampleBuf(input_data, sample_rate)
        output_block = process(plugin, input)

        # Copy to output
        output_data = Array(output_block)
        output[:, block_start:block_end] = output_data[:, 1:actual_block_size]

        current_sample += block_size
    end

    # Final note off
    if current_note >= 0
        noteoff(plugin, 0, current_note, 0)
    end

    # Process a few more blocks to let the sound decay
    println("\nLetting final note decay...")
    for _ in 1:10
        process(plugin, input)
    end

    deactivate!(plugin)

    # Save output
    println("\nSaving output: $output_file")
    wavwrite(output', output_file, Fs=sample_rate)

    close(plugin)
    println("Done!")
end

"""Convert MIDI note number to note name"""
function midi_note_to_name(note::Int)
    note_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    octave = div(note, 12) - 1
    name_idx = (note % 12) + 1
    return "$(note_names[name_idx])$octave"
end

if abspath(PROGRAM_FILE) == @__FILE__
    generate_melody(
        "/Library/Audio/Plug-Ins/VST3/YourSynth.vst3",
        "melody.wav",
        sample_rate=44100.0,
        block_size=512
    )
end
