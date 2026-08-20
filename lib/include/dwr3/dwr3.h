#ifndef DWR3_H
#define DWR3_H

#ifdef __cplusplus
extern "C" {
#endif

/// The specification of DWR3_BUFFER_BASE_SIZE is provided to control the number of batched iterations per CUDA graph
/// instance to fine tune the batching performance similarly to what is described in
/// Ekelund, Jonah, Stefano Markidis, and Ivy Peng. "Boosting performance of iterative applications on gpus: Kernel batching with cuda graphs." 2025 33rd Euromicro International Conference on Parallel, Distributed, and Network-Based Processing (PDP). IEEE, 2025.
/**/
#ifndef DWR3_BUFFER_BASE_SIZE
/// The base size for I/O buffers in DWR3, ov
/// @note Must be an even number and a multiple of DWR3_BOUNDARY_FILTER_ORDER
/// @note 64 has been found to be a good value for real-time iteration on small-to-medium instances on GeForce RTX 40 series GPUs
#define DWR3_BUFFER_BASE_SIZE 64
#endif

/// The maximum amount of inputs and outputs allowed by DWR3
#define DWR3_MAX_IO 128

#ifndef DWR3_BOUNDARY_FILTER_ORDER
/// The order of the boundary filters used by DWR3
/// @note Must be an even number and a perfect divisor of DWR3_BOUNDARY_FILTER_ORDER
#define DWR3_BOUNDARY_FILTER_ORDER 8
#endif

/// IIR boundary reflectance filter coefficients
/// @note Can be provided with un-normalized a[0]
typedef struct {
    double b[DWR3_BOUNDARY_FILTER_ORDER + 1], a[DWR3_BOUNDARY_FILTER_ORDER + 1];
} dwr3_boundary_filter_t;

// ReSharper disable once CppUnusedIncludeDirective
#include <dwr3/gen/boundary_filters.h>

/// Indexing convention used in DWR3 to refer to boundary walls in linear arrays
typedef enum {
    /// X-negative axis index
    DWR3_AXIS_X_N = 0,
    /// X-positive axis index
    DWR3_AXIS_X_P = 1,
    /// Y-negative axis index
    DWR3_AXIS_Y_N = 2,
    /// Y-positive axis index
    DWR3_AXIS_Y_P = 3,
    /// Z-negative axis index
    DWR3_AXIS_Z_N = 4,
    /// Z-positive axis index
    DWR3_AXIS_Z_P = 5
} dwr3_axis_t;

/// Interpolation modes
typedef enum {
    /// Nearest neighbor
    DWR3_INTERPOLATION_NEAREST = 0,
    /// Linear interpolation
    DWR3_INTERPOLATION_LINEAR = 1,
} dwr3_interpolation_t;

/**
 * Creates a new DWR3 instance
 * @param size_x_m Physical size in meters on the x-axis
 * @param size_y_m Physical size in meters on the y-axis
 * @param size_z_m Physical size in meters on the z-axis
 * @param boundary_filters An array of 6 boundary filters pointers for each axis' wall, each pointer must be non-NULL
 * @param sample_rate A valid (greater than 0) sample rate value
 * @param buffer_size A valid (greater than 0) buffer size value, which must be a proper multiple of DWR3_BUFFER_BASE_SIZE
 * @param input_count The number of inputs, which must be less or equal than DWR3_MAX_IO
 * @param output_count The number of outputs, which must be less or equal than DWR3_MAX_IO
 * @param output_interpolation The outputs' sampling interpolation mode
 * @param nodes_distance If not NULL, returns the inter-nodal distance
 * @param size_x_n If not NULL, returns the nodes size of the simulation on the X-axis
 * @param size_y_n If not NULL, returns the nodes size of the simulation on the Y-axis
 * @param size_z_n If not NULL, returns the nodes size of the simulation on the Z-axis
 * @param sim_memory_size If not NULL, returns the CUDA memory footprint of the simulation component
 * @param io_memory_size If not NULL, returns the CUDA memory footprint of the I/O component
 * @return A non-NULL pointer to the DWR3 instance, if the creation fails then the implementation exits with error
 */
void *dwr3_create(float size_x_m, float size_y_m, float size_z_m, const dwr3_boundary_filter_t *boundary_filters[6],
                  double sample_rate, unsigned int buffer_size, unsigned int input_count, unsigned int output_count,
                  dwr3_interpolation_t output_interpolation, float *nodes_distance, int *size_x_n, int *size_y_n,
                  int *size_z_n, size_t *sim_memory_size, size_t *io_memory_size);

/**
 * Destroys a valid instance of DWR3
 * @param dwr3 A pointer to a valid DWR3 instance
 * @note The pointer can be NULL, in this case nothing happens
 */
void dwr3_destroy(void *dwr3);

/**
 * Resets the state of a valid DWR3 instance
 * @param dwr3 A non-NULL pointer to a valid DWR3 instance
 */
void dwr3_reset(void *dwr3);

/**
 * Processes synchronously a block of interleaved samples with a valid DWR3 instance
 * @param dwr3 A non-NULL pointer to a valid DWR3 instance
 * @param input_samples An array of buffer_size*input_count input samples, stored in interleaved format
 * @param input_positions An array of 3*input_count floating point values representing physical positions
 * @param output_samples An array of buffer_size*output_count output samples, stored in interleaved format
 * @param output_positions If output_interpolation is set DWR3_INTERPOLATION_NEAREST, an array of 3*output_count floating point values representing physical positions; if output_interpolation is set DWR3_INTERPOLATION_LINEAR, an array of 3*output_count*buffer_size floating point values representing physical positions at each sample
 * @note Physical positions for inputs or nearest neighbor outputs are provided as [x0, y0, z0, ... xn, yn, zn], with n corresponding to either input_count or output_count
 * @note Physical positions for interpolated outputs are provided as buffer_size consecutive sequences [x0, y0, z0, ... xn, yn, zn] (see nearest neighbor), with each repetition corresponding to the position at each sample of all receivers
 */
void dwr3_process(void *dwr3, const float *input_samples, const float *input_positions, float *output_samples,
                  const float *output_positions);

#ifdef __cplusplus
}
#endif

#endif // DWR3_H
