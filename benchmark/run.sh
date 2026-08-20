#!/bin/bash

fs=22050 # sample rate
buf_size=128 # buffer size
samples=101 # 101 because the first sample is discarded during data analysis
step=0.0265 # step every node size increment
interp=0 # switch to 1 to test with linear interpolation for outputs
from=1 # smallest tested size, "to" is used for the largest size

run_benchmark() {
  program_name="`basename $program_file`"
  program_name_pretty=${program_name#"dwr3_benchmark_"}
  echo "-> running $program_name_pretty with ${n_io} inputs and outputs"
  out_file="./build/benchmark/${program_name_pretty}_io_${n_io}.csv"
  out_files="$out_files $out_file"
  eval "$program_file $fs $buf_size $samples $from $to $step $n_io $interp" > "${out_file}"
}

n_io=1 # Test with 1 input and 1 output

for program_file in ./build/benchmark/dwr3_benchmark_bbs*; do
  to=3.5 # on RTX 4050 Laptop, 5.75 on RTX 4090
  run_benchmark
done

for program_file in ./build/benchmark/dwr3_benchmark_c*; do
  to=3.5 # on RTX 4050 Laptop, 5.75 on RTX 4090
  run_benchmark
done

for program_file in ./build/benchmark/dwr3_benchmark_ud*; do
  to=5 # on RTX 4050 Laptop, 6.75 on RTX 4090
  run_benchmark
done

for program_file in ./build/benchmark/dwr3_benchmark_rot*; do
  to=7 # on RTX 4050 Laptop, 11.5 on RTX 4090 (long floor side)
  run_benchmark
done

n_io=128 # Test with 128 inputs and 128 outputs

for program_file in ./build/benchmark/dwr3_benchmark_ud*; do
  to=5 # on RTX 4050 Laptop, 6.75 on RTX 4090
  run_benchmark
done

for program_file in ./build/benchmark/dwr3_benchmark_rot*; do
  to=7 # on RTX 4050 Laptop, 11.5 on RTX 4090 (long floor side)
  run_benchmark
done