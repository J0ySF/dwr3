#include "PluginParameters.h"

#include "dwr3/dwr3.h"
#include "output_layouts.h"

// TODO: consider more sensible defaults
constexpr float db_spl_min_val = 0;
constexpr float db_spl_max_val = 100;
constexpr float db_spl_default_val = 94;
constexpr float db_fs_min_val = -30;
constexpr float db_fs_max_val = 0;
constexpr float db_fs_default_val = -26;

constexpr float room_side_min_val = 1;
constexpr float room_side_max_val = 6;

namespace parameters {
    const std::string axis_order_suffix[3] = {"x", "y", "z"};
    const std::string wall_order_suffix[6] = {"x-", "x+", "y-", "y+", "z-", "z+"};

    const ParameterID room_size_id[3] = {
        "room_size_" + axis_order_suffix[0],
        "room_size_" + axis_order_suffix[1],
        "room_size_" + axis_order_suffix[2]
    };
    const ParameterID wall_material_id[6] = {
        "wall_material_" + wall_order_suffix[0],
        "wall_material_" + wall_order_suffix[1],
        "wall_material_" + wall_order_suffix[2],
        "wall_material_" + wall_order_suffix[3],
        "wall_material_" + wall_order_suffix[4],
        "wall_material_" + wall_order_suffix[5]
    };
    const ParameterID mic_layout_id = "mic_layout";
    const ParameterID mic_position_base_id[3] = {
        "mic_position_base_" + axis_order_suffix[0],
        "mic_position_base_" + axis_order_suffix[1],
        "mic_position_base_" + axis_order_suffix[2]
    };
    const ParameterID mic_position_offset_id[3] = {
        "mic_position_offset_" + axis_order_suffix[0],
        "mic_position_offset_" + axis_order_suffix[1],
        "mic_position_offset_" + axis_order_suffix[2]
    };
    const ParameterID mic_db_fs_id = "mic_db_fs";
    const ParameterID src_position_id[src_max_channels][3] = {
        {
            "src_1_position_" + axis_order_suffix[0], "src_1_position_" + axis_order_suffix[1],
            "src_1_position_" + axis_order_suffix[2],
        },
        {
            "src_2_position_" + axis_order_suffix[0], "src_2_position_" + axis_order_suffix[1],
            "src_2_position_" + axis_order_suffix[2],
        },
        {
            "src_3_position_" + axis_order_suffix[0], "src_3_position_" + axis_order_suffix[1],
            "src_3_position_" + axis_order_suffix[2],
        },
        {
            "src_4_position_" + axis_order_suffix[0], "src_4_position_" + axis_order_suffix[1],
            "src_4_position_" + axis_order_suffix[2],
        }
    };
    const ParameterID src_db_spl_1m_id[src_max_channels] = {
        "src_1_db_spl_1m",
        "src_2_db_spl_1m",
        "src_3_db_spl_1m",
        "src_4_db_spl_1m",
    };
    const ParameterID osc_enabled_id = "osc_enabled";
    const ParameterID osc_port_id = "osc_port";

    // Auto convert id to sensible "pretty name" to show outside the plugin
    static std::string prettify_id(const ParameterID &id) {
        bool capitalize_next = true;
        std::string str = id.getParamID().toStdString();
        for (size_t i = 0; i < str.length(); ++i) {
            if (str[i] == '_') {
                str[i] = ' ';
                capitalize_next = true;
            } else if (capitalize_next && std::isalpha(static_cast<unsigned char>(str[i]))) {
                str[i] = std::toupper(static_cast<unsigned char>(str[i])); // NOLINT(*-narrowing-conversions)
                capitalize_next = false;
            } else {
                capitalize_next = false;
            }
        }
        return str;
    }

    // Create parameters for an xyz triplet, used for positions, mic offset and room size
    static void create_layout_coord(AudioProcessorValueTreeState::ParameterLayout &layout,
                                    const ParameterID id[3], float *actual_size[3],
                                    const float min = 0.0f, const float max = 1.0f, const float default_ = 0.5f,
                                    const bool normalized_scale = true) {
        for (int i = 0; i < 3; ++i) {
            layout.add(std::make_unique<AudioParameterFloat>(
                id[i], prettify_id(id[i]),
                NormalisableRange(min, max), default_,
                AudioParameterFloatAttributes()
                .withAutomatable(true)
                // normalized_scale is used to check if this is a static ranged parameter (mic offset, room size) or if the range
                // varies dynamically with room size (all position parameters)
                // These functions perform scaling and unscaling
                .withStringFromValueFunction([actual_size, i, normalized_scale](const float v, int) {
                    std::ostringstream oss;
                    oss << std::fixed << std::setprecision(2) << v * (!normalized_scale ? 1.0f : *actual_size[i]);
                    return oss.str();
                })
                .withValueFromStringFunction([actual_size, i, normalized_scale](const String &s) {
                    std::stringstream ss(s.toStdString());
                    float d;
                    ss >> d;
                    return d / (!normalized_scale ? 1.0f : *actual_size[i]);
                })));
        }
    }

    AudioProcessorValueTreeState::ParameterLayout create_layout(float *actual_size[3]) {
        auto layout = AudioProcessorValueTreeState::ParameterLayout();

        for (int i = 0; i < 3; ++i)
            layout.add(std::make_unique<AudioParameterFloat>(
                room_size_id[i], prettify_id(room_size_id[i]),
                NormalisableRange(room_side_min_val, room_side_max_val, 0.1f),
                *actual_size[i], AudioParameterFloatAttributes().withAutomatable(false).withMeta(false)));

        StringArray materials_names = {};
        for (int i = 0; i < DWR3_BOUNDARY_FILTER_MATERIAL_COUNT; i++)
            materials_names.add(dwr3_boundary_filter_name(static_cast<DWR3_BOUNDARY_FILTER_MATERIAL_T>(i)));
        for (const auto &i: wall_material_id)
            layout.add(std::make_unique<AudioParameterChoice>(
                i, prettify_id(i), materials_names,
                1, AudioParameterChoiceAttributes().withAutomatable(false).withMeta(false)));

        StringArray mic_layouts_names = {};
        for (int i = 0; i < OUTPUT_LAYOUT_COUNT; i++)
            mic_layouts_names.add(output_layout_name(static_cast<OUTPUT_LAYOUT_T>(i)));
        layout.add(std::make_unique<AudioParameterChoice>(
            mic_layout_id, prettify_id(mic_layout_id), mic_layouts_names,
            1, AudioParameterChoiceAttributes().withAutomatable(false).withMeta(false)));

        create_layout_coord(layout, mic_position_base_id, actual_size);
        create_layout_coord(layout, mic_position_offset_id, actual_size, -mic_position_offset_max_extent,
                            mic_position_offset_max_extent, 0, false);

        layout.add(std::make_unique<AudioParameterFloat>(
            mic_db_fs_id, prettify_id(mic_db_fs_id), NormalisableRange(db_fs_min_val, db_fs_max_val, 0.1f),
            db_fs_default_val, AudioParameterFloatAttributes().withAutomatable(false)));

        for (const auto &i: src_position_id) create_layout_coord(layout, i, actual_size);
        for (const auto &i: src_db_spl_1m_id)
            layout.add(std::make_unique<AudioParameterFloat>(
                i, prettify_id(i), NormalisableRange(db_spl_min_val, db_spl_max_val, 0.1f),
                db_spl_default_val, AudioParameterFloatAttributes().withAutomatable(false)));

        layout.add(std::make_unique<AudioParameterBool>(osc_enabled_id, prettify_id(osc_enabled_id), false,
                                                        AudioParameterBoolAttributes().withAutomatable(false).withMeta(
                                                            false)));
        layout.add(std::make_unique<AudioParameterInt>(osc_port_id, prettify_id(osc_port_id), 0, 9999, osc_port_default,
                                                       AudioParameterIntAttributes().withAutomatable(false).withMeta(
                                                           false)));

        return layout;
    }
}
