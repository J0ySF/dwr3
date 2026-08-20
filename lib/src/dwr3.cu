#include "dwr3/dwr3.h"
#include <cassert>
#include <cstdio>

/// Macros used to handle fatal failures by exiting
#define STRINGIZE_DETAIL(x) #x
#define STRINGIZE(x) STRINGIZE_DETAIL(x)
#define LOG_ERROR(TYPE, FORMAT, ...)                                                                                   \
    {                                                                                                                  \
        fprintf(stderr, "DWR3 " TYPE " error in file " __FILE__ " at line " STRINGIZE(__LINE__) ": " FORMAT "\n",    \
                                                                                        __VA_ARGS__);                  \
    }
#define CHECK_ERROR(CALL, FORMAT, ...)                                                                                 \
    {                                                                                                                  \
        const bool ok = CALL;                                                                                          \
        if (!ok) {                                                                                                     \
            LOG_ERROR("", FORMAT, __VA_ARGS__);                                                                        \
            exit(EXIT_FAILURE);                                                                                        \
        }                                                                                                              \
    }
#define CUDA_CHECK_ERROR(CALL)                                                                                         \
    {                                                                                                                  \
        const cudaError_t result = CALL;                                                                               \
        if (result != cudaSuccess) {                                                                                   \
            LOG_ERROR("CUDA", "%s", cudaGetErrorString(result));                                                       \
            exit(EXIT_FAILURE);                                                                                        \
        }                                                                                                              \
    }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Check for compile-time assumptions
/**/
/// I/O threads for a single block, the current implementation just runs one block so this is enforced
#define IO_THREADS_PER_BLOCK 128
static_assert(IO_THREADS_PER_BLOCK == DWR3_MAX_IO, "IO_THREADS_PER_BLOCK must be the same as DWR3_MAX_IO");

/// Check the assumptions on DWR3_BOUNDARY_FILTER_ORDER that are required by the implementation
static_assert(DWR3_BOUNDARY_FILTER_ORDER == 1 ||
              (DWR3_BOUNDARY_FILTER_ORDER > 1 && DWR3_BOUNDARY_FILTER_ORDER % 2 == 0),
              "DWR3_BOUNDARY_FILTER_ORDER must be greater than 0 and be either 1 or an even number");

/// Check the assumptions on SUBGRAPH_ITERATIONS that are required by the implementation
static_assert(DWR3_BUFFER_BASE_SIZE % 2 == 0, "DWR3_BUFFER_BASE_SIZE must be an even number");
static_assert(DWR3_BUFFER_BASE_SIZE % DWR3_BOUNDARY_FILTER_ORDER == 0,
              "DWR3_BUFFER_BASE_SIZE must be a multiple of DWR3_BOUNDARY_FILTER_ORDER");

/// Implementation based mainly on
/// Kowalczyk, Konrad, and Maarten Van Walstijn. "Room acoustics simulation using 3-D compact explicit FDTD schemes." IEEE Transactions on Audio, Speech, and Language Processing 19.1 (2010): 34-46.
/// using said paper's SLF scheme
/**/
/// Lambda in the numerical scheme
#define L1 0.57735026918962576450914878050196f
/// The reciprocal of Lambda in the numerical scheme
#define L1_REC 1.7320508075688772935274463415059f
/// Lambda squared in the numerical scheme
#define L2 0.33333333333333333333333333333333f
/// d_1 in the numerical scheme
#define D1 0.33333333333333333333333333333333f
/// Speed of sound constant for air
#define SOS 343.0f

/// Index linearization macros for row-major array allocations
/**/
#define SIM_I_INDEX(X, Y, Z) ((X) + (size_x + pad_x) * ((Y) + size_y * (Z)))
#define SIM_X_INDEX(Y, Z) ((Y) + size_y * (Z))
#define SIM_Y_INDEX(X, Z) ((X) + size_x * (Z))
#define SIM_Z_INDEX(X, Y) ((X) + size_x * (Y))

#include "sim_kernels.cuh"

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Accessors to DIF parameters

__host__ __device__ float dif_b_0_rec(const dif_t &d) { return d._b_0_rec; }

static float *dif_b_0_rec_ptr(dif_t &d) { return &d._b_0_rec; }

__host__ __device__ float dif_b(const dif_t &d, const int i) {
    assert(i >= 0 && i <= DWR3_BOUNDARY_FILTER_ORDER);
    return d._b[i];
}

static float *dif_b_ptr(dif_t &d, const int i) {
    assert(i >= 0 && i <= DWR3_BOUNDARY_FILTER_ORDER);
    return &d._b[i];
}

__host__ __device__ float dif_a(const dif_t &d, const int i) {
    assert(i >= 1 && i <= DWR3_BOUNDARY_FILTER_ORDER);
    return d._a[i - 1];
}

static float *dif_a_ptr(dif_t &d, const int i) {
    assert(i >= 1 && i <= DWR3_BOUNDARY_FILTER_ORDER);
    return &d._a[i - 1];
}

/// Conversion between reflectance IIR filter coefficients and DIF filter coefficients
static void dif_compute_from_boundary_filter(dif_t &df, const dwr3_boundary_filter_t *bf) {
    assert(bf != nullptr);
    const double a0 = bf->a[0] - bf->b[0];
    *dif_b_ptr(df, 0) = static_cast<float>((bf->a[0] + bf->b[0]) / a0);
    *dif_b_0_rec_ptr(df) = static_cast<float>(a0 / (bf->a[0] + bf->b[0]));
    for (int i = 1; i <= DWR3_BOUNDARY_FILTER_ORDER; i++) {
        *dif_a_ptr(df, i) = static_cast<float>((bf->a[i] - bf->b[i]) / a0);
        *dif_b_ptr(df, i) = static_cast<float>((bf->a[i] + bf->b[i]) / a0);
    }
}

/// Mappings physical and implementation coordinates
enum coords_mapping_t {
    coords_mapping_xyz,
    coords_mapping_xzy,
    coords_mapping_yxz,
    coords_mapping_yzx,
    coords_mapping_zxy,
    coords_mapping_zyx,
};

/// Determine the best mapping between physical and implementation coordinates
/// @note The current implementation aims to keep the x-axis sides as small as possible, the z-axis are kept as large as
/// possible
template<typename T>
static coords_mapping_t coords_mapping_get(T x, T y, T z) {
    /// If the coordinates mapping is disabled, just return the identity mapping
    /// This is available to showcase in benchmarks the improvement for instances that are better handled with mapping
#ifdef DISABLE_COORDS_MAPPING
    return coords_mapping_xyz;
#endif
    assert(x >= 0 && y >= 0 && z >= 0);
    const T xs = y * z;
    const T ys = x * z;
    const T zs = x * y;
    if (xs <= ys && ys <= zs) return coords_mapping_xyz;
    if (xs <= zs && zs <= ys) return coords_mapping_xzy;
    if (ys <= xs && xs <= zs) return coords_mapping_yxz;
    if (ys <= zs && zs <= xs) return coords_mapping_yzx;
    if (zs <= xs && xs <= ys) return coords_mapping_zxy;
    if (zs <= ys && ys <= xs) return coords_mapping_zyx;
    assert(false);
    return coords_mapping_xyz;
}

/// Map from physical to implementation coordinates, editing the referenced variable's values
template<typename T>
static void coords_mapping_apply(T &x, T &y, T &z, const coords_mapping_t cm) {
    const T xc = x, yc = y, zc = z;
    switch (cm) {
        case coords_mapping_xyz: return;
        case coords_mapping_xzy:
            y = zc;
            z = yc;
            return;
        case coords_mapping_yxz:
            x = yc;
            y = xc;
            return;
        case coords_mapping_yzx:
            x = yc;
            y = zc;
            z = xc;
            return;
        case coords_mapping_zxy:
            x = zc;
            y = xc;
            z = yc;
            return;
        case coords_mapping_zyx:
            x = zc;
            z = xc;
            return;
    }
    assert(false);
}

/// Digital impedance filters coefficients
struct difs_t {
    /// DIF coefficients ordered by dwr3_axis_t's values
    dif_t dif[6];
};

/// Configure DIF parameters
/// @note Requires updating the graph after calling to update the resources
/// @note No operations on the stream (kept for future use)
static void difs_configure(difs_t &d, const dwr3_boundary_filter_t *boundary_filters[6], const coords_mapping_t cm,
                           const bool initial, [[maybe_unused]] const cudaStream_t stream) {
    /// Apply coordinates mapping
    coords_mapping_apply(boundary_filters[0], boundary_filters[2], boundary_filters[4], cm);
    coords_mapping_apply(boundary_filters[1], boundary_filters[3], boundary_filters[5], cm);
    for (int i = 0; i < 6; i++) {
        /// Initial setup requires the filters to be provided, re-configuration keeps the previous filters if not provided
        if (initial)
            CHECK_ERROR(boundary_filters[i] != nullptr, "Boundary filter %i provided NULL during initialization", i)
        if (!initial && boundary_filters[i] == nullptr) continue;
        dif_compute_from_boundary_filter(d.dif[i], boundary_filters[i]);
    }
}

/// State data for each boundary side in the simulation
struct boundary_state_t {
    /// Size in bytes of each array
    size_t _size_single;
    /// Total size in bytes of allocation
    size_t allocation_size;
    /// Intermediate value for the boundary update step, accessed row-major
    float *g;
    /// DIF filter inputs and outputs history, each accessed row-major
    float *x[DWR3_BOUNDARY_FILTER_ORDER], *y[DWR3_BOUNDARY_FILTER_ORDER];
};

/// Create the state for a single boundary
/// @note: Operation is async on the stream
static void boundary_state_create(boundary_state_t &s, const unsigned int area, const cudaStream_t stream) {
    s._size_single = area * sizeof(float);
    s.allocation_size = s._size_single * (1 + 2 * DWR3_BOUNDARY_FILTER_ORDER);
    CUDA_CHECK_ERROR(cudaMallocAsync(&s.g, s._size_single, stream))
    for (int i = 0; i < DWR3_BOUNDARY_FILTER_ORDER; i++)
        CUDA_CHECK_ERROR(cudaMallocAsync(&s.x[i], s._size_single, stream))
    for (int i = 0; i < DWR3_BOUNDARY_FILTER_ORDER; i++)
        CUDA_CHECK_ERROR(cudaMallocAsync(&s.y[i], s._size_single, stream))
}

/// Reset the state for a single boundary
/// @note: Operation is async on the stream
static void boundary_state_reset(const boundary_state_t &s, const cudaStream_t stream) {
    CUDA_CHECK_ERROR(cudaMemsetAsync(s.g, 0, s._size_single, stream))
    for (int i = 0; i < DWR3_BOUNDARY_FILTER_ORDER; i++)
        CUDA_CHECK_ERROR(cudaMemsetAsync(s.x[i], 0, s._size_single, stream))
    for (int i = 0; i < DWR3_BOUNDARY_FILTER_ORDER; i++)
        CUDA_CHECK_ERROR(cudaMemsetAsync(s.y[i], 0, s._size_single, stream))
}

/// Destroy the state for a single boundary
/// @note: Operation is async on the stream
static void boundary_state_destroy(const boundary_state_t &s, const cudaStream_t stream) {
    CUDA_CHECK_ERROR(cudaFreeAsync(s.g, stream))
    for (int i = 0; i < DWR3_BOUNDARY_FILTER_ORDER; i++) CUDA_CHECK_ERROR(cudaFreeAsync(s.x[i], stream))
    for (int i = 0; i < DWR3_BOUNDARY_FILTER_ORDER; i++) CUDA_CHECK_ERROR(cudaFreeAsync(s.y[i], stream))
}

/// Rotate the DIF I/O history x and y pointers backwards by one sample,
/// this is used during iteration in order to shift the state pointers instead of rotating the values in the arrays
static void boundary_state_rotate_xy(boundary_state_t &b) {
    float *const l_x = b.x[DWR3_BOUNDARY_FILTER_ORDER - 1];
    for (int j = DWR3_BOUNDARY_FILTER_ORDER - 1; j > 0; j--) b.x[j] = b.x[j - 1];
    b.x[0] = l_x;
    float *const l_y = b.y[DWR3_BOUNDARY_FILTER_ORDER - 1];
    for (int j = DWR3_BOUNDARY_FILTER_ORDER - 1; j > 0; j--) b.y[j] = b.y[j - 1];
    b.y[0] = l_y;
}

/// Simulation state
struct sim_t {
    /// Mapping orientation between physical and simulation coordinates
    coords_mapping_t coords_mapping;
    /// Conversion constant between physical units and nodes units
    float nodes_per_unit;
    /// Implementation-space size
    int size_x, size_y, size_z;
    /// Either 0 or 1 depending on odd or even size_x
    int pad_x;

    /// Pressure state buffers, each accessed row-major, sized (size_x + pad_x) * size_y * size_z
    float *p[2];
    /// Size of p allocations
    size_t _p_size;
    /// Boundary states, ordered by dwr3_axis_t's values
    boundary_state_t b[6];

    /// Sim kernels grid sizes
    dim3 iter_x_grid, iter_y_grid, iter_z_grid, iter_c_grid;

    /// Total allocation size of the simulation
    size_t allocation_size;
};

/// Destroy the state of the simulation
/// @note: Operation is async on the stream
static void sim_destroy(const sim_t &s, const cudaStream_t stream) {
    for (int i = 0; i < 2; i++) CUDA_CHECK_ERROR(cudaFreeAsync(s.p[i], stream))
    for (int i = 0; i < 6; i++) boundary_state_destroy(s.b[i], stream);
}

/// Reset the state of the simulation
/// @note: Operation is async on the stream
static void sim_reset(const sim_t &s, const cudaStream_t stream) {
    for (int i = 0; i < 2; i++) CUDA_CHECK_ERROR(cudaMemsetAsync(s.p[i], 0, s._p_size, stream))
    for (int i = 0; i < 6; i++) boundary_state_reset(s.b[i], stream);
}

/// Configure the state of the simulation
/// @note: Operation is async on the stream
/// @note Requires updating the graph after calling to update the resources
static void sim_configure(sim_t &s, float physical_size_x, float physical_size_y, float physical_size_z,
                          const double sample_rate, const bool initial, const cudaStream_t stream) {
    CHECK_ERROR(physical_size_x >= 0, "Physical size X value %f is not valid", physical_size_x)
    CHECK_ERROR(physical_size_x >= 0, "Physical size Y value %f is not valid", physical_size_y)
    CHECK_ERROR(physical_size_x >= 0, "Physical size Z value %f is not valid", physical_size_z)
    CHECK_ERROR(physical_size_x >= 0, "Sample rate %f is not valid", sample_rate)

    if (!initial) sim_destroy(s, stream); // Reconfiguration just destroys and starts from scratch

    s.coords_mapping = coords_mapping_get(physical_size_x, physical_size_y, physical_size_z);
    coords_mapping_apply(physical_size_x, physical_size_y, physical_size_z, s.coords_mapping);
    s.nodes_per_unit = L1 * static_cast<float>(sample_rate) / SOS;

    // Round to nearest grid size when determining size
    s.size_x = max(static_cast<int>(roundf(physical_size_x * s.nodes_per_unit)), 0) + 1;
    s.pad_x = s.size_x % 2 != 0 ? 1 : 0; // Check if padding is needed
    s.size_y = max(static_cast<int>(roundf(physical_size_y * s.nodes_per_unit)), 0) + 1;
    s.size_z = max(static_cast<int>(roundf(physical_size_z * s.nodes_per_unit)), 0) + 1;
    CHECK_ERROR(s.size_x >= 3, "Resulting node size on X axis %d is lesser than 3 nodes", s.size_x)
    CHECK_ERROR(s.size_y >= 3, "Resulting node size on Y axis %d is lesser than 3 nodes", s.size_y)
    CHECK_ERROR(s.size_z >= 3, "Resulting node size on Z axis %d is lesser than 3 nodes", s.size_z)

    s._p_size = (s.size_x + s.pad_x) * s.size_y * s.size_z * sizeof(float);
    for (int i = 0; i < 2; i++) CUDA_CHECK_ERROR(cudaMallocAsync(&s.p[i], s._p_size, stream))

    const int side_areas[3] = {s.size_y * s.size_z, s.size_x * s.size_z, s.size_x * s.size_y};
    for (int i = 0; i < 6; i++) boundary_state_create(s.b[i], side_areas[i / 2], stream);

    sim_reset(s, stream);

    s.iter_x_grid = dim3(((s.size_y - 2) + SIM_BORDER_BLOCK_DIM_X - 1) / SIM_BORDER_BLOCK_DIM_X,
                         ((s.size_z - 2) + SIM_BORDER_BLOCK_DIM_Y - 1) / SIM_BORDER_BLOCK_DIM_Y);
    s.iter_y_grid = dim3((s.size_x + SIM_BORDER_BLOCK_DIM_X - 1) / SIM_BORDER_BLOCK_DIM_X,
                         ((s.size_z - 2) + SIM_BORDER_BLOCK_DIM_Y - 1) / SIM_BORDER_BLOCK_DIM_Y);
    s.iter_z_grid = dim3((s.size_x + SIM_BORDER_BLOCK_DIM_X - 1) / SIM_BORDER_BLOCK_DIM_X,
                         (s.size_y + SIM_BORDER_BLOCK_DIM_Y - 1) / SIM_BORDER_BLOCK_DIM_Y);
    s.iter_c_grid = dim3(((s.size_x - 2) + SIM_CENTER_BLOCK_COMPUTE_DIM_X - 1) / SIM_CENTER_BLOCK_COMPUTE_DIM_X,
                         ((s.size_y - 2) + SIM_CENTER_BLOCK_DIM_Y - 1) / SIM_CENTER_BLOCK_DIM_Y,
                         ((s.size_z - 2) + SIM_CENTER_BLOCK_DIM_Z - 1) / SIM_CENTER_BLOCK_DIM_Z);

    s.allocation_size = s._p_size * 2; // Compute allocation size
    for (int i = 0; i < 6; i++) s.allocation_size += s.b[i].allocation_size;
}

/// Convert from physical to integer node units
/// @note Clamps the positions in bounds
static void sim_physical_to_nodes_round(const sim_t &s, const float p_x, const float p_y, const float p_z, int &n_x,
                                        int &n_y, int &n_z) {
    n_x = min(max(static_cast<int>(roundf(p_x * s.nodes_per_unit)), 0), s.size_x - 1);
    n_y = min(max(static_cast<int>(roundf(p_y * s.nodes_per_unit)), 0), s.size_y - 1);
    n_z = min(max(static_cast<int>(roundf(p_z * s.nodes_per_unit)), 0), s.size_z - 1);
}

/// Convert from physical to floating point node units
/// @note Clamps the positions in bounds
static void sim_physical_to_nodes(const sim_t &s, const float p_x, const float p_y, const float p_z, float &n_x,
                                  float &n_y, float &n_z) {
    n_x = min(max(p_x * s.nodes_per_unit, 0.0f), static_cast<float>(s.size_x - 1));
    n_y = min(max(p_y * s.nodes_per_unit, 0.0f), static_cast<float>(s.size_y - 1));
    n_z = min(max(p_z * s.nodes_per_unit, 0.0f), static_cast<float>(s.size_z - 1));
}

/// Convert from integer node units to linearized index in p arrays
static int sim_nodes_to_index(const sim_t &s, const int n_x, const int n_y, const int n_z) {
    assert(n_x >= 0 && n_y >= 0 && n_z >= 0 && n_x < s.size_x && n_y < s.size_y && n_z < s.size_z);
    const int size_x = s.size_x; // Bring names into scope for macro purposes
    const int pad_x = s.pad_x; // Bring names into scope for macro purposes
    const int size_y = s.size_y;
    return SIM_I_INDEX(n_x, n_y, n_z);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Stores input and output pointers for each data segment over a contiguous memory allocation
struct io_pointers_t {
    /// Buffer index
    int *n;
    /// Input position indices
    int *input_positions;
    /// Input samples buffers with interleaved values
    float *input_buffer;
    /// Output position indices
    void *output_positions;
    /// Output samples buffers with interleaved values
    float *output_buffer;
};

/// Fills the pointers in io_pointers_t from a contiguous memory allocation
static void io_pointers_fill(io_pointers_t &ptrs, void *allocation, const int buffer_size, const int input_count,
                             const int output_count, const dwr3_interpolation_t output_interpolation) {
    size_t offset = 0;

    // Host -> device data
    ptrs.n = static_cast<int *>(allocation) + offset;
    offset += 1;
    ptrs.input_positions = static_cast<int *>(allocation) + offset;
    offset += input_count;
    ptrs.input_buffer = static_cast<float *>(allocation) + offset;
    offset += input_count * buffer_size;
    switch (output_interpolation) {
        case DWR3_INTERPOLATION_NEAREST:
            ptrs.output_positions = static_cast<int *>(allocation) + offset;
            offset += output_count;
            break;
        case DWR3_INTERPOLATION_LINEAR:
            ptrs.output_positions = static_cast<float *>(allocation) + offset;
            offset += output_count * 3 * buffer_size;
            break;
    }

    // Device -> host data
    ptrs.output_buffer = static_cast<float *>(allocation) + offset;
    offset += output_count * buffer_size;
}

/// Input and output state
struct io_t {
    /// I/O count
    int input_count, output_count;
    /// I/O samples
    int buffer_size;
    /// I/O size in bytes
    size_t _h2d_size, _d2h_size;
    /// I/O total allocation
    size_t allocation_size;
    /// Host and device I/O memory allocations
    void *_h_alloc, *_d_alloc;
    /// Host and device I/O pointers
    io_pointers_t h_pointers, d_pointers;
    /// Output interpolation mode
    dwr3_interpolation_t output_interpolation;
};

/// Destroy the io state
/// @note: Operation is async on the stream
static void io_destroy(const io_t &io, const cudaStream_t stream) {
    CUDA_CHECK_ERROR(cudaFreeHost(io._h_alloc))
    CUDA_CHECK_ERROR(cudaFreeAsync(io._d_alloc, stream))
}

/// Configure the io state
/// @note: Operation is async on the stream
/// @note Requires updating the graph after calling to update the resources
static void io_configure(io_t &io, const unsigned int buffer_size, const unsigned int input_count,
                         const unsigned int output_count, const dwr3_interpolation_t output_interpolation,
                         const bool initial, const cudaStream_t stream) {
    CHECK_ERROR(buffer_size > 0, "Buffer size %d is not valid", buffer_size)
    CHECK_ERROR(buffer_size % DWR3_BUFFER_BASE_SIZE == 0,
                "Buffer size %d is not a multiple of DWR3_BUFFER_BASE_SIZE=%d", buffer_size, DWR3_BUFFER_BASE_SIZE)
    CHECK_ERROR(input_count > 0, "Input count %d is not valid", input_count)
    CHECK_ERROR(output_count > 0, "Output count %d is not valid", output_count)
    CHECK_ERROR(input_count <= DWR3_MAX_IO, "Input count %d is greater than DWR3_MAX_INPUTS=%d", input_count,
                DWR3_MAX_IO)
    CHECK_ERROR(output_count <= DWR3_MAX_IO, "Output count %d is greater than DWR3_MAX_OUTPUTS=%d", output_count,
                DWR3_MAX_IO)

    if (initial) io_destroy(io, stream); // Reconfiguration just destroys and starts from scratch

    io.input_count = input_count;
    io.output_count = output_count;
    io.buffer_size = buffer_size;
    io.output_interpolation = output_interpolation;

    // Compute host -> device allocation size
    io._h2d_size = sizeof(int) + //
                   io.input_count * sizeof(int) + //
                   io.input_count * buffer_size * sizeof(float);
    switch (output_interpolation) {
        case DWR3_INTERPOLATION_NEAREST: io._h2d_size += io.output_count * sizeof(int);
            break;
        case DWR3_INTERPOLATION_LINEAR: io._h2d_size += io.output_count * sizeof(float) * 3 * buffer_size;
            break;
    }
    io._d2h_size = io.output_count * buffer_size * sizeof(float); // Compute device -> host allocation size
    io.allocation_size = io._h2d_size + io._d2h_size; // Compute total IO allocation size

    CUDA_CHECK_ERROR(cudaHostAlloc(&io._h_alloc, io.allocation_size, cudaHostAllocDefault))
    CUDA_CHECK_ERROR(cudaMallocAsync(&io._d_alloc, io.allocation_size, stream))

    io_pointers_fill(io.h_pointers, io._h_alloc, buffer_size, input_count, output_count, output_interpolation);
    io_pointers_fill(io.d_pointers, io._d_alloc, buffer_size, input_count, output_count, output_interpolation);

    *io.h_pointers.n = 0; // The first buffer value is read as a counter inside IO kernels, this value is set so that
    // each host transfer also resets this counter
}

/// Transfer the IO data from host to device
/// @note: Operation is async on the stream
void io_transfer_host_to_device(const io_t &io, const float *input_samples, const float *input_positions,
                                const float *output_positions, const sim_t &sim, const cudaStream_t stream) {
    // Transfer asynchronously into the single transfer buffer all samples, in the meantime compute the coordinates
    CUDA_CHECK_ERROR(cudaMemcpyAsync(io.h_pointers.input_buffer, input_samples,
        sizeof(float) * io.buffer_size * io.input_count, cudaMemcpyHostToHost, stream))
    // Apply coordinates mapping to input positions and store them in the single transfer buffer
    for (int i = 0; i < io.input_count; i++) {
        float p_x = input_positions[i * 3 + 0], p_y = input_positions[i * 3 + 1], p_z = input_positions[i * 3 + 2];
        coords_mapping_apply(p_x, p_y, p_z, sim.coords_mapping);
        int n_x, n_y, n_z;
        sim_physical_to_nodes_round(sim, p_x, p_y, p_z, n_x, n_y, n_z);
        io.h_pointers.input_positions[i] = sim_nodes_to_index(sim, n_x, n_y, n_z);
    }
    // Apply coordinates mapping to output positions and store them in the single transfer buffer
    switch (io.output_interpolation) {
        case DWR3_INTERPOLATION_NEAREST:
            for (int i = 0; i < io.output_count; i++) {
                float p_x = output_positions[i * 3 + 0], p_y = output_positions[i * 3 + 1],
                        p_z = output_positions[i * 3 + 2];
                coords_mapping_apply(p_x, p_y, p_z, sim.coords_mapping);
                int n_x, n_y, n_z;
                sim_physical_to_nodes_round(sim, p_x, p_y, p_z, n_x, n_y, n_z);
                static_cast<int *>(io.h_pointers.output_positions)[i] = sim_nodes_to_index(sim, n_x, n_y, n_z);
            }
            break;
        case DWR3_INTERPOLATION_LINEAR:
            const int tot = io.buffer_size * io.output_count;
            for (int i = 0; i < tot; i++) {
                float p_x = output_positions[i * 3 + 0], p_y = output_positions[i * 3 + 1],
                        p_z = output_positions[i * 3 + 2];
                coords_mapping_apply(p_x, p_y, p_z, sim.coords_mapping);
                sim_physical_to_nodes(sim, p_x, p_y, p_z,
                                      static_cast<float *>(io.h_pointers.output_positions)[i * 3 + 0],
                                      static_cast<float *>(io.h_pointers.output_positions)[i * 3 + 1],
                                      static_cast<float *>(io.h_pointers.output_positions)[i * 3 + 2]);
            }
            break;
    }
    // Single transfer from host to device, this waits for the first cudaMemcpyAsync to complete
    CUDA_CHECK_ERROR(cudaMemcpyAsync(io._d_alloc, io._h_alloc, io._h2d_size, cudaMemcpyHostToDevice, stream))
}

/// Transfer the IO data from device to host
/// @note: Operation is async on the stream
void io_transfer_device_to_host(const io_t &io, float *output_samples, const cudaStream_t stream) {
    CUDA_CHECK_ERROR(cudaMemcpyAsync(io.h_pointers.output_buffer, io.d_pointers.output_buffer, io._d2h_size,
        cudaMemcpyDeviceToHost, stream))
    CUDA_CHECK_ERROR(cudaMemcpyAsync(output_samples, io.h_pointers.output_buffer, io._d2h_size,
        cudaMemcpyHostToHost, stream))
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// IO kernels, each one is meant to be executed with one single block
/**/
/// Hard source excitation
__global__ void __launch_bounds__(IO_THREADS_PER_BLOCK)
io_step_input(float *__restrict__ p_curr, const int *__restrict__ n, const int *__restrict__ input_positions,
              const float *__restrict__ input_buffer) {
    p_curr[input_positions[threadIdx.x]] = input_buffer[threadIdx.x + blockDim.x * *n];
}

/// Sampling nearest neighbor
__global__ void __launch_bounds__(IO_THREADS_PER_BLOCK)
io_step_output_nearest(const float *__restrict__ p_curr, int *__restrict__ n,
                       const int *__restrict__ output_positions, float *__restrict__ output_buffer) {
    output_buffer[threadIdx.x + blockDim.x * *n] = p_curr[output_positions[threadIdx.x]];
    __syncthreads();
    if (threadIdx.x == 0) (*n)++;
}

/// Aux function from https://developer.nvidia.com/blog/lerp-faster-cuda/
template<typename T>
__device__ T lerpp(T v0, T v1, T t) {
    return fma(t, v1, fma(-t, v0, v0));
}

/// Linear interpolation implementation
template<int pad_x>
__device__ void io_step_output_linear_perform(const int size_x, const int size_y, const float *__restrict__ p_curr,
                                              const int n, const float *__restrict__ output_positions,
                                              float *__restrict__ output_buffer, const int output_count) {
    const int positions_sample_offset = (n * output_count + threadIdx.x) * 3;
    const float x = output_positions[positions_sample_offset + 0];
    const int x_floor = static_cast<int>(floorf(x));
    const float x_frac = x - x_floor;
    const float y = output_positions[positions_sample_offset + 1];
    const int y_floor = static_cast<int>(floorf(y));
    const float y_frac = y - y_floor;
    const float z = output_positions[positions_sample_offset + 2];
    const int z_floor = static_cast<int>(floorf(z));
    const float z_frac = z - z_floor;

    p_curr += SIM_I_INDEX(x_floor, y_floor, z_floor);

    const int ox = 1, oy = size_x, oz = size_x * size_y;
    const float o = lerpp( //
        lerpp( //
            lerpp( //
                *(p_curr + 00 + 00 + 00), *(p_curr + 00 + 00 + oz), z_frac),
            lerpp( //
                *(p_curr + 00 + oy + 00), *(p_curr + 00 + oy + oz), z_frac),
            y_frac),
        lerpp( //
            lerpp( //
                *(p_curr + ox + 00 + 00), *(p_curr + ox + 00 + oz), z_frac),
            lerpp( //
                *(p_curr + ox + oy + 00), *(p_curr + ox + oy + oz), z_frac),
            y_frac),
        x_frac);
    output_buffer[threadIdx.x + blockDim.x * n] = o;
}

/// Sampling linear interpolation
template<int pad_x>
__global__ void __launch_bounds__(IO_THREADS_PER_BLOCK)
io_step_output_linear(const int size_x, const int size_y, const float *__restrict__ p_curr, int *__restrict__ n,
                      const float *__restrict__ output_positions, float *__restrict__ output_buffer) {
    io_step_output_linear_perform<pad_x>(size_x, size_y, p_curr, *n, output_positions, output_buffer, blockDim.x);
    __syncthreads();
    if (threadIdx.x == 0) (*n)++;
}

/// Sampling nearest neighbor, then hard source excitation
__global__ void __launch_bounds__(IO_THREADS_PER_BLOCK)
io_step_output_nearest_then_input(float *__restrict__ p_curr_then_p_prev, int *__restrict__ n,
                                  const int *__restrict__ output_positions, float *__restrict__ output_buffer,
                                  const int output_count, const int *__restrict__ input_positions,
                                  const float *__restrict__ input_buffer, const int input_count) {
    const int device_n_local = *n;
    if (threadIdx.x < output_count)
        output_buffer[threadIdx.x + output_count * device_n_local] = p_curr_then_p_prev[output_positions[threadIdx.x]];
    __syncthreads();
    if (threadIdx.x < input_count)
        p_curr_then_p_prev[input_positions[threadIdx.x]] =
                input_buffer[threadIdx.x + input_count * (device_n_local + 1)];
    if (threadIdx.x == 0) (*n)++;
}

/// Sampling linear interpolation, then hard source excitation
template<int pad_x>
__global__ void __launch_bounds__(IO_THREADS_PER_BLOCK)
io_step_output_linear_then_input(const int size_x, const int size_y, float *__restrict__ p_curr_then_p_prev,
                                 int *__restrict__ n, const float *__restrict__ output_positions,
                                 float *__restrict__ output_buffer, const int output_count,
                                 const int *__restrict__ input_positions,
                                 const float *__restrict__ input_buffer, const int input_count) {
    const int device_n_local = *n;
    if (threadIdx.x < output_count)
        io_step_output_linear_perform<pad_x>(size_x, size_y, p_curr_then_p_prev, device_n_local,
                                             output_positions, output_buffer, output_count);
    __syncthreads();
    if (threadIdx.x < input_count)
        p_curr_then_p_prev[input_positions[threadIdx.x]] =
                input_buffer[threadIdx.x + input_count * (device_n_local + 1)];
    if (threadIdx.x == 0) (*n)++;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Implementation data structure
struct dwr3_t {
    /// Async stream used for all CUDA computation
    cudaStream_t stream;
    /// Priority levels fetched at startup, medium is treated as the default,
    /// with low and high reserved for the Z boundary kernels
    int streamPriorityLow, streamPriorityMedium, streamPriorityHigh;

    /// Simulation state
    sim_t sim;
    /// DIF filters state
    difs_t difs;
    /// IO state
    io_t io;

    /// CUDA graph instance used to compute DWR3_BUFFER_BASE_SIZE iterations
    cudaGraph_t subgraph;
    cudaGraphExec_t subgraph_exec;
};

static void subgraph_destroy(const dwr3_t &w) {
    CUDA_CHECK_ERROR(cudaGraphExecDestroy(w.subgraph_exec))
    CUDA_CHECK_ERROR(cudaGraphDestroy(w.subgraph))
}

/// Configure the subgraph for DWR3_BUFFER_BASE_SIZE sub-iterations
template<int pad_x>
static void subgraph_configure(dwr3_t &w, const bool initial) {
    if (!initial) subgraph_destroy(w);

    /// Create a subgraph with structure
    /// ================================================================================================================
    ///                 |-> X axis  (normal priority)   |                              |->     |
    ///                 |-> Y axis  (normal priority)   |                              |->     |
    /// Source modeling |-> Center  (normal priority)   |-> Receiver + source modeling |-> ... |-> Receiver modeling
    ///                 |-> Z- axis (low/high priority) |                              |->     |
    ///                 |-> Z+ axis (low/high priority) |                              |->     |
    /// ================================================================================================================
    cudaStream_t stream_x, stream_y, stream_z_lp, stream_z_hp;
    cudaEvent_t event_io_done, event_x_done, event_y_done, event_z_lp_done, event_z_hp_done;
    CUDA_CHECK_ERROR(cudaStreamCreateWithPriority(&stream_x, cudaStreamDefault, w.streamPriorityMedium))
    CUDA_CHECK_ERROR(cudaStreamCreateWithPriority(&stream_y, cudaStreamDefault, w.streamPriorityMedium))
    CUDA_CHECK_ERROR(cudaStreamCreateWithPriority(&stream_z_lp, cudaStreamDefault, w.streamPriorityLow))
    CUDA_CHECK_ERROR(cudaStreamCreateWithPriority(&stream_z_hp, cudaStreamDefault, w.streamPriorityHigh))
    CUDA_CHECK_ERROR(cudaEventCreate(&event_io_done))
    CUDA_CHECK_ERROR(cudaEventCreate(&event_x_done))
    CUDA_CHECK_ERROR(cudaEventCreate(&event_y_done))
    CUDA_CHECK_ERROR(cudaEventCreate(&event_z_lp_done))
    CUDA_CHECK_ERROR(cudaEventCreate(&event_z_hp_done))
    CUDA_CHECK_ERROR(cudaStreamBeginCapture(w.stream, cudaStreamCaptureModeGlobal))

    for (int n = 0; n < DWR3_BUFFER_BASE_SIZE; n++) {
        // Sources modeling only kernel on first iteration
        if (n == 0) {
            io_step_input<<<dim3(1), dim3(w.io.input_count), 0, w.stream>>> //
                    (w.sim.p[0], w.io.d_pointers.n, w.io.d_pointers.input_positions, w.io.d_pointers.input_buffer);
            CUDA_CHECK_ERROR(cudaEventRecord(event_io_done, w.stream))
        }

        // Boundary state actual parameters macro
#define BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(I) w.sim.b[I].g, MACRO_LIST_EXPANSION_0(w.sim.b[I].x[, , , ]), MACRO_LIST_EXPANSION_0(w.sim.b[I].y[, , , ]), w.difs.dif[I]

        // Single time-step update kernels
#ifdef DISABLE_UPDATE_UP_DOWN_ITERATION
        // Disable up-down iteration for benchmarking purposes
        if (true) {
#else
        if (n % 2 == 0) {
#endif
            CUDA_CHECK_ERROR(cudaStreamWaitEvent(stream_z_hp, event_io_done, 0))
            sim_iter_z_n<pad_x> //
                    <<<w.sim.iter_z_grid, dim3(SIM_BORDER_BLOCK_DIM_X, SIM_BORDER_BLOCK_DIM_Y), 0, stream_z_hp>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.p[0], w.sim.p[1], //
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Z_N));
            CUDA_CHECK_ERROR(cudaEventRecord(event_z_hp_done, stream_z_hp))

            CUDA_CHECK_ERROR(cudaStreamWaitEvent(stream_x, event_io_done, 0))
            sim_iter_x<false, pad_x> //
                    <<<w.sim.iter_x_grid, dim3(SIM_BORDER_BLOCK_DIM_X, SIM_BORDER_BLOCK_DIM_Y), 0, stream_x>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.size_z, w.sim.p[0], w.sim.p[1], //
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_P));
            CUDA_CHECK_ERROR(cudaEventRecord(event_x_done, stream_x))

            CUDA_CHECK_ERROR(cudaStreamWaitEvent(stream_y, event_io_done, 0))
            sim_iter_y<false, pad_x> //
                    <<<w.sim.iter_y_grid, dim3(SIM_BORDER_BLOCK_DIM_X, SIM_BORDER_BLOCK_DIM_Y), 0, stream_y>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.size_z, w.sim.p[0], w.sim.p[1], //
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_P));
            CUDA_CHECK_ERROR(cudaEventRecord(event_y_done, stream_y))


            sim_iter_c<false, pad_x><<<w.sim.iter_c_grid, dim3(SIM_CENTER_BLOCK_DIM_X, SIM_CENTER_BLOCK_DIM_Y), 0, w.
                    stream>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.size_z, w.sim.p[0], w.sim.p[1]);

            CUDA_CHECK_ERROR(cudaStreamWaitEvent(stream_z_lp, event_io_done, 0))
            sim_iter_z_p<pad_x><<<w.sim.iter_z_grid, dim3(SIM_BORDER_BLOCK_DIM_X, SIM_BORDER_BLOCK_DIM_Y), 0,
                    stream_z_lp>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.size_z, w.sim.p[0], w.sim.p[1], //
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Z_P));
            CUDA_CHECK_ERROR(cudaEventRecord(event_z_lp_done, stream_z_lp))
        } else {
            CUDA_CHECK_ERROR(cudaStreamWaitEvent(stream_z_hp, event_io_done, 0))
            sim_iter_z_p<pad_x> //
                    <<<w.sim.iter_z_grid, dim3(SIM_BORDER_BLOCK_DIM_X, SIM_BORDER_BLOCK_DIM_Y), 0, stream_z_hp>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.size_z, w.sim.p[0], w.sim.p[1], //
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Z_P));
            CUDA_CHECK_ERROR(cudaEventRecord(event_z_hp_done, stream_z_hp))

            CUDA_CHECK_ERROR(cudaStreamWaitEvent(stream_x, event_io_done, 0))
            sim_iter_x<true, pad_x> //
                    <<<w.sim.iter_x_grid, dim3(SIM_BORDER_BLOCK_DIM_X, SIM_BORDER_BLOCK_DIM_Y), 0, stream_x>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.size_z, w.sim.p[0], w.sim.p[1], //
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_P));
            CUDA_CHECK_ERROR(cudaEventRecord(event_x_done, stream_x))

            CUDA_CHECK_ERROR(cudaStreamWaitEvent(stream_y, event_io_done, 0))
            sim_iter_y<true, pad_x> //
                    <<<w.sim.iter_y_grid, dim3(SIM_BORDER_BLOCK_DIM_X, SIM_BORDER_BLOCK_DIM_Y), 0, stream_y>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.size_z, w.sim.p[0], w.sim.p[1], //
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_P));
            CUDA_CHECK_ERROR(cudaEventRecord(event_y_done, stream_y))

            sim_iter_c<true, pad_x> //
                    <<<w.sim.iter_c_grid, dim3(SIM_CENTER_BLOCK_DIM_X, SIM_CENTER_BLOCK_DIM_Y), 0, w.stream>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.size_z, w.sim.p[0], w.sim.p[1]);

            CUDA_CHECK_ERROR(cudaStreamWaitEvent(stream_z_lp, event_io_done, 0))
            sim_iter_z_n<pad_x> //
                    <<<w.sim.iter_z_grid, dim3(SIM_BORDER_BLOCK_DIM_X, SIM_BORDER_BLOCK_DIM_Y), 0,stream_z_lp>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.p[0], w.sim.p[1], //
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_X_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_N),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Y_P),
                        BOUNDARY_ACTUAL_PARAMETERS_GRAPH_BUILD(DWR3_AXIS_Z_N));
            CUDA_CHECK_ERROR(cudaEventRecord(event_z_lp_done, stream_z_lp))
        }

        CUDA_CHECK_ERROR(cudaStreamWaitEvent(w.stream, event_x_done, 0))
        CUDA_CHECK_ERROR(cudaStreamWaitEvent(w.stream, event_y_done, 0))
        CUDA_CHECK_ERROR(cudaStreamWaitEvent(w.stream, event_z_lp_done, 0))
        CUDA_CHECK_ERROR(cudaStreamWaitEvent(w.stream, event_z_hp_done, 0))

        // Receivers + sources modeling for middle iterations
        if (n < DWR3_BUFFER_BASE_SIZE - 1) {
            switch (w.io.output_interpolation) {
                case DWR3_INTERPOLATION_NEAREST:
                    io_step_output_nearest_then_input //
                            <<<dim3(1), dim3(max(w.io.input_count, w.io.output_count)), 0, w.stream>>>( //
                                w.sim.p[1], w.io.d_pointers.n, static_cast<int *>(w.io.d_pointers.output_positions),
                                w.io.d_pointers.output_buffer, w.io.output_count, w.io.d_pointers.input_positions,
                                w.io.d_pointers.input_buffer, w.io.input_count);
                    break;
                case DWR3_INTERPOLATION_LINEAR:
                    io_step_output_linear_then_input //
                            <pad_x><<<dim3(1), dim3(max(w.io.input_count, w.io.output_count)), 0, w.stream>>>( //
                                w.sim.size_x, w.sim.size_y, w.sim.p[1], w.io.d_pointers.n,
                                static_cast<float *>(w.io.d_pointers.output_positions),
                                w.io.d_pointers.output_buffer, w.io.output_count, w.io.d_pointers.input_positions,
                                w.io.d_pointers.input_buffer, w.io.input_count);
                    break;
            }
            CUDA_CHECK_ERROR(cudaEventRecord(event_io_done, w.stream))
        } else {
            // Receivers modeling only on last iteration
            switch (w.io.output_interpolation) {
                case DWR3_INTERPOLATION_NEAREST:
                    io_step_output_nearest<<<dim3(1), dim3(w.io.output_count), 0, w.stream>>>( //
                        w.sim.p[1], w.io.d_pointers.n, static_cast<int *>(w.io.d_pointers.output_positions),
                        w.io.d_pointers.output_buffer);
                    break;
                case DWR3_INTERPOLATION_LINEAR:
                    io_step_output_linear<pad_x><<<dim3(1), dim3(w.io.output_count), 0, w.stream>>>( //
                        w.sim.size_x, w.sim.size_y, w.sim.p[1], w.io.d_pointers.n,
                        static_cast<float *>(w.io.d_pointers.output_positions), w.io.d_pointers.output_buffer);
                    break;
            }
        }

        // Rotate the simulation state pointers
        std::swap(w.sim.p[0], w.sim.p[1]);
        for (int i = 0; i < 6; i++) boundary_state_rotate_xy(w.sim.b[i]);
    }

    CUDA_CHECK_ERROR(cudaStreamEndCapture(w.stream, &w.subgraph))

    CUDA_CHECK_ERROR(cudaStreamDestroy(stream_x))
    CUDA_CHECK_ERROR(cudaStreamDestroy(stream_y))
    CUDA_CHECK_ERROR(cudaStreamDestroy(stream_z_lp))
    CUDA_CHECK_ERROR(cudaStreamDestroy(stream_z_hp))
    CUDA_CHECK_ERROR(cudaEventDestroy(event_io_done))
    CUDA_CHECK_ERROR(cudaEventDestroy(event_x_done))
    CUDA_CHECK_ERROR(cudaEventDestroy(event_y_done))
    CUDA_CHECK_ERROR(cudaEventDestroy(event_z_lp_done))
    CUDA_CHECK_ERROR(cudaEventDestroy(event_z_hp_done))

    CUDA_CHECK_ERROR(
        cudaGraphInstantiateWithFlags(&w.subgraph_exec, w.subgraph, cudaGraphInstantiateFlagUseNodePriority))
}

void *dwr3_create(const float size_x_m, const float size_y_m, const float size_z_m,
                  const dwr3_boundary_filter_t *boundary_filters[6], const double sample_rate,
                  const unsigned int buffer_size, const unsigned int input_count, const unsigned int output_count,
                  const dwr3_interpolation_t output_interpolation, float *nodes_distance, int *size_x_n,
                  int *size_y_n, int *size_z_n, size_t *sim_memory_size, size_t *io_memory_size) {
    auto *w = static_cast<dwr3_t *>(calloc(1, sizeof(dwr3_t)));
    assert(w != nullptr);

    // Get the min, max, medium priorities
    CUDA_CHECK_ERROR(cudaDeviceGetStreamPriorityRange(&w->streamPriorityLow, &w->streamPriorityHigh))
    w->streamPriorityMedium = (w->streamPriorityLow + w->streamPriorityHigh) / 2;
    // Regular stream with medium priority
    CUDA_CHECK_ERROR(cudaStreamCreateWithPriority(&w->stream, cudaStreamDefault, w->streamPriorityMedium))

    // Since none of the currently developed kernels make use of shared memory, reserve more L1 cache
    CUDA_CHECK_ERROR(cudaDeviceSetCacheConfig(cudaFuncCachePreferL1))

    // First configuration of all state
    sim_configure(w->sim, size_x_m, size_y_m, size_z_m, sample_rate, true, w->stream);
    difs_configure(w->difs, boundary_filters, w->sim.coords_mapping, true, w->stream);
    io_configure(w->io, buffer_size, input_count, output_count, output_interpolation, true, w->stream);
    if (w->sim.pad_x == 0) { subgraph_configure<0>(*w, true); } else { subgraph_configure<1>(*w, true); }

    // Provide instance information
    if (nodes_distance != nullptr) *nodes_distance = 1.0f / w->sim.nodes_per_unit;
    if (size_x_n != nullptr) *size_x_n = w->sim.size_x;
    if (size_y_n != nullptr) *size_y_n = w->sim.size_y;
    if (size_z_n != nullptr) *size_z_n = w->sim.size_z;
    if (sim_memory_size != nullptr) *sim_memory_size = w->sim.allocation_size;
    if (io_memory_size != nullptr) *io_memory_size = w->io.allocation_size;

    CUDA_CHECK_ERROR(cudaStreamSynchronize(w->stream)) // This procedure is implicitly synchronous
    return w;
}

void dwr3_destroy(void *dwr3) {
    if (dwr3 == nullptr) return;
    auto *w = static_cast<dwr3_t *>(dwr3);

    sim_destroy(w->sim, w->stream);
    io_destroy(w->io, w->stream);
    subgraph_destroy(*w);

    CUDA_CHECK_ERROR(cudaStreamSynchronize(w->stream))
    CUDA_CHECK_ERROR(cudaStreamDestroy(w->stream)) // This procedure is implicitly synchronous
    free(w);
}

void dwr3_reset(void *dwr3) {
    assert(dwr3 != nullptr);
    const auto *w = static_cast<dwr3_t *>(dwr3);

    sim_reset(w->sim, w->stream);

    CUDA_CHECK_ERROR(cudaStreamSynchronize(w->stream)) // This procedure is implicitly synchronous
}

void dwr3_process(void *dwr3, const float *input_samples, const float *input_positions, float *output_samples,
                  const float *output_positions) {
    assert(dwr3 != nullptr);
    const auto *w = static_cast<dwr3_t *>(dwr3);
    io_transfer_host_to_device(w->io, input_samples, input_positions, output_positions, w->sim, w->stream);
    const int graph_launch_count = w->io.buffer_size / DWR3_BUFFER_BASE_SIZE;
    for (int i = 0; i < graph_launch_count; i++) CUDA_CHECK_ERROR(
        cudaGraphLaunch(w->subgraph_exec, w->stream))
    io_transfer_device_to_host(w->io, output_samples, w->stream);
    CUDA_CHECK_ERROR(cudaStreamSynchronize(w->stream)) // This procedure is implicitly synchronous
}
