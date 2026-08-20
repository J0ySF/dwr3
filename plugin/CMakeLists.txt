cmake_minimum_required(VERSION 3.17)

dwr3_variant("-pic") # Compile dwr3 with position independent code on to avoid linker errors
set_target_properties(dwr3-pic PROPERTIES POSITION_INDEPENDENT_CODE ON)

juce_add_plugin(dwr3-plugin
        COMPANY_NAME "J0ySF"
        IS_SYNTH FALSE
        NEEDS_MIDI_INPUT FALSE
        NEEDS_MIDI_OUTPUT FALSE
        IS_MIDI_EFFECT FALSE
        EDITOR_WANTS_KEYBOARD_FOCUS FALSE
        COPY_PLUGIN_AFTER_BUILD TRUE
        PLUGIN_MANUFACTURER_CODE JSFx
        PLUGIN_CODE Dwr3
        FORMATS VST3
        PRODUCT_NAME "DWR3 demo"
        NEEDS_WEB_BROWSER FALSE
        NEEDS_CURL FALSE)
set_property(TARGET dwr3-plugin PROPERTY CXX_STANDARD 23)

juce_generate_juce_header(dwr3-plugin)

target_sources(dwr3-plugin
        PRIVATE
        PluginParameters.cpp
        PluginEditor.cpp
        PluginProcessor.cpp
        output_layouts.c)

target_compile_definitions(dwr3-plugin
        PUBLIC
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        JUCE_VST3_CAN_REPLACE_VST2=0)

target_link_libraries(dwr3-plugin
        PRIVATE
        juce::juce_audio_utils
        PUBLIC
        juce::juce_recommended_config_flags
        juce::juce_recommended_lto_flags
        juce::juce_recommended_warning_flags
        juce::juce_osc
        dwr3-pic) # Use the version with PIC on
