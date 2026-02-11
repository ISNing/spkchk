#set page(margin: 2cm)
#set text(font: ("DejaVu Sans", "Lato"), size: 10pt)

= RtHDDump Content Difference Report

== Executive summary (direct answers)

- WIDs do not change across Windows profiles. They identify hardware pins (speaker, headphone, mic, SPDIF) and stay constant across preferred device, Dolby, and enhancement states.
- Only one WID is overridden by the Windows driver: WID `0x1D` (`Drv=411111F0` vs `Codec=40471A6D`). Linux keeps the codec default (`Pin Default=40471A6D`).
- Windows coefficient changes are limited to headset plug: Wid `0x20` indices `0x10`, `0x46`, `0x67` toggle when the headset is plugged.
- Linux coefficient changes are limited to headset plug + automute/dualstream: Node `0x20` coefficient `0x46` toggles with headset plug; `0x77/0x78` move with automute/dualstream.
- Dolby/enhancement do not appear in WIDs or coefficients; they are encoded in the `REG_*` registry keys in Windows dumps.

The remainder of this report reconstructs the investigation into Windows internals, Linux internals, and a cross-platform investigation that maps each WID and coefficient to its inferred control meaning.

== Windows internal investigation

=== WID meaning list (Windows WID → Linux Node mapping)

Windows `Wid=0x??` entries correspond directly to Linux `Node 0x??`. The table below lists each WID, its Linux node type, and the pin description (the practical meaning).

#table(
  columns: (auto, auto, auto, auto, auto, auto),
  [WID], [Linux node type], [Linux pin description], [Win Codec], [Win Drv], [Drv!=Codec],
  [0x12], [Node 0x12 [Pin Complex] wcaps 0x40040b: Stereo Amp-In], [[N/A] Line Out at Ext N/A], [40000000], [40000000], [no],
  [0x13], [Node 0x13 [Pin Complex] wcaps 0x40040b: Stereo Amp-In], [[N/A] Speaker at Ext Rear], [411111F0], [411111F0], [no],
  [0x14], [Node 0x14 [Pin Complex] wcaps 0x40058d: Stereo Amp-Out], [[Fixed] Speaker at Int N/A], [90170120], [90170120], [no],
  [0x17], [Node 0x17 [Pin Complex] wcaps 0x40058d: Stereo Amp-Out], [[Fixed] Speaker at Int N/A], [90170120], [90170120], [no],
  [0x19], [Node 0x19 [Pin Complex] wcaps 0x40048b: Stereo Amp-In], [[Jack] Mic at Ext Left], [03A11030], [03A11030], [no],
  [0x1A], [Node 0x1a [Pin Complex] wcaps 0x40048b: Stereo Amp-In], [[N/A] Speaker at Ext Rear], [411111F0], [411111F0], [no],
  [0x1B], [Node 0x1b [Pin Complex] wcaps 0x40058f: Stereo Amp-In Amp-Out], [[N/A] Speaker at Ext Rear], [411111F0], [411111F0], [no],
  [0x1D], [Node 0x1d [Pin Complex] wcaps 0x400400: Mono], [[N/A] SPDIF Out at Ext N/A], [40471A6D], [411111F0], [yes],
  [0x1E], [Node 0x1e [Pin Complex] wcaps 0x400501: Stereo], [[N/A] Speaker at Ext Rear], [411111F0], [411111F0], [no],
  [0x21], [Node 0x21 [Pin Complex] wcaps 0x40058d: Stereo Amp-Out], [[Jack] HP Out at Ext Left], [03211010], [03211010], [no],
)

Inference: WID `0x14/0x17` are internal speakers, WID `0x21` is the headphone jack, WID `0x19` is the external mic, and WID `0x1D` is SPDIF/aux. The only Windows driver override is WID `0x1D`.

=== Windows coefficient controls (Wid 0x20)

Windows stores vendor coefficients under Wid 0x20. The only coefficient changes tied to a Windows state are for headset plugged:

#table(
  columns: (auto, auto, auto, auto),
  [Index], [Headset unplugged], [Headset plugged], [Inferred meaning],
  [0x10], [8A06], [8B06], [Headset plug toggle (Windows)],
  [0x46], [0004], [0C34], [Headset plug toggle (Windows)],
  [0x67], [1000], [3000], [Headset plug toggle (Windows)],
)

Inference: headset plug is expressed via Wid 0x20 coefficient deltas, not via WID pin changes. Dolby/enhancement are not represented in Wid/coeff values and instead live in `REG_*` deltas.

=== Windows-only DSP coefficient blocks (IIR/EQ/DRC candidates)

Windows exposes additional vendor coefficient blocks on WIDs `0x53–0x58` that are not present in the Linux dumps. These blocks have dense, non-zero coefficient sets and are likely used for DSP processing such as IIR/EQ/DRC (based on the presence of many fixed-point coefficient values). Linux lacks these nodes, so their tuning is not applied.

#table(
  columns: (auto, auto, auto, auto, auto),
  [WID], [coeff count], [non-zero coeffs], [sample non-zero values], [Inferred meaning],
  [0x53], [128], [10], [0x00=602A, 0x02=8000, 0x05=0263, 0x06=41F4, 0x07=1F20], [DSP coefficient block (IIR/EQ/DRC candidate)],
  [0x54], [128], [9], [0x00=2000, 0x05=0263, 0x06=41F4, 0x07=1F20, 0x08=D8C2], [DSP coefficient block (IIR/EQ/DRC candidate)],
  [0x56], [128], [6], [0x00=821C, 0x02=74C4, 0x03=082A, 0x04=6400, 0x05=D7C6], [DSP coefficient block (IIR/EQ/DRC candidate)],
  [0x57], [128], [5], [0x03=A011, 0x04=8244, 0x06=2000, 0x07=3300, 0x08=2200], [DSP coefficient block (IIR/EQ/DRC candidate)],
  [0x58], [128], [5], [0x00=1888, 0x03=31CC, 0x0F=F0C9, 0x11=0621, 0x14=C000], [DSP coefficient block (IIR/EQ/DRC candidate)],
)

== Linux internal investigation

=== Linux node controls

Linux exposes the same pin controls as the Windows WID list above. The Linux pin defaults confirm the same roles: internal speakers on nodes `0x14/0x17`, headphone jack on `0x21`, mic on `0x19`, and SPDIF/aux on `0x1D`.

=== Linux coefficient controls (Node 0x20)

Linux exposes vendor coefficients under Node 0x20. Only three coefficients vary across Linux states:

#table(
  columns: (auto, auto, auto, auto, auto),
  [State], [Coeff 0x46], [Coeff 0x77], [Coeff 0x78], [Inferred meaning],
  [spk], [0404], [0050], [00A6], [Linux baseline],
  [dual_h_spk], [0C04], [0063], [0079], [Headset plug toggles 0x46/0x77/0x78],
  [dual_h_spk_no_automute], [0C04], [0023], [0090], [Automute toggle (0x77/0x78)],
  [dual_h_spk_no_automute_dualstream], [0C04], [0046], [005D], [Dualstream toggle (0x77/0x78)],
)

Inference:
- 0x46 is a headset-plug control in Linux.
- 0x77/0x78 encode automute/dualstream routing choices (Linux-specific behavior).

== Cross investigation (Windows ↔ Linux)

=== Windows-only DSP blocks missing in Linux

The WIDs above (`0x53–0x58`) are present only in Windows dumps and contain non-zero coefficient sets. Their absence in Linux is consistent with missing IIR/EQ/DRC tuning in the Linux driver path.

=== Coefficient meaning list (merged view)

The table below lists every coefficient index that differs across Windows/Linux or changes with a state, and the inferred meaning based on observed deltas.

#table(
  columns: (auto, auto, auto, auto, auto, auto, auto, auto),
  [Index], [Win base], [Win headset], [Linux base], [Linux headset], [Linux no_automute], [Linux dualstream], [Inferred meaning],
  [0x03], [F002], [F002], [0002], [0002], [0002], [0002], [Baseline mismatch (Win vs Linux)],
  [0x04], [AA09], [AA09], [AA89], [AA89], [AA89], [AA89], [Baseline mismatch (Win vs Linux)],
  [0x08], [4A37], [4A37], [4AB7], [4AB7], [4AB7], [4AB7], [Baseline mismatch (Win vs Linux)],
  [0x10], [8A06], [8B06], [8906], [8906], [8906], [8906], [Headset plug toggle (Windows)],
  [0x1A], [8C83], [8C83], [8003], [8003], [8003], [8003], [Baseline mismatch (Win vs Linux)],
  [0x30], [9007], [9007], [9004], [9004], [9004], [9004], [Baseline mismatch (Win vs Linux)],
  [0x44], [4900], [4900], [4500], [4500], [4500], [4500], [Baseline mismatch (Win vs Linux)],
  [0x46], [0004], [0C34], [0404], [0C04], [0C04], [0C04], [Headset plug toggle (Windows); headset plug toggle (Linux)],
  [0x48], [D049], [D049], [D011], [D011], [D011], [D011], [Baseline mismatch (Win vs Linux)],
  [0x49], [0049], [0049], [0045], [0045], [0045], [0045], [Baseline mismatch (Win vs Linux)],
  [0x67], [1000], [3000], [F000], [F000], [F000], [F000], [Headset plug toggle (Windows)],
  [0x77], [0000], [0000], [0050], [0063], [0023], [0046], [Headset plug + automute/dualstream (Linux)],
  [0x78], [0000], [0000], [00A6], [0079], [0090], [005D], [Headset plug + automute/dualstream (Linux)],
)

=== Inconsistency list (what blocks matching Windows on Linux)

#table(
  columns: (auto, auto, auto, auto),
  [Inconsistency], [Windows behavior], [Linux behavior], [Reproduction knob (Linux)],
  [Pin config (WID 0x1D)], [Driver overrides to `Drv=411111F0`], [Linux keeps codec default `Pin Default=40471A6D`], [Retask pin 0x1D to `0x411111F0` (firmware patch / hda-verb)],
  [Vendor coeff baseline], [Wid 0x20 values differ at indices `0x03/0x04/0x08/0x10/0x1A/0x30/0x44/0x46/0x48/0x49/0x67/0x77/0x78`], [Node 0x20 coefficients keep Linux defaults], [Write Node 0x20 coefficients to the Windows values],
  [Headset plug handling], [Wid 0x20 indices `0x10/0x46/0x67` toggle on plug], [Linux uses pin mutes + coeff `0x46`], [Apply Windows index values on plug/unplug and avoid automute pin mutes],
  [Automute/dualstream], [Not represented in Wid 0x20], [Linux uses coeff `0x77/0x78` + pin amp-out], [Set coeffs `0x77/0x78` to Windows baseline (0000) and manage routing explicitly],
)

=== Direct reproduction path (Linux → Windows behavior)

1. Retask pin 0x1D to the Windows driver value 0x411111F0.
2. Apply the Windows Wid 0x20 coefficient baseline to Linux Node 0x20 (indices listed above).
3. On headset plug/unplug, mirror the Windows headset-plug deltas (0x10/0x46/0x67).
4. Neutralize Linux-specific automute behavior by setting 0x77/0x78 to Windows baseline (0000) and controlling routing explicitly.

== Appendix: Regeneration

Font selection: the report uses DejaVu Sans with Lato as the fallback font to maximize availability on typical Linux systems.

Generate the CSV summary and the PDF report from the current dumps:

```
python rthddump_report.py --output rthddump_summary.csv
python rthddump_compare.py --diff-output rthddump_coeff_compare.csv --dsp-output rthddump_windows_dsp.csv --mismatches-only
typst compile RtHDDump_Report.typ RtHDDump_Report.pdf
```
