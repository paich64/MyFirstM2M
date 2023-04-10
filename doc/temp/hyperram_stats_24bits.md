This document contains statistics about the HyperRAM usage.

The HyperRAM usage is independent of output resolutions; only depends on input
resolution, and on output frame rate.

The starting point is the Demo Core, which generates a video output of 720x576
visible pixels at 50 Hz.

In this experiment there are two ascalers, one connected to VGA output (50 Hz)
and another connected to HDMI output (50 Hz).

Both ascalers are configured for 24 bit pixel color format, i.e. 3 bytes per
pixel.

The HyperRAM word width is also 16 bits, so one pixel fits into 1.5 words.

All numbers below are expressed in HyperRAM words of 16 bits.

## Theoretical values
The HyperRAM clock frequency is 100 MHz. This means that the theoretical
maximum bandwidth of the HyperRAM is 100 Mwords per second.

### Writing to HyperRAM
The amount of video data generated can be calculated as `720x576x50*3/2` = 31.1
Mwords per second.

### Reading from HyperRAM
The same video data must be read from HyperRAM as well, but perhaps with a
different frame rate.  At 60 Hz we get the following numbers: `720x576x60*3/2` =
37.3 Mwords per second.

### Total minimum bandwidth required
The video data must be written once and read twice. So at 50 Hz frame rate on
both VGA and HDMI, the combined bandwidth is `3x31.1` = 93.3 Mwords per second,
i.e. 93% of the available memory bandwidth.


## Measured values

All counters below are number of HyperRAM clock cycles and therefore are in
units of 16-bit words. The values are recorded after exactly one second.

### HDMI ascaler

```
WRITE       : 29_258_880
READ        : 22_739_328
WAIT_WR_TOT : 30_332_612
WAIT_WR_MAX :        429
WAIT_RD_TOT : 25_800_406
WAIT_RD_MAX :        293
```

So in conclusion we see that the HDMI ascaler spends approx 29% of the time
writing to HyperRAM, and 23% time reading from the HyperRAM.

### VGA ascaler

The VGA ascaler only does reads.

```
WRITE       :          0
READ        : 33_235_200
WAIT_WR_TOT :          0
WAIT_WR_MAX :          0
WAIT_RD_TOT : 33_100_530
WAIT_RD_MAX :        514
```

### HyperRAM arbiter

The two ascalers contend for access to the HyperRAM, and this contention is handled
by the HyperRAM arbiter. Statistics from this arbiter are as follows:

```
GRANT_VGA     : 36_732_702
WAIT_VGA      : 24_903_886
WAIT_VGA_MAX  :        143
GRANT_HDMI    : 57_231_347
WAIT_HDMI     : 33_811_016
WAIT_HDMI_MAX :        143
```

These numbers show that the ascaler for the HDMI output (which does both write
and read transactions) occupies the HyperRAM 57% of the time, while the VGA
output (which only does read transactions) uses 37% of the HyperRAM bandwidth.
The remaining 6% of the time the HyperRAM is idle.

Furthermore, these numbers confirm that the maximum wait time is the same for
the two ascalers. This shows the arbiter does a good job of ensuring a fair
share of the HyperRAM to each ascaler.

### HyperRAM controller

Finally, we look at the statistics of the HyperRAM controller itself:

```
IDLE        :  5_893_289
WRITE       : 29_258_880
READ        : 55_974_528
WAIT_WR_TOT : 12_148_306
WAIT_WR_MAX :        145
WAIT_RD_TOT : 18_370_340
WAIT_RD_MAX :        145
```

We see that the HyperRAM is sitting idle 6% of the time. The maximum
wait time is 145 clock cycles. This value can be understood as the combination of
* The transfer time for one transaction (128 clock cycles)
* The time it takes to widen the data bus from 16 to 128 bits (8 clock cycles)
* The total transaction delay inside the HyperRAM device (6+3=9 clock cycles)

