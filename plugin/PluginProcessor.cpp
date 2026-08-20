#include "PluginProcessor.h"

#include <cmath>

#include "PluginParameters.h"
#include "PluginEditor.h"
#include "output_layouts.h"
#include "dwr3/dwr3.h"

AudioPluginAudioProcessor::AudioPluginAudioProcessor()
    : AudioProcessor(BusesProperties()
          .withInput("Input", AudioChannelSet::discreteChannels(parameters::src_max_channels), true)
          .withOutput("Output", AudioChannelSet::discreteChannels(parameters::mic_max_channels), true)
      ),
      ui_actual_size_ptr{&ui_actual_size[0], &ui_actual_size[1], &ui_actual_size[2]},
      apvts(AudioProcessorValueTreeState(*this, nullptr, "apvts", parameters::create_layout(ui_actual_size_ptr))) {
    // The room size parameters are listened for with the parameterChanged callback
    for (const auto &i: parameters::room_size_id) apvts.addParameterListener(i.getParamID(), this);
    // The OSC related parameters (enabled, port) are listened for with the parameterChanged callback
    apvts.addParameterListener(parameters::osc_enabled_id.getParamID(), this);
    apvts.addParameterListener(parameters::osc_port_id.getParamID(), this);

    // Fetch all atomics read during the audio thread processing update
    mic_layout_atom = apvts.getRawParameterValue(parameters::mic_layout_id.getParamID());
    for (int i = 0; i < 3; i++) {
        mic_pos_base_atom[i] = apvts.getRawParameterValue(parameters::mic_position_base_id[i].getParamID());
        mic_pos_offset_atom[i] = apvts.getRawParameterValue(parameters::mic_position_offset_id[i].getParamID());
    }
    mic_gain_fs_atom = apvts.getRawParameterValue(parameters::mic_db_fs_id.getParamID());
    // Fetch all atomics read during the audio thread processing update
    for (int j = 0; j < parameters::src_max_channels; j++) {
        for (int i = 0; i < 3; i++) {
            src_pos_atom[j][i] = apvts.getRawParameterValue(parameters::src_position_id[j][i].getParamID());
            src_pos_atom[j][i] = apvts.getRawParameterValue(parameters::src_position_id[j][i].getParamID());
        }
        src_gain_spl_atom[j] = apvts.getRawParameterValue(parameters::src_db_spl_1m_id[j].getParamID());
    }

    osc_enabled_atom = apvts.getRawParameterValue(parameters::osc_enabled_id.getParamID());
    osc_port_atom = apvts.getRawParameterValue(parameters::osc_port_id.getParamID());
    for (int i = 0; i < 3; i++)
        room_size_atom[i] = apvts.getRawParameterValue(parameters::room_size_id[i].getParamID());
    for (int i = 0; i < 6; i++)
        wall_material_atom[i] = apvts.getRawParameterValue(parameters::wall_material_id[i].getParamID());

    // Register the OSC callback
    osc_receiver.addListener(this);
}

AudioPluginAudioProcessor::~AudioPluginAudioProcessor() = default;

void AudioPluginAudioProcessor::prepareToPlay(const double sampleRate, const int samplesPerBlock) {
    // Get all the simulation parameters that are used to set up an instance
    {
        std::lock_guard guard(simulation_mutex);
        simulation_sample_rate = static_cast<int>(sampleRate);
        simulation_buffer_size = samplesPerBlock;
        // This gain correction factor has been obtained empirically so that, given a raw input signal with amplitude of 1,
        // the output at 1 meter of distance has roughly max amplitude of 1
        simulation_gain_correction = powf(static_cast<float>(sampleRate) / 16000.0f, 1.05f) * 90.0f;
        // simulation_node_distance is provided directly by instantiating the model later
        simulation_src_samples_transposed.resize(
            static_cast<size_t>(samplesPerBlock) * parameters::src_max_channels);
        simulation_mic_samples_transposed.resize(
            static_cast<size_t>(samplesPerBlock) * parameters::mic_max_channels);
        simulation_mic_positions_transposed.resize(
            static_cast<size_t>(samplesPerBlock) * parameters::mic_max_channels * 3);

        // If the simulation was already instantiated when this is called, then it needs to be reset
        if (simulation_running) {
            setSimulationStateInternal(false);
            setSimulationStateInternal(true);
        }
    }

    // Reset interpolation so that the first call to processBlock fetches the latest position into mic_pos_offset_prev
    reset_interpolation = true;
}

void AudioPluginAudioProcessor::releaseResources() {
}

bool AudioPluginAudioProcessor::isBusesLayoutSupported(const BusesLayout &layouts) const {
    return layouts.getMainOutputChannelSet().size() == parameters::src_max_channels &&
           layouts.getMainOutputChannelSet().size() == parameters::mic_max_channels;
}

void AudioPluginAudioProcessor::processBlock(AudioBuffer<float> &buffer,
                                             MidiBuffer &) {
    ScopedNoDenormals noDenormals;

    // Stores the number of actually used output channels, which depends on parameters::mic_layout_id, which
    // can be altered at any time
    int output_layout_count;

    {
        // Scope to limit the mutex lock to the minimum amount of time required
        std::lock_guard guard(simulation_mutex);

        // If the simulation is not running or there is a mismatch with the number of input and output channels, output silence
        if (!simulation_running || getTotalNumInputChannels() != parameters::src_max_channels ||
            getTotalNumOutputChannels() != parameters::mic_max_channels ||
            buffer.getNumSamples() != simulation_buffer_size) {
            buffer.clear();
            return;
        }

        // Buffer that stores the transposed source positions
        float src_positions_transposed[parameters::src_max_channels * 3];

        for (int j = 0; j < parameters::src_max_channels; j++) {
            // Apply gain to each source and write the transposed source samples to the model's input buffer

            // Standard gain formula for SPL
            const float input_gain = simulation_gain_correction * 0.00002f * powf(
                                         10.0f, src_gain_spl_atom[j]->load() * 0.05f);

            const auto b = buffer.getReadPointer(j);
            for (int n = 0; n < simulation_buffer_size; n++)
                simulation_src_samples_transposed[static_cast<size_t>(n * parameters::src_max_channels + j)] = b[n] * input_gain; // NOLINT(*-misplaced-widening-cast)

            // Fill transposed source positions
            for (int i = 0; i < 3; i++)
                src_positions_transposed[j * 3 + i] = src_pos_atom[j][i]->load();
        }

        {
            // Temporary variables to store microphone base position
            float mic_pos_base_curr[3];
            for (int i = 0; i < 3; i++) mic_pos_base_curr[i] = mic_pos_base_atom[i]->load();

            // Temporary variables to store microphone offset position
            float mic_pos_offset_curr[3];
            for (int i = 0; i < 3; i++) {
                mic_pos_offset_curr[i] = mic_pos_offset_atom[i]->load();
                // If reset_interpolation is set, initialize mic_pos_offset_prev with the latest position
                if (reset_interpolation) mic_pos_offset_prev[i] = mic_pos_offset_curr[i];
            }
            reset_interpolation = false;

            // Handle the output layout selection
            const auto selected_layout = static_cast<OUTPUT_LAYOUT_T>(mic_layout_atom->load());
            int _unused_output_layout_rs;
            // Layout coords stores the offsets in terms of nodes from the center coordinate, this is later scaled
            // to metric units using simulation_node_distance
            const int *output_layout_coords = output_layout_offsets(selected_layout, &output_layout_count,
                                                                    &_unused_output_layout_rs);

            // Fill the microphone positions output buffer
            for (int n = 0; n < simulation_buffer_size; n++) {
                // Interpolation percentage during the sample n
                const float interp = static_cast<float>(n) / simulation_buffer_size;
                for (int j = 0; j < output_layout_count; j++) {
                    for (int i = 0; i < 3; i++)
                        simulation_mic_positions_transposed[((n * parameters::mic_max_channels) + j) * 3 + i] =
                                mic_pos_base_curr[i] +
                                std::lerp(mic_pos_offset_prev[i], mic_pos_offset_curr[i], interp) +
                                static_cast<float>(output_layout_coords[j * 3 + i]) * simulation_node_distance;
                }

                for (int j = output_layout_count; j < parameters::mic_max_channels; j++) {
                    for (int i = 0; i < 3; i++)
                        simulation_mic_positions_transposed[((n * parameters::mic_max_channels) + j) * 3 + i] =
                                mic_pos_base_curr[i] + mic_pos_offset_curr[i];
                }
            }

            // Update mic_pos_offset_prev
            for (int i = 0; i < 3; i++)
                mic_pos_offset_prev[i] = mic_pos_offset_curr[i];
        }

        // Now that all required information is available, process the input samples with the model
        dwr3_process(simulation_dwr3_instance, simulation_src_samples_transposed.data(), src_positions_transposed,
                     simulation_mic_samples_transposed.data(), simulation_mic_positions_transposed.data());

        // dBFS offset
        const float output_spl_to_fs_correction = -(94.0f - mic_gain_fs_atom->load());

        for (int j = 0; j < output_layout_count; j++) {
            const auto b = buffer.getWritePointer(j);

            // Un-transpose the model's output and apply output amplification according to the provided amplification factor
            for (int n = 0; n < simulation_buffer_size; n++) {
                const float out_sample = simulation_mic_samples_transposed[static_cast<size_t>(n * parameters::mic_max_channels + j)]; // NOLINT(*-misplaced-widening-cast)
                const float output_sign = static_cast<float>(out_sample > 0.0f) - static_cast<float>(out_sample < 0.0f);
                const float output_spl = 20.0f * log10f(fabsf(out_sample) * 50000.0f); // From Pa to dB-SPL
                const float output_fs = output_spl + output_spl_to_fs_correction; // From dB-SPL to dB-FS
                b[n] = output_sign * powf(10.0f, output_fs * 0.05f); // Convert to scaled output
            }
        }
    }

    // Since not all output channels may be in use, clear the unused channels
    for (int j = output_layout_count; j < parameters::mic_max_channels; j++)
        buffer.clear(j, 0, simulation_buffer_size);
}

AudioProcessorEditor *AudioPluginAudioProcessor::createEditor() {
    return new AudioPluginAudioProcessorEditor(*this);
}

bool AudioPluginAudioProcessor::hasEditor() const {
    return true; // (change this to false if you choose to not supply an editor)
}

const String AudioPluginAudioProcessor::getName() const {
    return JucePlugin_Name;
}

bool AudioPluginAudioProcessor::acceptsMidi() const {
    return false;
}

bool AudioPluginAudioProcessor::producesMidi() const {
    return false;
}

bool AudioPluginAudioProcessor::isMidiEffect() const {
    return false;
}

double AudioPluginAudioProcessor::getTailLengthSeconds() const {
    return 0.0;
}

int AudioPluginAudioProcessor::getNumPrograms() {
    return 1;
}

int AudioPluginAudioProcessor::getCurrentProgram() {
    return 0;
}

void AudioPluginAudioProcessor::setCurrentProgram(int) {
}

const String AudioPluginAudioProcessor::getProgramName(int) {
    return {};
}

void AudioPluginAudioProcessor::changeProgramName(int, const String &) {
}

void AudioPluginAudioProcessor::getStateInformation(MemoryBlock &destData) {
    const auto state = apvts.copyState();
    const std::unique_ptr xml(state.createXml());
    copyXmlToBinary(*xml, destData);
}

void AudioPluginAudioProcessor::setStateInformation(const void *data, const int sizeInBytes) {
    if (const std::unique_ptr xmlState(getXmlFromBinary(data, sizeInBytes)); xmlState != nullptr)
        if (xmlState->hasTagName(apvts.state.getType()))
            apvts.replaceState(ValueTree::fromXml(*xmlState));
}

void AudioPluginAudioProcessor::parameterChanged(const String &parameterID, const float newValue) {
    // If the changed parameter is related to OSC, handle the connection
    if (parameterID == parameters::osc_enabled_id.getParamID() || parameterID == parameters::osc_port_id.getParamID()) {
        const bool enabled = apvts.getParameter(parameters::osc_enabled_id.getParamID())->getValue() != 0.0f;
        if (osc_connected && !enabled)
            oscDisconnect();
        else if (osc_connected || enabled) {
            const int port =
                    dynamic_cast<AudioParameterInt *>(apvts.getParameter(parameters::osc_port_id.getParamID()))->get();
            oscConnect(port);
        }
        return;
    }

    // Otherwise the parameters that have been handled are the size ones
    bool rescale = false;
    for (int i = 0; i < 3; i++)
        // Store the scaled value for the purpose of showing the updated UI coordinates
        if (parameterID == parameters::room_size_id[i].getParamID()) {
            ui_actual_size[i] = newValue;
            rescale = true;
            break;
        }
    // Dummy update of all room coordinate variables so that the UI pulls the updated scale
    if (rescale) {
        for (const auto &i: parameters::mic_position_base_id) {
            const auto param = apvts.getParameter(i.getParamID());
            param->setValue(param->getValue());
        }
        for (const auto &i: parameters::src_position_id) {
            for (const auto &j: i) {
                const auto param = apvts.getParameter(j.getParamID());
                param->setValue(param->getValue());
            }
        }
    }
}

void AudioPluginAudioProcessor::oscConnect(const int port) {
    if (osc_connected) osc_receiver.disconnect();
    osc_connected = osc_receiver.connect(port);
}

void AudioPluginAudioProcessor::oscDisconnect() {
    osc_receiver.disconnect();
    osc_connected = false;
}

void AudioPluginAudioProcessor::oscMessageReceived(const OSCMessage &message) {
    if (message.getAddressPattern().matches("/xyz") && message.size() == 3) {
        for (int i = 0; i < 3; i++)
            if (message[i].isFloat32()) {
                const auto param = apvts.getParameter(parameters::mic_position_offset_id[i].getParamID());
                param->setValueNotifyingHost(param->convertTo0to1(message[i].getFloat32()));
            }
    }
}

bool AudioPluginAudioProcessor::getSimulationState() {
    std::lock_guard guard(simulation_mutex);
    return simulation_running;
}

void AudioPluginAudioProcessor::setSimulationState(const bool on) {
    std::lock_guard guard(simulation_mutex);
    setSimulationStateInternal(on);
}

void AudioPluginAudioProcessor::setSimulationStateInternal(const bool on) {
    // Do nothing if the simulation is already in the provided state
    if (simulation_running == on) return;
    simulation_running = on;
    if (!simulation_running) {
        dwr3_destroy(simulation_dwr3_instance);
        simulation_dwr3_instance = nullptr;
        return;
    }

    // TODO: handle errors related to non-valid parameters more elegantly instead of exiting on error

    const dwr3_boundary_filter_t *boundary_filters[6] = {
        dwr3_boundary_filter_material(
            static_cast<DWR3_BOUNDARY_FILTER_MATERIAL_T>(wall_material_atom[0]->load()), simulation_sample_rate),
        dwr3_boundary_filter_material(
            static_cast<DWR3_BOUNDARY_FILTER_MATERIAL_T>(wall_material_atom[1]->load()), simulation_sample_rate),
        dwr3_boundary_filter_material(
            static_cast<DWR3_BOUNDARY_FILTER_MATERIAL_T>(wall_material_atom[2]->load()), simulation_sample_rate),
        dwr3_boundary_filter_material(
            static_cast<DWR3_BOUNDARY_FILTER_MATERIAL_T>(wall_material_atom[3]->load()), simulation_sample_rate),
        dwr3_boundary_filter_material(
            static_cast<DWR3_BOUNDARY_FILTER_MATERIAL_T>(wall_material_atom[4]->load()), simulation_sample_rate),
        dwr3_boundary_filter_material(
            static_cast<DWR3_BOUNDARY_FILTER_MATERIAL_T>(wall_material_atom[5]->load()), simulation_sample_rate),
    };

    simulation_dwr3_instance = dwr3_create(
        room_size_atom[0]->load(), room_size_atom[1]->load(), room_size_atom[2]->load(),
        boundary_filters, simulation_sample_rate, simulation_buffer_size,
        parameters::src_max_channels, parameters::mic_max_channels,
        DWR3_INTERPOLATION_LINEAR, &simulation_node_distance, nullptr, nullptr, nullptr, nullptr, nullptr
    );
}

AudioProcessor * JUCE_CALLTYPE createPluginFilter() {
    return new AudioPluginAudioProcessor();
}
