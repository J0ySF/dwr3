#pragma once

#include "PluginParameters.h"
#include "PluginProcessor.h"

// TODO: improve implementation of layout and overall code structure

static constexpr int elem_height = 20;
static constexpr int elem_spacing = 10;

// Custom group component that automatically adds elem_spacing around itself
class group_component : public GroupComponent {
public:
    static constexpr int margin_height = elem_spacing * 3;

    // ReSharper disable once CppHidingFunction
    [[nodiscard]] Rectangle<int> getLocalBounds() const noexcept;
};

class xyz_ui final : public group_component, AudioProcessorValueTreeState::Listener {
public:
    static constexpr int height = elem_height * 3 + elem_spacing * 2 + margin_height;

    Label labels[3];
    Slider sliders[3];
    std::unique_ptr<AudioProcessorValueTreeState::SliderAttachment> slider_attachments[3];

    explicit xyz_ui(AudioProcessorValueTreeState &apvts, const ParameterID params[3],
                    bool scale_with_size = true, bool is_size = false);

    ~xyz_ui() override;

    void resized() override;

    void parameterChanged(const String &parameterID, float val) override;

    void set_enabled(bool enabled);

private:
    AudioProcessorValueTreeState &_apvts;
    ParameterID _params[3];
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(xyz_ui)
};

class db_ui final : public group_component {
public:
    static constexpr int min_height = 50.0f;

    Slider slider;
    std::unique_ptr<AudioProcessorValueTreeState::SliderAttachment> slider_attachment;

    explicit db_ui(AudioProcessorValueTreeState &apvts, const ParameterID &param, const std::string &unit,
                   Slider::TextEntryBoxPosition lab_pos);

    void resized() override;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(db_ui)
};

class materials_ui final : public group_component {
public:
    Label labels[6];
    ComboBox combo_boxes[6];
    std::unique_ptr<AudioProcessorValueTreeState::ComboBoxAttachment> combo_boxes_attachments[6];

    explicit materials_ui(AudioProcessorValueTreeState &apvts);

    void resized() override;

    void set_enabled(bool enabled);

private:
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(materials_ui)
};

class enclosure_ui final : public group_component {
public:
    static constexpr int height = xyz_ui::height + margin_height;

    xyz_ui size;
    materials_ui materials;
    ToggleButton start_toggle;

    explicit enclosure_ui(AudioPluginAudioProcessor &);

    void resized() override;

private:
    AudioPluginAudioProcessor &processorRef;
    bool is_playing;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(enclosure_ui)
};

class input_ui final : public group_component {
public:
    static constexpr int width = 400.0f;

    std::unique_ptr<xyz_ui> positions[parameters::src_max_channels];
    std::unique_ptr<db_ui> amplifications[parameters::src_max_channels];

    explicit input_ui(AudioProcessorValueTreeState &apvts);

    void resized() override;

private:
    Viewport viewport;
    Component scroll;
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(input_ui)
};

class osc_ui final : public group_component {
public:
    static constexpr int height = elem_height + margin_height;

    ToggleButton enabled_toggle;
    AudioProcessorValueTreeState::ButtonAttachment enabled_toggle_attachment;
    Slider port_slider;
    AudioProcessorValueTreeState::SliderAttachment port_slider_attachment;

    explicit osc_ui(AudioProcessorValueTreeState &apvts);

    void resized() override;

private:
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(osc_ui)
};

class output_ui final : public group_component {
public:
    static constexpr int width = 280.0f;
    static constexpr int height =
            elem_height + xyz_ui::height * 2 + osc_ui::height + elem_spacing * 4 + margin_height + db_ui::min_height;

    Label layout_label;
    ComboBox layout_combo_box;
    AudioProcessorValueTreeState::ComboBoxAttachment layout_combo_box_attachment;
    xyz_ui position_base, position_offset;
    db_ui amplification;
    osc_ui osc;

    explicit output_ui(AudioProcessorValueTreeState &apvts);

    void resized() override;

private:
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(output_ui)
};

class main_ui final : public Component {
public:
    static constexpr int min_width = input_ui::width + output_ui::width;
    static constexpr int min_height = enclosure_ui::height + output_ui::height;

    explicit main_ui(AudioPluginAudioProcessor &);

    void resized() override;

private:
    enclosure_ui enclosure;
    input_ui input;
    output_ui output;
    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(main_ui)
};

class AudioPluginAudioProcessorEditor final : public AudioProcessorEditor {
public:
    explicit AudioPluginAudioProcessorEditor(AudioPluginAudioProcessor &);

    ~AudioPluginAudioProcessorEditor() override;

    void paint(Graphics &) override;

    void resized() override;

private:
    AudioPluginAudioProcessor &processorRef;
    main_ui ui;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AudioPluginAudioProcessorEditor)
};
