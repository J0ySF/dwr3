# Dynamic Wave-based Rectangular Room Reverb

DWR3 (Dynamic Wave-based Rectangular Room Reverb) is a GPU-accelerated sound wave propagation model, suitable
for real-time rendering of acoustic reverberation in small to medium rectangular enclosures provided with tunable
absorbing walls.
The implementation is based on the CUDA platform, computing a known Finite-Difference Time-Domain (FDTD) scheme which is
known to perform efficiently on 3D rectangular geometries and furthermore allows for the inclusion of user-defined
boundary filters modeling wall absorption.

A [Digital Audio Workstation (DAW) plugin](plugin/README.md) capable of rendering multiple omnidirectional sources and a
receiver modeling an Ambisonics microphone capture has been developed, enabling dynamic auralization of rectangular
rooms.
See [`plugin/README.md`](plugin/README.md) for more information.

Output samples and plugin usage output examples are provided in the directory [`examples`](examples/README.md) for
immediate
access to auralization examples, see [`examples/README.md`](examples/README.md) for more information.

No pre-built binaries are provided at the moment, and the project must be built from source (read below for more
information).
The implementation and instructions provided in this document have been tested on Linux Ubuntu 24.04 and
Linux Ubuntu 26.04.

### Implementation

The subdirectory `lib` contains the implementation of the GPU-accelerated model, in the form of a static library.
This allows for the implementation to be accessed via the C interface defined in `lib/include/dwr3/dwr3.h`, see the
[`cli_tool`](cli_tool/README.md) source code for a very simple usage example.

The FDTD scheme implemented is based on the SLF scheme presented in *Kowalczyk, Konrad, and Maarten Van Walstijn. "Room
acoustics simulation using 3-D compact explicit FDTD schemes." IEEE Transactions on Audio, Speech, and Language
Processing 19.1 (2010): 34-46.*

> Note: This implementation assumes a relatively recent NVIDIA GPU is used if real-time computation is desired, since
> the recent
> generations' increases to L2 cache size greatly improve memory access efficiency for this scheme, and the
> implementation
> relies on this fact for viability.

### Benchmarks

The subdirectory `benchmark` contains the executable implementation used to test for various properties of the model
implementation. After building from source (see below), the `benchmark/run.sh` script is provided to reproduce
each benchmark. The script is can be run from the project's base directory as `./benchmark/run.sh`, producing
measurements with the `.csv` format in the `build/benchmark` directory, with the following naming conventions:

* `bbs` (batch-block-size): tests for varying CUDA graph sizes,
* `c` (center kernel stride): tests for different Z-axis lengths processed by each "center section kernel" block,
* `ud` (up-down): compares the computation efficiency without and with swapping the assignment direction of blocks to
  nodes relative to `blockIdx.z` on consecutive iterations. The "up-down" memory scanning pattern has been found to
  improve performance on instances where significant amounts of simulation data fits at the same time in L2 cache.
* `rot` (rotation): compares the time for computation without and with enclosure rotations with the purpose of keeping
  less efficient boundary computations as small as possible (the X-axis sides of the enclosure require more
  non-coalesced memory accesses than the rest, so shrinking them and growing other sides is beneficial).

Each measurements file's name has suffix `_io_*`, indicating the amount of sources and receivers that have been
employed in the place of `*`.

## Build from source

### Requirements

* This repository, which must be cloned with submodules (`git clone --recurse-submodules https://github.com/J0ySF/dwr3`)
  in order to clone the dependencies in `third_party`
* The `build-essential` package for Debian-based Linux distibutions (or equivalent for other distibutions)
* CMake (`3.17` or newer)
* CUDA toolkit (tested with version `release 13.1, V13.1.115`)
* To build the plugin, make sure to check out the requirements at https://github.com/juce-framework/JUCE

### Build instructions

In the project's base directory, run `cmake -DCMAKE_CUDA_ARCHITECTURES=XX -B build && make -C build`, with `XX`
corresponding to your Compute Capability of choice (as an example `-DCMAKE_CUDA_ARCHITECTURES=89` for RTX 40 series
GPUs).

#### Build options

The CMake options `DWR3_BUILD_CLI_TOOL`, `DWR3_BUILD_BENCHMARKS`, `DWR3_BUILD_DAW_PLUGIN` are provided to allow
disabling the building of the respective optional project components (for example, to disable the benchmarks add
`-DDWR3_BUILD_BENCHMARKS=OFF` before `-B`).

The `lib/include/dwr3/dwr3.h` header exposes some user-definable parameters, such as:

* `DWR3_BOUNDARY_FILTER_ORDER`: the order of boundary filters (must be either 1 or a positive even number less or equal
  than 8),
* `DWR3_BUFFER_BASE_SIZE`: the base buffer size used in the implementation for the purposes of batch-processing on GPU,
  must be a multiple of `DWR3_BOUNDARY_FILTER_ORDER`. This value also restricts the buffer size for instances, which
  must be a multiple of `DWR3_BUFFER_BASE_SIZE`.

The default definitions are `-DDWR3_BOUNDARY_FILTER_ORDER=8`, `-DDWR3_BUFFER_BASE_SIZE=64`.