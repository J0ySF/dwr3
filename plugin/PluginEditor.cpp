#include "PluginProcessor.h"
#include "PluginEditor.h"
#include "output_layouts.h"
#include "dwr3/dwr3.h"

Rectangle<int> group_component::getLocalBounds() const noexcept {
    return GroupComponent::getLocalBounds().reduced(elem_spacing).withTrimmedTop(elem_spacing);
}

xyz_ui::xyz_ui(AudioProcessorValueTreeState &apvts, const ParameterID params[3], const bool scale_with_size,
               const bool is_size) : _apvts(apvts) {
    for (int i = 0; i < 3; i++) {
        this->_params[i] = params[i];
        constexpr char label_text[3] = {'X', 'Y', 'Z'};
        addAndMakeVisible(labels[i]);
        addAndMakeVisible(sliders[i]);
        labels[i].setText(std::string("") + label_text[i] + ": ", dontSendNotification);
        labels[i].attachToComponent(&sliders[i], true);
        sliders[i].setTextBoxStyle(Slider::TextBoxLeft, false, 60, elem_height);
        sliders[i].setTextValueSuffix(" m");
        sliders[i].setColour(Slider::trackColourId, Colours::transparentBlack);
        slider_attachments[i] = std::make_unique<AudioProcessorValueTreeState::SliderAttachment>(
            apvts, params[i].getParamID(), sliders[i]);
        if (is_size)
            sliders[i].setSliderStyle(Slider::IncDecButtons);
    }
    if (scale_with_size)
        for (const auto &i: parameters::room_size_id)
            apvts.addParameterListener(i.getParamID(), this);
}

xyz_ui::~xyz_ui() {
    for (const auto &i: parameters::room_size_id)
        _apvts.removeParameterListener(i.getParamID(), this);
}

void xyz_ui::resized() {
    auto bounds = getLocalBounds();
    for (int i = 0; i < 3; i++) {
        auto local_bounds = bounds.removeFromTop(elem_height);
        labels[i].setBounds(local_bounds.removeFromLeft(30));
        sliders[i].setBounds(local_bounds);
        bounds.removeFromTop(elem_spacing);
    }
}

void xyz_ui::parameterChanged(const String &parameterID, const float) {
    for (int i = 0; i < 3; i++)
        if (parameterID == parameters::room_size_id[i].getParamID()) {
            slider_attachments[i] = nullptr;
            slider_attachments[i] = std::make_unique<AudioProcessorValueTreeState::SliderAttachment>(
                _apvts, _params[i].getParamID(), sliders[i]);
            return;
        }
}

void xyz_ui::set_enabled(const bool enabled) {
    for (auto &slider: sliders) slider.setEnabled(enabled);
}

db_ui::db_ui(AudioProcessorValueTreeState &apvts, const ParameterID &param, const std::string &unit,
             Slider::TextEntryBoxPosition lab_pos) {
    addAndMakeVisible(slider);
    slider.setTextBoxStyle(lab_pos, false, 120, elem_height);
    slider.setTextValueSuffix(" " + unit);
    slider.setColour(Slider::trackColourId, Colours::transparentBlack);
    slider_attachment = std::make_unique<AudioProcessorValueTreeState::SliderAttachment>(
        apvts, param.getParamID(), slider);
}

void db_ui::resized() {
    slider.setBounds(getLocalBounds());
}

materials_ui::materials_ui(AudioProcessorValueTreeState &apvts) {
    setText("Boundary Materials");
    for (int i = 0; i < 6; i++) {
        addAndMakeVisible(labels[i]);
        addAndMakeVisible(combo_boxes[i]);
        labels[i].setText(parameters::wall_order_suffix[i], dontSendNotification);
        labels[i].attachToComponent(&combo_boxes[i], true);
        for (int j = 0; j < DWR3_BOUNDARY_FILTER_MATERIAL_COUNT; j++)
            combo_boxes[i].addItem(dwr3_boundary_filter_name(static_cast<DWR3_BOUNDARY_FILTER_MATERIAL_T>(j)), j + 1);
        combo_boxes[i].setSelectedItemIndex(
            apvts.getParameterAsValue(parameters::wall_material_id[i].getParamID()).getValue());
        combo_boxes_attachments[i] = std::make_unique<AudioProcessorValueTreeState::ComboBoxAttachment>(
            apvts, parameters::wall_material_id[i].getParamID(), combo_boxes[i]);
    }
}

void materials_ui::resized() {
    auto bounds = getLocalBounds();
    const int colW = (bounds.getWidth() - elem_spacing * 1 - 2 * elem_spacing * 2) / 2;
    const int colH = (bounds.getHeight() - elem_spacing * 2) / 3;
    Rectangle<int> rows[3];
    rows[0] = bounds.removeFromTop(colH);
    bounds.removeFromTop(elem_spacing);
    rows[1] = bounds.removeFromTop(colH);
    bounds.removeFromTop(elem_spacing);
    rows[2] = bounds;
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 2; j++) {
            rows[i].removeFromLeft(elem_spacing * 3);
            combo_boxes[i * 2 + j].setBounds(rows[i].removeFromLeft(colW));
        }
    }
}

void materials_ui::set_enabled(const bool enabled) {
    for (auto &combo: combo_boxes) combo.setEnabled(enabled);
}

enclosure_ui::enclosure_ui(AudioPluginAudioProcessor &processor) : size(processor.apvts, parameters::room_size_id, false,
                                                                        true), materials(processor.apvts),
                                                                   processorRef(processor) {
    setText("Enclosure Settings");
    addAndMakeVisible(size);
    size.setText("Size");
    addAndMakeVisible(materials);
    is_playing = false;

    addAndMakeVisible(start_toggle);
    start_toggle.setButtonText("Running");
    start_toggle.setToggleState(processor.getSimulationState(), dontSendNotification);
    start_toggle.onStateChange = [&] {
        const bool enabled = start_toggle.getToggleState();
        size.set_enabled(!enabled);
        materials.set_enabled(!enabled);
        processor.setSimulationState(enabled);
    };
    const bool enabled = processor.getSimulationState();
    size.set_enabled(!enabled);
    materials.set_enabled(!enabled);
}

void enclosure_ui::resized() {
    auto bounds = getLocalBounds();
    size.setBounds(bounds.removeFromLeft(160));
    bounds.removeFromLeft(elem_spacing);
    start_toggle.setBounds(bounds.removeFromRight(80));
    bounds.removeFromRight(elem_spacing);
    materials.setBounds(bounds);
}

input_ui::input_ui(AudioProcessorValueTreeState &apvts) {
    setText("Input Sources");
    addAndMakeVisible(scroll);
    addAndMakeVisible(viewport);
    viewport.setViewedComponent(&scroll, false);
    for (int i = 0; i < parameters::src_max_channels; i++) {
        positions[i] = std::make_unique<xyz_ui>(apvts, parameters::src_position_id[i]);
        scroll.addAndMakeVisible(positions[i].get());
        positions[i]->setText("Source " + std::to_string(i + 1) + " position");
        amplifications[i] = std::make_unique<db_ui>(apvts, parameters::src_db_spl_1m_id[i], "dB-SPL@1m",
                                                    Slider::TextBoxBelow);
        scroll.addAndMakeVisible(amplifications[i].get());
        amplifications[i]->setText("Source " + std::to_string(i + 1) + " level");
    }
}

void input_ui::resized() {
    const auto bounds = getLocalBounds();
    scroll.setBounds(bounds.getX(), bounds.getY(), bounds.getWidth() - elem_spacing,
                     xyz_ui::height * parameters::src_max_channels + elem_spacing * 3);
    viewport.setBounds(getLocalBounds());
    for (int i = 0; i < parameters::src_max_channels; i++) {
        auto localBounds =
                Rectangle(0, xyz_ui::height * i, bounds.getWidth() - elem_spacing, xyz_ui::height);
        positions[i]->setBounds(localBounds.removeFromLeft(200));
        localBounds.removeFromLeft(elem_spacing / 2);
        amplifications[i]->setBounds(localBounds);
    }
}

osc_ui::osc_ui(AudioProcessorValueTreeState &apvts) : enabled_toggle_attachment(
                                                          apvts, parameters::osc_enabled_id.getParamID(), enabled_toggle),
                                                      port_slider_attachment(
                                                          apvts, parameters::osc_port_id.getParamID(), port_slider) {
    setText("OSC Offset Control Port");
    addAndMakeVisible(enabled_toggle);
    addAndMakeVisible(port_slider);
    port_slider.setSliderStyle(Slider::IncDecButtons);
}

void osc_ui::resized() {
    auto bounds = getLocalBounds();
    auto x_bounds = bounds.removeFromTop(elem_height);
    enabled_toggle.setBounds(x_bounds.removeFromLeft(30));
    port_slider.setBounds(x_bounds);
}

output_ui::output_ui(AudioProcessorValueTreeState &apvts) : layout_combo_box_attachment(
                                                                apvts, parameters::mic_layout_id.getParamID(),
                                                                layout_combo_box),
                                                            position_base(apvts, parameters::mic_position_base_id),
                                                            position_offset(
                                                                apvts, parameters::mic_position_offset_id, false),
                                                            amplification(
                                                                apvts, parameters::mic_db_fs_id, "dB-FS",
                                                                Slider::TextBoxLeft),
                                                            osc(apvts) {
    setText("Ambisonic Microphone Output");
    addAndMakeVisible(layout_label);
    addAndMakeVisible(layout_combo_box);
    layout_label.setText("Layout: ", dontSendNotification);
    layout_label.attachToComponent(&layout_combo_box, true);
    for (int i = 0; i < OUTPUT_LAYOUT_COUNT; i++)
        layout_combo_box.addItem(output_layout_name(static_cast<OUTPUT_LAYOUT_T>(i)), i + 1);
    layout_combo_box.setSelectedItemIndex(apvts.getParameterAsValue(parameters::mic_layout_id.getParamID()).getValue());
    addAndMakeVisible(position_base);
    position_base.setText("Position");
    addAndMakeVisible(position_offset);
    position_offset.setText("Offset");
    addAndMakeVisible(amplification);
    amplification.setText("Sensitivity");
    addAndMakeVisible(osc);
}

void output_ui::resized() {
    auto bounds = getLocalBounds();
    auto layout_bounds = bounds.removeFromTop(elem_height);
    layout_label.setBounds(layout_bounds.removeFromLeft(55));
    layout_combo_box.setBounds(layout_bounds);
    bounds.removeFromTop(elem_spacing);
    position_base.setBounds(bounds.removeFromTop(xyz_ui::height));
    bounds.removeFromTop(elem_spacing);
    position_offset.setBounds(bounds.removeFromTop(xyz_ui::height));
    bounds.removeFromTop(elem_spacing);
    amplification.setBounds(bounds.removeFromTop(db_ui::min_height));
    bounds.removeFromTop(elem_spacing);
    osc.setBounds(bounds);
}

main_ui::main_ui(AudioPluginAudioProcessor &processor) : enclosure(processor), input(processor.apvts),
                                                         output(processor.apvts) {
    addAndMakeVisible(enclosure);
    addAndMakeVisible(input);
    addAndMakeVisible(output);
}

void main_ui::resized() {
    auto bounds = getLocalBounds();
    enclosure.setBounds(bounds.removeFromTop(enclosure_ui::height));
    input.setBounds(bounds.removeFromLeft(input_ui::width));
    output.setBounds(bounds);
}

AudioPluginAudioProcessorEditor::AudioPluginAudioProcessorEditor(
    AudioPluginAudioProcessor &p) : AudioProcessorEditor(p), processorRef(p), ui(main_ui(p)) {
    setSize(main_ui::min_width, main_ui::min_height);
    setResizeLimits(main_ui::min_width, main_ui::min_height,
                    main_ui::min_width, main_ui::min_height);
    setResizable(false, false);
    centreWithSize(getWidth(), getHeight());
    addAndMakeVisible(ui);
}

AudioPluginAudioProcessorEditor::~AudioPluginAudioProcessorEditor() = default;

void AudioPluginAudioProcessorEditor::paint(Graphics &g) {
    const auto colour = getLookAndFeel().findColour(ResizableWindow::backgroundColourId);
    g.fillAll(colour);
}

void AudioPluginAudioProcessorEditor::resized() {
    ui.setSize(getWidth(), getHeight());
}
