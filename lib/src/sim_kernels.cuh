/// Definitions of simulation step kernels

#ifndef DWR3_SIM_KERNELS_CUH
#define DWR3_SIM_KERNELS_CUH

/// The single time-step computations is split between border kernels and a single center kernel

/// Kernel block size constants
#define SIM_BORDER_BLOCK_DIM_X 32
#define SIM_BORDER_BLOCK_DIM_Y 4
#define SIM_CENTER_BLOCK_DIM_X 32
#define SIM_CENTER_BLOCK_DIM_Y 4
/// The center kernel uses a loop tiling technique to handle multiple z axis coordinates with a loop, the block contains
/// only SIM_CENTER_BLOCK_DIM_X x SIM_CENTER_BLOCK_DIM_Y threads
#ifndef SIM_CENTER_BLOCK_DIM_Z
/// 10 has been found to be a good value for real-time iteration on small-to-medium instances on GeForce RTX 40 series GPUs
#define SIM_CENTER_BLOCK_DIM_Z 10
#endif
/// Each thread in each warp for the center section kernel computes two adjacent x coordinates (with the first and last threads computing only one)
#define SIM_CENTER_BLOCK_COMPUTE_DIM_X (SIM_CENTER_BLOCK_DIM_X * 2 - 2)

/// Digital impedance filter coefficients, access the values via the provided dif_* functions
/// @note the a_0 coefficient is normalized to 1, it's not stored in memory, and it cannot be accessed via dif_a
struct dif_t {
    float _b_0_rec;
    float _b[DWR3_BOUNDARY_FILTER_ORDER + 1];
    float _a[DWR3_BOUNDARY_FILTER_ORDER];
};

/// Accessor to DIF b_0 reciprocal coefficient
__host__ __device__ float dif_b_0_rec(const dif_t &d);

/// Accessor to DIF b_i coefficient
__host__ __device__ float dif_b(const dif_t &d, int i);

/// Accessor to DIF a_i coefficient
__host__ __device__ float dif_a(const dif_t &d, int i);

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Macros used to implement kernel boundary parameters passage,
/// This is used since the __restrict__ attribute is ignored for non-base types such as arrays of __restrict__
/// pointers and structs containing __restrict__ pointers
#if DWR3_BOUNDARY_FILTER_ORDER > 6
#define MACRO_LIST_EXPANSION_7(PRE_A, PRE_C, POST_C, POST_A) , PRE_A PRE_C##7##POST_C POST_A
#define MACRO_LIST_EXPANSION_6(PRE_A, PRE_C, POST_C, POST_A)                                                           \
    , PRE_A PRE_C##6##POST_C POST_A MACRO_LIST_EXPANSION_7(PRE_A, PRE_C, POST_C, POST_A)
#else
#define MACRO_LIST_EXPANSION_6(PRE_A, PRE_C, POST_C, POST_A)
#endif

#if DWR3_BOUNDARY_FILTER_ORDER > 4
#define MACRO_LIST_EXPANSION_5(PRE_A, PRE_C, POST_C, POST_A)                                                           \
    , PRE_A PRE_C##5##POST_C POST_A MACRO_LIST_EXPANSION_6(PRE_A, PRE_C, POST_C, POST_A)
#define MACRO_LIST_EXPANSION_4(PRE_A, PRE_C, POST_C, POST_A)                                                           \
    , PRE_A PRE_C##4##POST_C POST_A MACRO_LIST_EXPANSION_5(PRE_A, PRE_C, POST_C, POST_A)
#else
#define MACRO_LIST_EXPANSION_4(PRE_A, PRE_C, POST_C, POST_A)
#endif

#if DWR3_BOUNDARY_FILTER_ORDER > 2
#define MACRO_LIST_EXPANSION_3(PRE_A, PRE_C, POST_C, POST_A)                                                           \
    , PRE_A PRE_C##3##POST_C POST_A MACRO_LIST_EXPANSION_4(PRE_A, PRE_C, POST_C, POST_A)
#define MACRO_LIST_EXPANSION_2(PRE_A, PRE_C, POST_C, POST_A)                                                           \
    , PRE_A PRE_C##2##POST_C POST_A MACRO_LIST_EXPANSION_3(PRE_A, PRE_C, POST_C, POST_A)
#else
#define MACRO_LIST_EXPANSION_2(PRE_A, PRE_C, POST_C, POST_A)
#endif

#if DWR3_BOUNDARY_FILTER_ORDER > 1
#define MACRO_LIST_EXPANSION_1(PRE_A, PRE_C, POST_C, POST_A)                                                           \
    , PRE_A PRE_C##1##POST_C POST_A MACRO_LIST_EXPANSION_2(PRE_A, PRE_C, POST_C, POST_A)
#else
#define MACRO_LIST_EXPANSION_1(PRE_A, PRE_C, POST_C, POST_A)
#endif

#define MACRO_LIST_EXPANSION_0(PRE_A, PRE_C, POST_C, POST_A)                                                           \
    PRE_A PRE_C##0##POST_C POST_A MACRO_LIST_EXPANSION_1(PRE_A, PRE_C, POST_C, POST_A)

/// Macro used to expand kernel boundary formal parameters
#define KERNEL_BOUNDARY_FORMAL_PARAMS(SUFFIX)                                                                          \
    float *__restrict__ b_##SUFFIX##_g,                                                                                \
            float *__restrict__ b_##SUFFIX##_x0 MACRO_LIST_EXPANSION_1(, const float *__restrict__ b_##SUFFIX##_x,     \
                                                                       , ),                                            \
            float *__restrict__ b_##SUFFIX##_y0 MACRO_LIST_EXPANSION_1(, const float *__restrict__ b_##SUFFIX##_y,     \
                                                                       , ),                                            \
            const __grid_constant__ dif_t d_##SUFFIX

/// Since the MACRO_LIST_EXPANSION_N go up to 7, DWR3_BOUNDARY_FILTER_ORDER greater than 8 is currently unsupported
static_assert(DWR3_BOUNDARY_FILTER_ORDER <= 8,
              "DWR3_BOUNDARY_FILTER_ORDER greater than 8 is currently unsupported");

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Update a boundary filter state
inline __device__ void
update_filter(const float o, const float n, float *__restrict__ const b__g,
              float *__restrict__ const b__x0 MACRO_LIST_EXPANSION_1(, const float *__restrict__ const b__x, ,),
              float *__restrict__ const b__y0 MACRO_LIST_EXPANSION_1(, const float *__restrict__ const b__y, ,),
              const dif_t &d_) {
    float g = *b__g;
    const float x0 = (L1_REC * (n - o) - g) * dif_b_0_rec(d_);
    const float y0 = dif_b(d_, 0) * x0 + g;

    g = dif_b(d_, 1) * x0 - dif_a(d_, 1) * y0;
#if DWR3_BOUNDARY_FILTER_ORDER > 1
    g += dif_b(d_, 2) * *b__x1 - dif_a(d_, 2) * *b__y1;
#endif
#if DWR3_BOUNDARY_FILTER_ORDER > 2
    g += dif_b(d_, 3) * *b__x2 - dif_a(d_, 3) * *b__y2;
    g += dif_b(d_, 4) * *b__x3 - dif_a(d_, 4) * *b__y3;
#endif
#if DWR3_BOUNDARY_FILTER_ORDER > 4
    g += dif_b(d_, 5) * *b__x4 - dif_a(d_, 5) * *b__y4;
    g += dif_b(d_, 6) * *b__x5 - dif_a(d_, 6) * *b__y5;
#endif
#if DWR3_BOUNDARY_FILTER_ORDER > 6
    g += dif_b(d_, 7) * *b__x6 - dif_a(d_, 7) * *b__y6;
    g += dif_b(d_, 8) * *b__x7 - dif_a(d_, 8) * *b__y7;
#endif

    *b__g = g;
    *b__x0 = x0;
    *b__y0 = y0;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Set of macros used to parameterize the generic boundary kernel implementations

/// First step macros
/**/
/// Gather X- boundary parameters WITH a coordinate check
#define UPDATE_MACRO_X1N                                                                                               \
    int xnd = -1;                                                                                                      \
    if (x == 0) {                                                                                                      \
        xnd = 1;                                                                                                       \
        b += dif_b_0_rec(d_xn);                                                                                        \
        g += b_xn_g[SIM_X_INDEX(y, z)] * dif_b_0_rec(d_xn);                                                            \
    }
/// Gather X- boundary parameters WITHOUT a coordinate check
#define UPDATE_MACRO_X1NS                                                                                              \
    {                                                                                                                  \
        b += dif_b_0_rec(d_xn);                                                                                        \
        g += b_xn_g[SIM_X_INDEX(y, z)] * dif_b_0_rec(d_xn);                                                            \
    }
/// Gather X+ boundary parameters WITH a coordinate check
#define UPDATE_MACRO_X1P                                                                                               \
    int xpd = 1;                                                                                                       \
    if (x == size_x - 1) {                                                                                             \
        xpd = -1;                                                                                                      \
        b += dif_b_0_rec(d_xp);                                                                                        \
        g += b_xp_g[SIM_X_INDEX(y, z)] * dif_b_0_rec(d_xp);                                                            \
    }
/// Gather X+ boundary parameters WITHOUT a coordinate check
#define UPDATE_MACRO_X1PS                                                                                              \
    {                                                                                                                  \
        b += dif_b_0_rec(d_xp);                                                                                        \
        g += b_xp_g[SIM_X_INDEX(y, z)] * dif_b_0_rec(d_xp);                                                            \
    }
/// Gather Y- boundary parameters WITH a coordinate check
#define UPDATE_MACRO_Y1N                                                                                               \
    int ynd = -(size_x + pad_x);                                                                                       \
    if (y == 0) {                                                                                                      \
        ynd = (size_x + pad_x);                                                                                        \
        b += dif_b_0_rec(d_yn);                                                                                        \
        g += b_yn_g[SIM_Y_INDEX(x, z)] * dif_b_0_rec(d_yn);                                                            \
    }
/// Gather Y- boundary parameters WITHOUT a coordinate check
#define UPDATE_MACRO_Y1NS                                                                                              \
    {                                                                                                                  \
        b += dif_b_0_rec(d_yn);                                                                                        \
        g += b_yn_g[SIM_Y_INDEX(x, z)] * dif_b_0_rec(d_yn);                                                            \
    }
/// Gather Y+ boundary parameters WITH a coordinate check
#define UPDATE_MACRO_Y1P                                                                                               \
    int ypd = (size_x + pad_x);                                                                                        \
    if (y == size_y - 1) {                                                                                             \
        ypd = -(size_x + pad_x);                                                                                       \
        b += dif_b_0_rec(d_yp);                                                                                        \
        g += b_yp_g[SIM_Y_INDEX(x, z)] * dif_b_0_rec(d_yp);                                                            \
    }
/// Gather Y+ boundary parameters WITHOUT a coordinate check
#define UPDATE_MACRO_Y1PS                                                                                              \
    {                                                                                                                  \
        b += dif_b_0_rec(d_yp);                                                                                        \
        g += b_yp_g[SIM_Y_INDEX(x, z)] * dif_b_0_rec(d_yp);                                                            \
    }
/// Gather Z- boundary parameters WITH a coordinate check
#define UPDATE_MACRO_Z1N                                                                                               \
    int znd = -(size_x + pad_x) * size_y;                                                                              \
    if (z == 0) {                                                                                                      \
        znd = (size_x + pad_x) * size_y;                                                                               \
        b += dif_b_0_rec(d_zn);                                                                                        \
        g += b_zn_g[SIM_Z_INDEX(x, y)] * dif_b_0_rec(d_zn);                                                            \
    }
/// Gather Z- boundary parameters WITHOUT a coordinate check
#define UPDATE_MACRO_Z1NS                                                                                              \
    {                                                                                                                  \
        b += dif_b_0_rec(d_zn);                                                                                        \
        g += b_zn_g[SIM_Z_INDEX(x, y)] * dif_b_0_rec(d_zn);                                                            \
    }
/// Gather Z+ boundary parameters WITH a coordinate check
#define UPDATE_MACRO_Z1P                                                                                               \
    int zpd = (size_x + pad_x) * size_y;                                                                               \
    if (z == size_z - 1) {                                                                                             \
        zpd = -(size_x + pad_x) * size_y;                                                                              \
        b += dif_b_0_rec(d_zp);                                                                                        \
        g += b_zp_g[SIM_Z_INDEX(x, y)] * dif_b_0_rec(d_zp);                                                            \
    }
/// Gather Z+ boundary parameters WITHOUT a coordinate check
#define UPDATE_MACRO_Z1PS                                                                                              \
    {                                                                                                                  \
        b += dif_b_0_rec(d_zp);                                                                                        \
        g += b_zp_g[SIM_Z_INDEX(x, y)] * dif_b_0_rec(d_zp);                                                            \
    }

/// Actual parameters used by macros for update_filter in the second step
#define BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(SUF, I)                                                               \
    b_##SUF##_g + (I), MACRO_LIST_EXPANSION_0(, b_##SUF##_x, , +(I)), MACRO_LIST_EXPANSION_0(, b_##SUF##_y, , +(I)),   \
            d_##SUF

/// Second step macros
/**/
/// Update X- boundary state WITH a coordinate check
#define UPDATE_MACRO_X2N                                                                                               \
    if (x == 0) { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(xn, SIM_X_INDEX(y, z))); }
/// Update X- boundary state WITHOUT a coordinate check
#define UPDATE_MACRO_X2NS                                                                                              \
    { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(xn, SIM_X_INDEX(y, z))); }
/// Update X+ boundary state WITH a coordinate check
#define UPDATE_MACRO_X2P                                                                                               \
    if (x == size_x - 1) { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(xp, SIM_X_INDEX(y, z))); }
/// Update X+ boundary state WITHOUT a coordinate check
#define UPDATE_MACRO_X2PS                                                                                              \
    { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(xp, SIM_X_INDEX(y, z))); }
/// Update Y- boundary state WITH a coordinate check
#define UPDATE_MACRO_Y2N                                                                                               \
    if (y == 0) { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(yn, SIM_Y_INDEX(x, z))); }
/// Update Y- boundary state WITHOUT a coordinate check
#define UPDATE_MACRO_Y2NS                                                                                              \
    { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(yn, SIM_Y_INDEX(x, z))); }
/// Update Y+ boundary state WITH a coordinate check
#define UPDATE_MACRO_Y2P                                                                                               \
    if (y == size_y - 1) { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(yp, SIM_Y_INDEX(x, z))); }
/// Update Y+ boundary state WITHOUT a coordinate check
#define UPDATE_MACRO_Y2PS                                                                                              \
    { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(yp, SIM_Y_INDEX(x, z))); }
/// Update Z- boundary state WITH a coordinate check
#define UPDATE_MACRO_Z2N                                                                                               \
    if (z == 0) { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(zn, SIM_Z_INDEX(x, y))); }
/// Update Z- boundary state WITHOUT a coordinate check
#define UPDATE_MACRO_Z2NS                                                                                              \
    { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(zn, SIM_Z_INDEX(x, y))); }
/// Update Z+ boundary state WITH a coordinate check
#define UPDATE_MACRO_Z2P                                                                                               \
    if (z == size_z - 1) { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(zp, SIM_Z_INDEX(x, y))); }
/// Update Z+ boundary state WITHOUT a coordinate check
#define UPDATE_MACRO_Z2PS                                                                                              \
    { update_filter(o, n, BOUNDARY_ACTUAL_PARAMETERS_KERNEL_FILTER(zp, SIM_Z_INDEX(x, y))); }

/// Macro to update a single side in a fully generic way
#define UPDATE_MACRO(VARS, S1, S2)                                                                                     \
    {                                                                                                                  \
        VARS;                                                                                                          \
        const int i = SIM_I_INDEX(x, y, z);                                                                            \
        const float *p_r = p + i;                                                                                      \
        float *p_aux_r = p_aux + i;                                                                                    \
        float g = 0;                                                                                                   \
        float b = 0;                                                                                                   \
        S1;                                                                                                            \
        const float o = *p_aux_r;                                                                                      \
        float n = p_r[znd];                                                                                            \
        n += p_r[ynd];                                                                                                 \
        n += p_r[xnd];                                                                                                 \
        n += p_r[xpd];                                                                                                 \
        n += p_r[ypd];                                                                                                 \
        n += p_r[zpd];                                                                                                 \
        n = (D1 * n + L2 * g + (L1 * b - 1.0f) * o) / (L1 * b + 1.0f);                                                 \
        *p_aux_r = n;                                                                                                  \
        S2;                                                                                                            \
    }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/// Each of the boundary kernels maps the coordinates to the respective boundaries and performs the UPDATE_MACRO
/// The kernels use reverse_z to reverse the mapping of threads on the z axis
/// THe kernels use pad_x to correctly compute the p arrays coordinates (padding of 1 is added if size_x is odd)
/**/
/// X- and X+ boundaries single-time-step update handling kernel
template<bool reverse_z, int pad_x>
__global__ void __launch_bounds__(SIM_BORDER_BLOCK_DIM_X * SIM_BORDER_BLOCK_DIM_Y)
sim_iter_x(const int size_x, const int size_y, const int size_z, const float *__restrict__ p,
           float *__restrict__ p_aux, KERNEL_BOUNDARY_FORMAL_PARAMS(xn), KERNEL_BOUNDARY_FORMAL_PARAMS(xp)) {
    const int y = threadIdx.x + blockIdx.x * SIM_BORDER_BLOCK_DIM_X + 1;
    const int z = !reverse_z
                      ? threadIdx.y + blockIdx.y * SIM_BORDER_BLOCK_DIM_Y + 1
                      : size_z - 1 - (threadIdx.y + blockIdx.y * SIM_BORDER_BLOCK_DIM_Y + 1);
    if (!(y < size_y - 1 && ((z < size_z - 1 && !reverse_z) || (z > 0 && reverse_z)))) return;

    const int ynd = -(size_x + pad_x);
    const int ypd = (size_x + pad_x);
    const int znd = !reverse_z ? -((size_x + pad_x) * size_y) : (size_x + pad_x) * size_y;
    const int zpd = !reverse_z ? (size_x + pad_x) * size_y : -((size_x + pad_x) * size_y);
    UPDATE_MACRO(constexpr int x = 0; constexpr int xnd = 1; constexpr int xpd = 1, //
                 UPDATE_MACRO_X1NS, //
                 UPDATE_MACRO_X2NS)
    UPDATE_MACRO(const int x = size_x - 1; constexpr int xnd = -1; constexpr int xpd = -1, //
                 UPDATE_MACRO_X1PS, //
                 UPDATE_MACRO_X2PS)
}

/// Y- and Y+ boundaries single-time-step update handling kernel
template<bool reverse_z, int pad_x>
__global__ void __launch_bounds__(SIM_BORDER_BLOCK_DIM_X * SIM_BORDER_BLOCK_DIM_Y)
sim_iter_y(const int size_x, const int size_y, const int size_z, const float *__restrict__ p,
           float *__restrict__ p_aux, KERNEL_BOUNDARY_FORMAL_PARAMS(xn), KERNEL_BOUNDARY_FORMAL_PARAMS(xp),
           KERNEL_BOUNDARY_FORMAL_PARAMS(yn), KERNEL_BOUNDARY_FORMAL_PARAMS(yp)) {
    const int x = threadIdx.x + blockIdx.x * SIM_BORDER_BLOCK_DIM_X;
    const int z = !reverse_z
                      ? threadIdx.y + blockIdx.y * SIM_BORDER_BLOCK_DIM_Y + 1
                      : size_z - 1 - (threadIdx.y + blockIdx.y * SIM_BORDER_BLOCK_DIM_Y + 1);
    if (!(x < size_x && ((z < size_z - 1 && !reverse_z) || (z > 0 && reverse_z)))) return;

    const int znd = !reverse_z ? -((size_x + pad_x) * size_y) : (size_x + pad_x) * size_y;
    const int zpd = !reverse_z ? (size_x + pad_x) * size_y : -((size_x + pad_x) * size_y);
    UPDATE_MACRO(constexpr int y = 0; const int ynd = (size_x + pad_x);
                 const int ypd = (size_x + pad_x), //
                 UPDATE_MACRO_X1N UPDATE_MACRO_X1P UPDATE_MACRO_Y1NS, //
                 UPDATE_MACRO_X2N UPDATE_MACRO_X2P UPDATE_MACRO_Y2NS)
    UPDATE_MACRO(const int y = size_y - 1; const int ynd = -(size_x + pad_x);
                 const int ypd = -(size_x + pad_x), //
                 UPDATE_MACRO_X1N UPDATE_MACRO_X1P UPDATE_MACRO_Y1PS, //
                 UPDATE_MACRO_X2N UPDATE_MACRO_X2P UPDATE_MACRO_Y2PS)
}

/// Z- boundary single-time-step update handling kernel
template<int pad_x>
__global__ void __launch_bounds__(SIM_BORDER_BLOCK_DIM_X * SIM_BORDER_BLOCK_DIM_Y)
sim_iter_z_n(const int size_x, const int size_y, const float *__restrict__ p, float *__restrict__ p_aux,
             KERNEL_BOUNDARY_FORMAL_PARAMS(xn), KERNEL_BOUNDARY_FORMAL_PARAMS(xp),
             KERNEL_BOUNDARY_FORMAL_PARAMS(yn), KERNEL_BOUNDARY_FORMAL_PARAMS(yp),
             KERNEL_BOUNDARY_FORMAL_PARAMS(zn)) {
    const int x = threadIdx.x + blockIdx.x * SIM_BORDER_BLOCK_DIM_X;
    const int y = threadIdx.y + blockIdx.y * SIM_BORDER_BLOCK_DIM_Y;
    if (!(x < size_x && y < size_y)) return;
    UPDATE_MACRO(constexpr int z = 0; const int znd = (size_x + pad_x) * size_y;
                 const int zpd = (size_x + pad_x) * size_y, //
                 UPDATE_MACRO_X1N UPDATE_MACRO_X1P UPDATE_MACRO_Y1N UPDATE_MACRO_Y1P UPDATE_MACRO_Z1NS, //
                 UPDATE_MACRO_X2N UPDATE_MACRO_X2P UPDATE_MACRO_Y2N UPDATE_MACRO_Y2P UPDATE_MACRO_Z2NS)
}

/// Z+ boundary single-time-step update handling kernel
template<int pad_x>
__global__ void __launch_bounds__(SIM_BORDER_BLOCK_DIM_X * SIM_BORDER_BLOCK_DIM_Y)
sim_iter_z_p(const int size_x, const int size_y, const int size_z, const float *__restrict__ p,
             float *__restrict__ p_aux, KERNEL_BOUNDARY_FORMAL_PARAMS(xn), KERNEL_BOUNDARY_FORMAL_PARAMS(xp),
             KERNEL_BOUNDARY_FORMAL_PARAMS(yn), KERNEL_BOUNDARY_FORMAL_PARAMS(yp),
             KERNEL_BOUNDARY_FORMAL_PARAMS(zp)) {
    const int x = threadIdx.x + blockIdx.x * SIM_BORDER_BLOCK_DIM_X;
    const int y = threadIdx.y + blockIdx.y * SIM_BORDER_BLOCK_DIM_Y;
    if (!(x < size_x && y < size_y)) return;
    UPDATE_MACRO(const int z = size_z - 1; const int znd = -(size_x + pad_x) * size_y;
                 const int zpd = -(size_x + pad_x) * size_y, //
                 UPDATE_MACRO_X1N UPDATE_MACRO_X1P UPDATE_MACRO_Y1N UPDATE_MACRO_Y1P UPDATE_MACRO_Z1PS, //
                 UPDATE_MACRO_X2N UPDATE_MACRO_X2P UPDATE_MACRO_Y2N UPDATE_MACRO_Y2P UPDATE_MACRO_Z2PS)
}

/// Center section single-time-step update handling kernel
template<bool reverse_z, int pad_x>
__global__ void __launch_bounds__(SIM_CENTER_BLOCK_DIM_X * SIM_CENTER_BLOCK_DIM_Y)
sim_iter_c(const int size_x, const int size_y, const int size_z, const float *__restrict__ p,
           float *__restrict__ p_aux) {
    // Each thread in each warp computes two adjacent x coordinates (with the first and last threads computing only one)
    const int g_x = threadIdx.x * 2 + blockIdx.x * SIM_CENTER_BLOCK_COMPUTE_DIM_X;
    const int g_y = threadIdx.y + blockIdx.y * SIM_CENTER_BLOCK_DIM_Y + 1;

    // Early exit for out of bounds kernels, the active mask is obtained for later shuffle operations
    if (g_x >= size_x || g_y >= size_y - 1) return;
    const unsigned active = __activemask();

    const int g_z_start =
            !reverse_z ? blockIdx.z * SIM_CENTER_BLOCK_DIM_Z : size_z - blockIdx.z * SIM_CENTER_BLOCK_DIM_Z - 1;

    // To check if each thread needs to write either one of its values, a boolean for each value is checked when writing
    const bool write_1 = threadIdx.x > 0 && g_x < size_x - 1, write_2 = threadIdx.x < 31 && g_x < size_x - 2;

    // p and p_aux are iterated over via pointers arithmetics to increment between xy planes
    const int g_base_xyz = SIM_I_INDEX(g_x, g_y, g_z_start);
    const int g_offset_xyz = !reverse_z ? (size_x + pad_x) * size_y : -((size_x + pad_x) * size_y);
    p += g_base_xyz;
    p_aux += g_base_xyz;

    // Loop tiling technique inspired from the stencil computation chapter in
    // Wen-Mei, W. Hwu, David B. Kirk, and Izzat El Hajj. Programming massively parallel processors: a hands-on approach. Morgan Kaufmann, 2026.
    float2 p_prev_r = *reinterpret_cast<const float2 *>(p);
    p += g_offset_xyz;
    float2 p_curr_r = *reinterpret_cast<const float2 *>(p);

    for (int z_i = 1; z_i <= SIM_CENTER_BLOCK_DIM_Z; z_i++) {
        if (!((z_i + g_z_start < size_z - 1 && !reverse_z) || (g_z_start - z_i > 0 && reverse_z))) return;

        // Stencil computation for center section
        const float2 read_p_yn = *reinterpret_cast<const float2 *>(p - size_x - pad_x);
        p_prev_r.x += read_p_yn.x;
        p_prev_r.y += read_p_yn.y;
        p_prev_r.x += __shfl_up_sync(active, p_curr_r.y, 1);
        p_prev_r.x += p_curr_r.y;
        p_prev_r.y += p_curr_r.x;
        p_prev_r.y += __shfl_down_sync(active, p_curr_r.x, 1);
        const float2 read_p_yp = *reinterpret_cast<const float2 *>(p + size_x + pad_x);
        p_prev_r.x += read_p_yp.x;
        p_prev_r.y += read_p_yp.y;
        p += g_offset_xyz;
        const float2 read_p_zp = *reinterpret_cast<const float2 *>(p);
        p_prev_r.x += read_p_zp.x;
        p_prev_r.y += read_p_zp.y;

        // Read and compute new values
        p_aux += g_offset_xyz;
        float2 read_p_aux = *reinterpret_cast<float2 *>(p_aux);
        read_p_aux.x = D1 * p_prev_r.x - read_p_aux.x;
        read_p_aux.y = D1 * p_prev_r.y - read_p_aux.y;

        // Write only the correct values (the first and last threads compute at most 1 valid value)
        // This way of writing back to memory has been found to be relatively efficient compared to alternatives
        if (write_1 && write_2) *reinterpret_cast<float2 *>(p_aux) = read_p_aux;
        if (write_1 && !write_2) *p_aux = read_p_aux.x;
        if (!write_1 && write_2) *(p_aux + 1) = read_p_aux.y;

        p_prev_r = p_curr_r;
        p_curr_r = read_p_zp;
    }
}

#endif // DWR3_SIM_KERNELS_CUH
