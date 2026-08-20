### CLI Tool

A very simple Command Line Interface tool that allows to render offline the auralization of a single source
from a single receiver.

This tool expects arguments in the following format:

`dwr3_cli <x size> <y size> <z size> <source x> <source y> <source z> <receiver x> <receiver y> <receiver z> <source input file (.wav)> <receiver output file (.wav)> <source input file peak dB-SPL @ 1m> <receiver output dB-FS sensitivity> <receiver interpolation (0=off or 1=on)> <n. of processed chunks (OPTIONAL)>`

with sizes and positions provided in meters. The input `.wav` file must have a float32 format and a single channel.

This tool uses the same wall materials configuration as the case study mentioned in
*Oxnard, Stephen, et al. "Frequency-Dependent Absorbing Boundary Implementations in 3D Finite Difference Time Domain
Room Acoustics Simulations." Proceedings of EURONOISE, Maastricht, The Netherlands (2015)*, with an Y+ axis up
coordinates system.