This document contains statistics about the HyperRAM usage.

The HyperRAM usage is independent of output resolutions; only depends on input
resolution, and on output frame rate.

The starting point is the Demo Core, which generates a video output of 720x576
visible pixels at 50 Hz.

In this experiment there are two ascalers, one connected to VGA output (50 Hz)
and another connected to HDMI output (50 Hz).

Both ascalers are configured for 16 bit pixel color format, i.e. 2 bytes per
pixel.

The HyperRAM word width is also 16 bits, so one pixel fits into one word.

All numbers below are expressed in HyperRAM words of 16 bits.

## Theoretical values
The HyperRAM clock frequency is 100 MHz. This means that the theoretical
maximum bandwidth of the HyperRAM is 100 Mwords per second.

### Writing to HyperRAM
The amount of video data generated can be calculated as `720x576x50` = 20.7
Mwords per second.

### Reading from HyperRAM
The same video data must be read from HyperRAM as well, but perhaps with a
different frame rate.  At 60 Hz we get the following numbers: `720x576x60` =
24.9 Mwords per second.

### Total minimum bandwidth required
The video data must be written once and read twice. So at 50 Hz frame rate on
both VGA and HDMI, the combined bandwidth is `3x20.7` = 62 Mwords per second,
i.e. 62% of the available memory bandwidth.


## Measured values

All counters below are number of HyperRAM clock cycles and therefore are in
units of 16-bit words. The values are recorded after exactly one second.

### HDMI ascaler

```
WRITE       : 22_118_400
READ        : 22_156_800
WAIT_WR_TOT : 11_058_401
WAIT_WR_MAX :        400
WAIT_RD_TOT : 18_465_788
WAIT_RD_MAX :        293
ADR_MAX_WR  :    442_368
ADR_MAX_RD  :    443_136
```

From the `ADR_MAX` values we conclude that the ascaler rounds each line up to a
multiple of 128 words.  So a single line of 720 pixels is stored in 768 words.
The total amount of data stored is then `768x576`= 442368 words, which exactly
corresponds with `ADR_MAX_WR`. Multiplying this value by 50 gives the number
`WRITE`. The value of `ADR_MAX_RD` is exactly 768 larger, i.e. corresponding to
one more scan line.  This is probably an artifact of the ascaler. Again,
multiplying by 50 gives the value of `READ`.

So in conclusion we see that the HDMI ascaler spends approx 22% of the time
writing to HyperRAM, and an equal amount of time reading from the HyperRAM.

To interpret the WAIT times we first calculate the number of HyperRAM
transactions. Each transaction consists of 128 words, so a total of
`22118400/128` = 172800 write transactions per second. The average wait time is
therefore `11058401/ 22118400 * 128` = 64 clock cycles for each write, and
`18465788 / 22156800 * 128` = 107 clock cycles for each read.

So in conclusion the HDMI ascaler wait time for each transaction (both average
and maximum) is much less than a single scan line of 768 clock cycles.

### VGA ascaler

The VGA ascaler only does reads.

```
WRITE       :          0
READ        : 22_156_800
WAIT_WR_TOT :          0
WAIT_WR_MAX :          0
WAIT_RD_TOT : 14_844_415
WAIT_RD_MAX :        415
```

We see that the `READ` value is the same, because the frame rate is the same.
The average wait time is `14844415 / 22156800 * 128` = 86 clock cycles.

The VGA ascaler wait time for each transaction (both average and maximum)
is again much less than a single scan line of 768 clock cycles.

### HyperRAM arbiter

The two ascalers contend for access to the HyperRAM, and this contention is handled
by the HyperRAM arbiter. Statistics from this arbiter are as follows:

```
GRANT_VGA     : 24_416_719
WAIT_VGA      : 10_373_094
WAIT_VGA_MAX  :        143
GRANT_HDMI    : 48_415_504
WAIT_HDMI     : 12_326_559
WAIT_HDMI_MAX :        143
```

These numbers show that the ascaler for the HDMI output (which does both write
and read transactions) occupies the HyperRAM 48% of the time, while the VGA
output (which only does read transactions) uses 24% of the HyperRAM bandwidth.
The remaining 28% of the time the HyperRAM is idle.

Furthermore, these numbers confirm that the maximum wait time is the same for
the two ascalers. This shows the arbiter does a good job of ensuring a fair
share of the HyperRAM to each ascaler.

### HyperRAM controller

Finally, we look at the statistics of the HyperRAM controller itself:

```
IDLE        : 26_629_807
WRITE       : 22_118_400
READ        : 44_313_600
WAIT_WR_TOT :  9_284_060
WAIT_WR_MAX :        145
WAIT_RD_TOT : 12_384_891
WAIT_RD_MAX :        145
```

We see that the HyperRAM is sitting idle more than 26% of the time. The maximum
wait time is 145 clock cycles. This value can be understood as the combination of
* The transfer time for one transaction (128 clock cycles)
* The time it takes to widen the data bus from 16 to 128 bits (8 clock cycles)
* The total transaction delay inside the HyperRAM device (6+3=9 clock cycles)

A more conservative estimate of the required bandwidth is as follows:
A total of `768*576*50/128` = 172_800 write transactions are required. And twice the number
of read transactions. The total number of transactions are therefore:
`172_800*3` = 518_400. Each transaction takes up to 145 clock cycles, so
the total number of clock cycles required is therefore `518_400×145` = 75 M clock cycles,
i.e. a bandwidth utilization of 75 %. That is close to the observed value of 74 %.
