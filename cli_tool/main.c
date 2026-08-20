#include <math.h>
#include <stdlib.h>

#include <tinywav.h>
#include <dwr3/dwr3.h>

#define BUFFER_SIZE 128

static int _mini(const int a, const int b) { return a < b ? a : b; }

int main(const int argc, char **argv) {
    if (argc != 15 && argc != 16) {
        fprintf(stderr, "Usage: dwr3_cli"
                " <x size> <y size> <z size>"
                " <source x> <source y> <source z>"
                " <receiver x> <receiver y> <receiver z>"
                " <source input file (.wav)> <receiver output file (.wav)>"
                " <source input file peak dB-SPL @ 1m> <receiver output dB-FS sensitivity>"
                " <receiver interpolation (0=off or 1=on)> <n. of processed chunks (OPTIONAL)>"
                "\n");
        exit(EXIT_FAILURE);
    }
    int arg_index = 1;

    const float s_x = (float) atof(argv[arg_index++]);
    const float s_y = (float) atof(argv[arg_index++]);
    const float s_z = (float) atof(argv[arg_index++]);
    if (s_x <= 0 || s_y <= 0 || s_z <= 0) {
        fprintf(stderr, "Invalid dimensions! Each axis's dimension must be greater than 0\n");
        exit(EXIT_FAILURE);
    }

    const float src_x = atof(argv[arg_index++]);
    const float src_y = atof(argv[arg_index++]);
    const float src_z = atof(argv[arg_index++]);
    const float lst_x = atof(argv[arg_index++]);
    const float lst_y = atof(argv[arg_index++]);
    const float lst_z = atof(argv[arg_index++]);

    const char *input_path = argv[arg_index++];
    const char *output_path = argv[arg_index++];

    const float input_gain = 0.00002f * powf(10.0f, (float) atof(argv[arg_index++]) * 0.05f);
    const float output_spl_to_fs_correction = -(94.0f - (float) atof(argv[arg_index++]));

    const bool output_interpolation = atoi(argv[arg_index++]);
    int input_chunks_override = -1;
    if (argc == 16) input_chunks_override = atoi(argv[arg_index++]);

    int f_s;
    float *input_buffer;
    int input_chunks;
    {
        TinyWav tw;
        if (tinywav_open_read(&tw, input_path, TW_INLINE)) {
            fprintf(stderr, "Error opening input file!\n");
            exit(EXIT_FAILURE);
        }
        if (tw.numChannels != 1 || tw.sampFmt != TW_FLOAT32) {
            fprintf(stderr, "Invalid input file format! The file must be of 1 channel, Float32, .wav format\n");
            tinywav_close_read(&tw);
            exit(EXIT_FAILURE);
        }
        f_s = (int) tw.h.SampleRate;

        if (input_chunks_override <= 0) {
            input_chunks = (tw.numFramesInHeader + BUFFER_SIZE - 1) / BUFFER_SIZE;
        } else {
            input_chunks = input_chunks_override;
        }

        input_buffer = calloc(input_chunks * BUFFER_SIZE, sizeof(float));
        tinywav_read_f(&tw, input_buffer, _mini(input_chunks * BUFFER_SIZE, tw.numFramesInHeader));
        tinywav_close_read(&tw);
    }
    // "Magic number" formula to approximately match 1Pa peak at 1 meter of distance
    const float gain_correction = powf((float) f_s / 16000.0f, 1.05f) * 90.0f;
    const float input_gain_corrected = input_gain * gain_correction;
    // Amplify each input sample so that it matches the prescribed dB-SPL at 1 meter of distance
    for (int i = 0; i < input_chunks * BUFFER_SIZE; i++) input_buffer[i] *= input_gain_corrected;

    float *output_buffer = malloc(sizeof(float) * input_chunks * BUFFER_SIZE);

    {
        // Same materials order as the case study presented in
        // Oxnard, Stephen, et al. "Frequency-Dependent Absorbing Boundary Implementations in 3D Finite Difference Time Domain Room Acoustics Simulations." Proceedings of EURONOISE, Maastricht, The Netherlands (2015).
        const dwr3_boundary_filter_t *boundary_filters[6] = {
            dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_CONCRETE, f_s),
            dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_CONCRETE, f_s),
            dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_WOOD, f_s),
            dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_PLASTER, f_s),
            dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_CONCRETE, f_s),
            dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_CONCRETE, f_s)
        };
        void *res = dwr3_create(s_x, s_y, s_z, boundary_filters, f_s, BUFFER_SIZE, 1, 1,
                                output_interpolation ? DWR3_INTERPOLATION_LINEAR : DWR3_INTERPOLATION_NEAREST, NULL,
                                NULL, NULL, NULL, NULL, NULL);
        if (res != NULL) {
            const float input_pos[3] = {src_x, src_y, src_z};
            float output_pos[3 * BUFFER_SIZE] = {lst_x, lst_y, lst_z};
            if (output_interpolation)
                // Nearest neighbor interpolation needs only one triplet per receiver, linear requires one per each sample for each receiver
                for (int i = 1; i < BUFFER_SIZE; i++) {
                    output_pos[i * 3 + 0] = lst_x;
                    output_pos[i * 3 + 1] = lst_y;
                    output_pos[i * 3 + 2] = lst_z;
                }
            for (int current_chunk = 0; current_chunk < input_chunks; current_chunk++) {
                const float *input = &input_buffer[current_chunk * BUFFER_SIZE];
                float *output = &output_buffer[current_chunk * BUFFER_SIZE];
                dwr3_process(res, input, input_pos, output, output_pos);
                // Apply the provided dB-FS sensitivity to the output samples
                for (int i = 0; i < BUFFER_SIZE; i++) {
                    const float output_sign = (float) (output[i] > 0.0f) - (float) (output[i] < 0.0f);
                    const float output_spl = 20.0f * log10f(fabsf(output[i]) * 50000.0f); // From Pa to dB-SPL
                    const float output_fs = output_spl + output_spl_to_fs_correction; // From dB-SPL to dB-FS
                    output[i] = output_sign * powf(10.0f, output_fs * 0.05f); // Convert to scaled output
                }
            }

            dwr3_destroy(res);

            TinyWav tw;
            if (tinywav_open_write(&tw, 1, f_s, TW_FLOAT32, TW_INLINE, output_path))
                fprintf(stderr, "Error opening output file!\n");
            else {
                tinywav_write_f(&tw, output_buffer, input_chunks * BUFFER_SIZE);
                tinywav_close_write(&tw);
            }
        } else {
            fprintf(stderr, "Fatal error during initialization!\n");
        }
    }

    free(input_buffer);
    free(output_buffer);

    return EXIT_SUCCESS;
}
