# The microphone goes silent for about 30 s in the middle of a recording

Dictation runs, then the mic delivers silence for about 30 s, then it works
again. The capture stream stays open the whole time, thus PipeWire and the
recording app report nothing. Speaker playback can drop a channel the same way.

The kernel log shows the cause at the moment it happens:

```
soundwire_intel soundwire_intel.link.3: Bus clash for control word
soundwire_intel soundwire_intel.link.3: Parity error
sdca_class sdw:0:3:01fa:4245:01: Parity error detected
```

## Mechanism

The mic is not a DMIC. It is an SDCA SmartMic function on the Cirrus CS42L45
codec, on SoundWire link 3. The speaker amps (CS35L63) are on link 2.

SoundWire has one clock line, driven by the controller. When no stream runs
for 3 s, the link runtime-suspends and stops the clock. On the next stream the
clock restarts and each codec must re-sync to it. On this machine that re-sync
faults on both links. The default quirk (`SDW_INTEL_CLK_STOP_BUS_RESET`, value
8) recovers with a full bus reset and re-enumeration, which is the 30 s of
silence.

The faults land 1–4 s after a capture starts, and 2 s after one stops. A
capture that starts while the links are still awake does not fault.

## The fix

`sdw-clock-stop.conf` sets `snd_sof_intel_hda_generic sdw_clock_stop_quirks=1`
(`SDW_INTEL_CLK_STOP_NOT_ALLOWED`). The link driver then holds a permanent
runtime-PM reference, thus the links never suspend and the clock never stops.
The DSP cannot idle either, because the links are its children.

Cost: the audio DSP and both links stay in their active state. A few hundred
mW on battery. Not measured.

## Ruled out

- **voxtype and PipeWire.** Neither logs anything. The stream runs through
  the silence.
- **BIOS.** Lenovo 1.21 ships the same UEFI 1.14 as 1.20 and changes only a
  CPU-frequency limit. The earlier mic fix in 1.12 (missing DisCo entries)
  is already applied.
- **Kernel 7.2.4–7.2.6.** No SoundWire or SDCA change in the changelogs
  touches this.
- **A longer autosuspend delay.** The first capture after any pause longer
  than the delay would still fault, which is the case that matters.
- **`sdw_clock_stop_quirks=2` (teardown).** Re-enumerates on each wake, thus
  each capture starts with the same dead stretch.

## Verify

The quirk is a module parameter, thus it needs a reboot. Then:

```sh
cat /sys/module/snd_sof_intel_hda_generic/parameters/sdw_clock_stop_quirks
# 1
cat /sys/bus/auxiliary/devices/soundwire_intel.link.3/power/runtime_status
# active, at any time, with nothing recording
journalctl -k -b | grep -E 'soundwire_intel.*(clash|Parity)'
# nothing within 5 s of a recording
```

CAUTION: Do not read that last one as a count. A resume from suspend logs
about two clash lines whatever the quirk does, because a system suspend stops
the bus on a different path. Measured: 57 recordings over one boot with two
lines, both at `PM: suspend exit`, 6.6 minutes from the nearest recording.

The same effect without a reboot, for a test only, is
`echo on > /sys/bus/auxiliary/devices/soundwire_intel.link.{2,3}/power/control`
as root. That held the links awake through three recordings with no fault,
where before nearly each recording faulted.

## Fixed when

Set the file aside, reboot, and run the third command above after a day of
dictation. No line within 5 s of a recording means the kernel handles
clock-stop exit on this codec, and the file can go. A line beside a recording
means put it back.

Upstream: [thesofproject/linux#5914](https://github.com/thesofproject/linux/issues/5914)
is the same fault on a Dell XPS 14 with the same codec. That report has no
kernel fix. It has not been tied to clock-stop there; this directory is the
evidence.

## Not this bug

[thesofproject/linux#5933](https://github.com/thesofproject/linux/issues/5933):
on kernel 7.2.x this model's mic can come up fully silent, or the sound card
can be absent, on some boots. That is a boot-time IRQ-mapping race, fixed in
7.3 by commit `ee1811ea`. A good boot logs
`snd_soc_sdca.SmartMic.0: loading SWF: 1fa-42450005-1309`. If that line is
absent, reboot.
