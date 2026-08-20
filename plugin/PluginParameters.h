#pragma once

#include <JuceHeader.h>

namespace parameters {
    extern const std::string axis_order_suffix[3];
    extern const std::string wall_order_suffix[6];

    extern const ParameterID room_size_id[3];
    extern const ParameterID wall_material_id[6];

    constexpr int mic_max_channels = 32;
    constexpr float mic_position_offset_max_extent = 1.0f;
    extern const ParameterID mic_layout_id;
    extern const ParameterID mic_position_base_id[3];
    extern const ParameterID mic_position_offset_id[3];
    extern const ParameterID mic_db_fs_id;

    constexpr int src_max_channels = 4;
    extern const ParameterID src_position_id[src_max_channels][3];
    extern const ParameterID src_db_spl_1m_id[src_max_channels];

    constexpr int osc_port_default = 9001;
    extern const ParameterID osc_enabled_id;
    extern const ParameterID osc_port_id;

    /// Creates the parameters layout for all parameters in this namespace
    /// actual_size stores pointers to the current room scaling factor, which is stored in the processor: this is done
    /// to show the dynamic range on all coordinates when the room is scaled. This workaround is done since there is no
    /// "native" support for this functionality in the current version of JUCE, and it should be safe since the APVTS
    /// instance is contained in the PluginProcessor, so the pointers provided have the same lifetime as the APVTS.
    AudioProcessorValueTreeState::ParameterLayout create_layout(float *actual_size[3]);
}
