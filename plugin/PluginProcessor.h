#pragma once

#include <juce_osc/juce_osc.h>
#include <JuceHeader.h>

#include "PluginParameters.h"

class AudioPluginAudioProcessor final :
        public AudioProcessor,
        AudioProcessorValueTreeState::Listener,
        OSCReceiver::Listener<OSCReceiver::RealtimeCallback> {
public:
    AudioPluginAudioProcessor();

    ~AudioPluginAudioProcessor() override;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;

    void releaseResources() override;

    // ReSharper disable once CppOverrideWithDifferentVisibility
    bool isBusesLayoutSupported(const BusesLayout &layouts) const override;

    void processBlock(AudioBuffer<float> &, MidiBuffer &) override;

    using AudioProcessor::processBlock;

    // ReSharper disable once CppOverrideWithDifferentVisibility
    AudioProcessorEditor *createEditor() override;

    bool hasEditor() const override;

    const String getName() const override;

    bool acceptsMidi() const override;

    bool producesMidi() const override;

    bool isMidiEffect() const override;

    double getTailLengthSeconds() const override;

    int getNumPrograms() override;

    int getCurrentProgram() override;

    void setCurrentProgram(int index) override;

    const String getProgramName(int index) override;

    void changeProgramName(int index, const String &newName) override;

    void getStateInformation(MemoryBlock &destData) override;

    void setStateInformation(const void *data, int sizeInBytes) override;

    void parameterChanged(const String &parameterID, float newValue) override;

    void oscMessageReceived(const OSCMessage &message) override;

    // Utility function for setting up the OSC connection
    void oscConnect(int port);

    // Utility function for ending the OSC connection
    void oscDisconnect();

    // Utility function used by the UI to know if the simulation is running
    bool getSimulationState();

    // Utility function used by the UI to start/stop the simulation
    void setSimulationState(bool on);

private:
    // Internal implementation of setSimulationState, which assumes that simulation_mutex is already locked
    void setSimulationStateInternal(bool on);

    // Used to protect the simulation related resources from being handled my the UI and audio thread at the same time
    std::mutex simulation_mutex;
    // Indicates if the simulation is running or not, MUST BE ACCESSED WITH simulation_mutex
    bool simulation_running = false;
    // Stores the sample rate for which the simulation is configured, MUST BE ACCESSED WITH simulation_mutex
    int simulation_sample_rate = 100;
    // Stores the buffer size for which the simulation is configured, MUST BE ACCESSED WITH simulation_mutex
    int simulation_buffer_size = 128;
    // Stores the gain correction dependent on simulation_sample_rate, MUST BE ACCESSED WITH simulation_mutex
    float simulation_gain_correction = 0;
    // Stores the node distance dependent on simulation_sample_rate, MUST BE ACCESSED WITH simulation_mutex
    float simulation_node_distance = 0;
    // Model instance, MUST BE ACCESSED WITH simulation_mutex
    void *simulation_dwr3_instance = nullptr;
    // Buffers for model I/O which depend on simulation_buffer_size, MUST BE ACCESSED WITH simulation_mutex
    std::vector<float> simulation_src_samples_transposed;
    std::vector<float> simulation_mic_samples_transposed;
    std::vector<float> simulation_mic_positions_transposed;

    // Parameter set from the UI thread in order to provide the workaround for scaling coordinates on the UI via the
    // APVTS, see parameters::create_layout for more information
    float ui_actual_size[3] = {1, 1, 1};
    // Pointers to the ui_actual_size elements, see ui_actual_size for info
    float *ui_actual_size_ptr[3]; // Initializated in constructor

public:
    // AudioProcessorValueTreeState instance, public since it is accessed by the UI via a reference to the processor
    AudioProcessorValueTreeState apvts;

private:
    // OSC handler
    OSCReceiver osc_receiver;
    // Keeps track if the osc_receiver is connected or not
    bool osc_connected = false;

    // Flag set whenever mic offset position interpolation needs to be reset
    bool reset_interpolation = true;
    // Previous mic offset position used for interpolation, must be to the latest position set whenever reset_interpolation is set to true
    float mic_pos_offset_prev[3] = {};

    // Parameters atomics
    std::atomic<float> *mic_layout_atom;
    std::atomic<float> *mic_pos_base_atom[3];
    std::atomic<float> *mic_pos_offset_atom[3];
    std::atomic<float> *mic_gain_fs_atom;
    std::atomic<float> *src_gain_spl_atom[parameters::src_max_channels];
    std::atomic<float> *src_pos_atom[parameters::src_max_channels][3];

    std::atomic<float> *osc_enabled_atom;
    std::atomic<float> *osc_port_atom;
    std::atomic<float> *room_size_atom[3];
    std::atomic<float> *wall_material_atom[6];

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AudioPluginAudioProcessor)
};
