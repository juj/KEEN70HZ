// BENCHVS.H: JukkaJ Sep 09 2023: Benchmark the vertical refresh rate
//                                and hblank length.

#ifndef BENCHVS_H
#define BENCHVS_H

// Benchmarks video refresh rate, and initializes all the parameters
// below.
#ifdef __cplusplus
extern "C"
#endif
void BenchmarkVideoRefreshRate(void);

// Contains max number of port I/O commands that can be achieved when
// inside vblank.
extern unsigned char MaxHblankLength;
// Contains video vertical reresh rate
extern unsigned char VideoRefreshRate;
// Set to 1 if VideoRefreshRateIs70Hz is about ~70Hz (+/- a few Hz)
extern unsigned char VideoRefreshRateIs70Hz;

#endif
