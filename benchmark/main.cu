#include <cassert>
#include <chrono>
#include <random>

#include <dwr3/dwr3.h>

void measure_single(const unsigned int sample_rate, const unsigned int buffer_size, const unsigned int buffer_count,
                    const float sim_size_x, const float sim_size_y, const float sim_size_z, const float *in_samples,
                    float *in_pos, float *out_samples, float *out_pos, const int n_io,
                    const bool listener_interpolation, double *buffer_timings) {
    assert(
        sample_rate > 0 && buffer_size > 0 && buffer_count > 0 && sim_size_x > 0 && sim_size_y > 0 && sim_size_z > 0);

    const dwr3_boundary_filter_t *boundary_filters[6] = {
        dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_CONCRETE, sample_rate),
        dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_CONCRETE, sample_rate),
        dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_CONCRETE, sample_rate),
        dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_CONCRETE, sample_rate),
        dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_WOOD, sample_rate),
        dwr3_boundary_filter_material(DWR3_BOUNDARY_FILTER_MATERIAL_PLASTER, sample_rate)
    };

    int size_x, size_y, size_z;
    size_t size_sim, size_io;
    if (void *res = dwr3_create(sim_size_x, sim_size_y, sim_size_z, boundary_filters, sample_rate, buffer_size, n_io,
                                n_io, listener_interpolation ? DWR3_INTERPOLATION_LINEAR : DWR3_INTERPOLATION_NEAREST,
                                nullptr, &size_x, &size_y, &size_z, &size_sim, &size_io);
        res != nullptr) {
        printf("%d,%d,%d,%lu,", size_x, size_y, size_z, size_sim + size_io);
        fflush(stdout);

        std::random_device rd_x;
        std::mt19937 gen_x(rd_x());
        std::uniform_real_distribution dist_x(0.0f, sim_size_x);
        std::random_device rd_y;
        std::mt19937 gen_y(rd_y());
        std::uniform_real_distribution dist_y(0.0f, sim_size_y);
        std::random_device rd_z;
        std::mt19937 gen_z(rd_z());
        std::uniform_real_distribution dist_z(0.0f, sim_size_z);

        for (unsigned int current_buffer = 0; current_buffer < buffer_count; current_buffer++) {
            const float *input_samples = &in_samples[current_buffer * buffer_size];
            float *output_samples = &out_samples[current_buffer * buffer_size];

            for (int i = 0; i < n_io; i++) {
                in_pos[i * 3 + 0] = dist_x(gen_x);
                in_pos[i * 3 + 1] = dist_y(gen_y);
                in_pos[i * 3 + 2] = dist_z(gen_z);
                out_pos[i * 3 + 0] = dist_x(gen_x);
                out_pos[i * 3 + 1] = dist_y(gen_y);
                out_pos[i * 3 + 2] = dist_z(gen_z);
                if (listener_interpolation)
                    for (unsigned int j = 1; j < buffer_size; j++) {
                        out_pos[(j * n_io + i) * 3 + 0] = dist_x(gen_x);
                        out_pos[(j * n_io + i) * 3 + 1] = dist_y(gen_y);
                        out_pos[(j * n_io + i) * 3 + 2] = dist_z(gen_z);
                    }
            }

            auto start = std::chrono::steady_clock::now();
            dwr3_process(res, input_samples, in_pos, output_samples, out_pos);
            auto end = std::chrono::steady_clock::now();

            const double time =
                    std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count() / 1000000000.0f;
            buffer_timings[current_buffer] = time;
        }

        dwr3_destroy(res);
    }
}

int main(const int argc, char **argv) {
    if (argc != 9) {
        printf("Usage: dwr3_benchmark <sample rate> <buffer size> <buffer count> <min size> <max size> <step "
            "size> <n. sources and listeners> <listeners interpolation>\n");
        return EXIT_FAILURE;
    }

    cudaDeviceProp deviceProp{};
    if (cudaGetDeviceProperties(&deviceProp, 0) != cudaSuccess) {
        printf("Error accessing CUDA device properties\n");
        return EXIT_FAILURE;
    }

    const unsigned int sample_rate = atoi(argv[1]);
    const unsigned int buffer_size = atoi(argv[2]);
    const unsigned int buffer_count = atoi(argv[3]);
    const float min_size = atof(argv[4]);
    const float max_size = atof(argv[5]);
    const float step_size = atof(argv[6]);
    const unsigned int n_io = atoi(argv[7]);
    const bool listener_interpolation = atoi(argv[8]);

    const int n_samples = buffer_size * buffer_count;
    auto *in_samples = new float[n_samples * n_io];
    auto *in_pos = new float[n_io * 3];
    auto *out_samples = new float[n_samples * n_io];
    auto *out_pos = new float[n_io * 3 * (listener_interpolation ? buffer_size : 1)];
    auto *buffer_timings = new double[buffer_count];

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_real_distribution dist(-1.0f, 1.0f);
    for (int sample = 0; sample < n_samples; sample++) in_samples[sample] = dist(gen);

    printf("sample_rate,io_count,out_interpolation,buffer_size,buffer_count,");
    printf("graph_size,center_z_size,disable_updown,disable_rotation,dif_order,device_name,device_L2_size,");
    printf("physical_side_x,physical_side_y,physical_side_z,node_side_x,node_side_y,node_side_z,mem_total,");
    for (unsigned int i = 0; i < buffer_count; i++) printf("buffer_sample_%d%s", i, i == buffer_count - 1 ? "" : ",");
    printf("\n");

    for (float sim_size = min_size; sim_size <= max_size; sim_size += step_size) {
        // Either cubic instances or room instances
#ifndef MEASURE_ROOM
        const float sim_size_x = sim_size;
        const float sim_size_y = sim_size;
        const float sim_size_z = sim_size;
#else
        // Room layout which is bad for computation without coordinate mapping enabled since the X sides become larger than the rest
        constexpr float sim_size_x = 2.5f;
        const float sim_size_y = sim_size / 2;
        const float sim_size_z = sim_size;
#endif

        printf("%d,%d,%d,%d,%d,", sample_rate, n_io, listener_interpolation, buffer_size, buffer_count);
        printf("%d,%d,%d,%d,%d,%s,%d,", DWR3_BUFFER_BASE_SIZE,
#ifdef SIM_CENTER_BLOCK_DIM_Z
               SIM_CENTER_BLOCK_DIM_Z
#else
               -1
#endif
               ,
#ifdef DISABLE_UPDATE_UP_DOWN_ITERATION
               1
#else
               0
#endif
               ,
#ifdef DISABLE_COORDS_MAPPING
               1
#else
               0
#endif
               , DWR3_BOUNDARY_FILTER_ORDER, deviceProp.name, deviceProp.l2CacheSize);
        printf("%f,%f,%f,", sim_size_x, sim_size_y, sim_size_z); // Last four printed in measure_single

        for (unsigned int i = 0; i < buffer_count; i++) buffer_timings[i] = 0;
        measure_single(sample_rate, buffer_size, buffer_count, sim_size_x, sim_size_y, sim_size_z, in_samples, in_pos,
                       out_samples, out_pos, n_io, listener_interpolation, buffer_timings);

        for (unsigned int i = 0; i < buffer_count; i++)
            printf("%f%s", buffer_timings[i], i == buffer_count - 1 ? "" : ",");
        printf("\n");
        fflush(stdout);
    }

    delete[] in_samples;
    delete[] in_pos;
    delete[] out_samples;
    delete[] out_pos;
    delete[] buffer_timings;

    return EXIT_SUCCESS;
}
