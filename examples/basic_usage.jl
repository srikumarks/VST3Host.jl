using VST3Host

# Example: Load a VST3 plugin and inspect its parameters

function main()
    # Load a plugin (update path to a real plugin on your system)
    plugin_path = "/Library/Audio/Plug-Ins/VST3/YourPlugin.vst3"

    println("Loading plugin...")
    plugin = VST3Plugin(plugin_path, 44100.0, 512)

    # Display plugin information (uses Base.show)
    display(plugin)

    # Get specific parameter info
    println("\nDetailed parameter inspection:")
    params = parameters(plugin)
    if length(params) > 0
        param = params[1]
        println(param)
        value = getparameter(plugin, param.id)
        println("  Current value: $(formatparameter(param, value))")
        println("  Is discrete: $(isdiscrete(param))")
    end

    # Set a parameter
    if length(params) > 0
        println("\nSetting parameter 0 to 0.5...")
        setparameter!(plugin, params[1].id, 0.5)
        value = getparameter(plugin, params[1].id)
        println("  New value: $(formatparameter(params[1], value))")
    end

    # Cleanup
    close(plugin)
    println("\nDone!")
end

# Only run if this is the main script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
