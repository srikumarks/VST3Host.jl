using VST3Host
using WAV

"""
Example: Block-based audio processing with VST3 plugin

This example shows how to:
1. Load a plugin
2. Process audio in blocks of arbitrary size
3. Send parameter changes
4. Write the processed audio to a file
"""

function process_audio_blocks(plugin_path::String, input_file::String, output_file::String;
                               block_size::Int=128)
    # Load input audio
    println("Loading input audio: $input_file")
    y, fs = wavread(input_file)

    # Convert to Float32 and transpose to (channels × samples)
    audio = Float32.(y')

    num_channels, num_samples = size(audio)
    println("  Channels: $num_channels")
    println("  Samples: $num_samples")
    println("  Sample rate: $fs Hz")
    println("  Duration: $(num_samples/fs) seconds")

    # Load plugin
    println("\nLoading plugin: $plugin_path")
    plugin = VST3Plugin(plugin_path, Float64(fs), block_size)

    plugin_info = info(plugin)
    println("  Plugin: $(plugin_info.name)")
    println("  I/O: $(plugin_info.num_inputs) → $(plugin_info.num_outputs)")

    # Prepare output buffer
    output = zeros(Float32, plugin_info.num_outputs, num_samples)

    # Process audio in blocks
    println("\nProcessing audio in blocks of $block_size samples...")
    activate!(plugin)

    num_blocks = div(num_samples, block_size) + (num_samples % block_size != 0 ? 1 : 0)

    for block_idx in 1:num_blocks
        # Calculate block boundaries
        start_sample = (block_idx - 1) * block_size + 1
        end_sample = min(block_idx * block_size, num_samples)
        current_block_size = end_sample - start_sample + 1

        # Extract input block
        input_block = audio[:, start_sample:end_sample]

        # Pad to block size if needed
        if current_block_size < block_size
            padded = zeros(Float32, num_channels, block_size)
            padded[:, 1:current_block_size] = input_block
            input_block = padded
        end

        # Process block
        output_block = process(plugin, input_block)

        # Copy to output (remove padding if any)
        output[:, start_sample:end_sample] = output_block[:, 1:current_block_size]

        # Progress indicator
        if block_idx % 100 == 0 || block_idx == num_blocks
            progress = round(block_idx / num_blocks * 100, digits=1)
            print("\r  Progress: $progress%")
        end
    end
    println()

    deactivate!(plugin)

    # Save output
    println("\nSaving output: $output_file")
    wavwrite(output', output_file, Fs=fs)

    # Cleanup
    close(plugin)

    println("Done!")
end

# Example usage
if abspath(PROGRAM_FILE) == @__FILE__
    process_audio_blocks(
        "/Library/Audio/Plug-Ins/VST3/YourPlugin.vst3",
        "input.wav",
        "output.wav",
        block_size=128
    )
end
