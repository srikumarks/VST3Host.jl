using VST3Host
using SampledSignals

"""
Example: Parameter automation during processing

This example demonstrates how to automate parameters while processing audio blocks.
"""

function automate_parameters(plugin_path::String; duration_seconds::Float64=5.0,
                             sample_rate::Float64=44100.0, block_size::Int=256)
    # Load plugin
    println("Loading plugin...")
    plugin = VST3Plugin(plugin_path, sample_rate, block_size)

    display(plugin)
    println()

    # Get parameters
    params = parameters(plugin)
    if isempty(params)
        println("No parameters available!")
        close(plugin)
        return
    end

    # Select first parameter for automation
    param = params[1]
    println("Automating parameter: $(param.title)")
    println("  Default value: $(formatparameter(param, param.default_value))")
    println()

    # Calculate total number of blocks
    num_samples = round(Int, duration_seconds * sample_rate)
    num_blocks = div(num_samples, block_size)

    # Prepare input (silence)
    plugin_info = info(plugin)
    input_data = zeros(Float32, plugin_info.num_inputs, block_size)

    # Activate plugin
    activate!(plugin)

    println("Processing $num_blocks blocks with parameter automation...")

    for block_idx in 1:num_blocks
        # Calculate parameter value (sine wave automation)
        time = (block_idx - 1) * block_size / sample_rate
        freq = 1.0  # 1 Hz modulation
        param_value = 0.5 + 0.5 * sin(2π * freq * time)

        # Set parameter
        setparameter!(plugin, param.id, param_value)

        # Process block
        input = SampleBuf(input_data, sample_rate)
        output = process(plugin, input)

        # Print status every second
        if block_idx % round(Int, sample_rate / block_size) == 0
            current_value = getparameter(plugin, param.id)
            formatted = formatparameter(param, current_value)
            println("  Time: $(round(time, digits=2))s, $(param.short_title) = $formatted")
        end
    end

    deactivate!(plugin)
    close(plugin)

    println("\nDone!")
end

if abspath(PROGRAM_FILE) == @__FILE__
    automate_parameters(
        "/Library/Audio/Plug-Ins/VST3/YourPlugin.vst3",
        duration_seconds=5.0,
        sample_rate=44100.0,
        block_size=256
    )
end
