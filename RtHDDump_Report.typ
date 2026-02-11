#set page(margin: (top: 1in, bottom: 1in, left: 1in, right: 1in))
#set heading(numbering: "1.")

#let preferred_keys = 15
#let headset_plugged_keys = 36
#let speaker_dolby_keys = 5
#let speaker_enhance_keys = 9
#let headset_dolby_keys = 10
#let headset_enhance_keys = 14
#let max_keys = 40

#let bar(value, max, color) = {
  let width = 180pt * value / max
  stack(
    dir: ltr,
    rect(width: width, height: 8pt, fill: color),
    h(4pt),
    str(value),
  )
}

= RtHDDump Content Difference Report

== Abstract

This report investigates RtHDDump file *content* differences and their relationship to device states (preferred device, headset plug state, and Dolby/enhancement modes). The analysis focuses on WID lines and registry-style key/value entries inside each dump rather than relying on filename tokens. We find that WID lines are identical across all dumps, while the state changes consistently align with differences in specific `REG_*` keys.

== Data and methods

- Dataset: 27 RtHDDump captures.
- WID analysis: extract all lines starting with `Wid=` and compare across files.
- Content difference analysis: extract key/value lines (`<key> = <value>`).
- Paired comparison method: for each device state, match files with all other states held constant and compare their key/value lines. A key is a *signature* when it changes in ≥ half of the paired comparisons for that state.
- Values are trimmed for readability (`prefix…suffix`) but still show the changing portions.

== Direct answer (WID vs device states)

No WID lines change across the dataset, so there is no WID that directly controls Dolby, preferred device, or system audio enhancement in these dumps. The state changes are instead reflected in `REG_*` key/value differences:

#table(
  columns: (auto, auto, auto),
  [State], [WID control?], [Content keys that change (examples)],
  [Dolby (speaker/headset)], [None observed], [`(REG_BINARY) {1e94c58f-3e40-4ddb-b10c-a86d8b870a31},2`, `(REG_BINARY) {8a845654-d6c3-4cd7-b4eb-243d4bd99032},2`, `(REG_BINARY) {6737016f-5360-48ee-af05-e616c8ff27a7},2`, `(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},4`],
  [Preferred (primary) device], [None observed], [`(REG_SZ) {24dbb0fc-9311-4b3d-9cf0-18ff155639d4},0`, `(REG_BINARY) {1e94c58f-3e40-4ddb-b10c-a86d8b870a31},2`, `(REG_BINARY) {bb8bdb4a-edac-4660-9056-8e67e68e4e77},4`],
  [System audio enhancement], [None observed], [`(REG_BINARY) {1e94c58f-3e40-4ddb-b10c-a86d8b870a31},2`, `(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},1`, `(REG_DWORD) {1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5`],
)

== Linux codec dump analysis

Linux dumps (`lin_` prefix) are HD-audio codec snapshots (Realtek ALC287). Their tokens describe ALSA mixer states:

- `no_automute`: automute disabled via alsamixer.
- `dualstream`: manual unmute of both headphone and speaker paths while the headset is plugged.
- `dual` (in the filename): headset is plugged.

The Linux dumps show a single stream shared by the speaker/headphone outputs (node 0x02 and 0x03). The speaker pins (node 0x14/0x17) switch between `0x80` (muted) and `0x00` (unmuted) when automute/dualstream changes.

#table(
  columns: (auto, auto, auto, auto, auto, auto, auto, auto),
  [File], [dual (hp plugged)], [no_automute], [dualstream], [node0x02 stream], [node0x03 stream], [node0x14 amp-out], [node0x17 amp-out],
  [lin_codec-dump-dual_h_spk], [yes], [no], [no], [0], [0], [0x80 0x80], [0x80 0x80],
  [lin_codec-dump-dual_h_spk_no_automute], [yes], [yes], [no], [1], [1], [0x80 0x80], [0x80 0x80],
  [lin_codec-dump-dual_h_spk_no_automute_dualstream], [yes], [yes], [yes], [1], [1], [0x00 0x00], [0x00 0x00],
  [lin_codec-dump-spk], [no], [no], [no], [0], [0], [0x00 0x00], [0x00 0x00],
  [lin_codec-dump-spk_no_automute], [no], [yes], [no], [1], [1], [0x00 0x00], [0x00 0x00],
  [lin_codec-dump-spk_no_automute_dualstream], [no], [yes], [yes], [1], [1], [0x00 0x00], [0x00 0x00],
)

Interpretation: `dualstream` explicitly unmutes the speaker pins while the headset is plugged, so the same audio stream is audible from both ports. `no_automute` turns off ALSA automute but does not by itself unmute the speaker pins when the headset is plugged; the manual unmute (dualstream) is what clears the `0x80` mute values.

=== Linux coefficient (verb) deltas

The refreshed Linux dumps now include the vendor coefficient block under Node 0x20. Only three coefficients differ across the Linux states:

#table(
  columns: (auto, auto, auto, auto, auto, auto, auto),
  [File], [dual], [no_automute], [dualstream], [Coeff 0x46], [Coeff 0x77], [Coeff 0x78],
  [lin_codec-dump-dual_h_spk], [yes], [no], [no], [0c04], [0063], [0079],
  [lin_codec-dump-dual_h_spk_no_automute], [yes], [yes], [no], [0c04], [0023], [0090],
  [lin_codec-dump-dual_h_spk_no_automute_dualstream], [yes], [yes], [yes], [0c04], [0046], [005d],
  [lin_codec-dump-spk], [no], [no], [no], [0404], [0050], [00a6],
  [lin_codec-dump-spk_no_automute], [no], [yes], [no], [0404], [003c], [006b],
  [lin_codec-dump-spk_no_automute_dualstream], [no], [yes], [yes], [0404], [001f], [0079],
)

Interpretation: Coeff 0x46 flips when the headset is plugged (dual), while 0x77 and 0x78 vary with automute and manual dualstream behavior. This aligns with the blog guidance that Windows/Linux differences often live in the vendor coefficient (verb) block rather than in the WID defaults.

== Results

=== WID section stability

All 27 files contain the same 11 WID lines with identical values, indicating that the device-state verbs are *not* encoded by WID changes in this dataset.

#table(
  columns: (auto, auto, auto, auto),
  [WID], [Codec], [Drv], [Loc],
  [12], [40000000], [40000000], [00000000],
  [13], [411111F0], [411111F0], [00000000],
  [14], [90170120], [90170120], [00000000],
  [17], [90170120], [90170120], [00000000],
  [18], [81D111F0], [—], [—],
  [19], [03A11030], [03A11030], [00080000],
  [1A], [411111F0], [411111F0], [00020400],
  [1B], [411111F0], [411111F0], [00000000],
  [1D], [40471A6D], [411111F0], [00000000],
  [1E], [411111F0], [411111F0], [00000700],
  [21], [03211010], [03211010], [00020000],
)

=== Feature difference summary

#table(
  columns: (auto, auto, auto, auto),
  [Feature], [Paired comparisons], [Keys ≥ half pairs], [Keys all pairs],
  [preferred_device], [3], [15], [8],
  [headset_plugged], [1], [36], [36],
  [speaker_dolby], [6], [5], [3],
  [speaker_enhance], [6], [9], [3],
  [headset_dolby], [3], [10], [10],
  [headset_enhance], [4], [14], [3],
)

#figure(
  caption: [Signature key counts by feature (≥ half of paired comparisons)],
  table(
    columns: (auto, auto),
    [preferred_device], bar(preferred_keys, max_keys, rgb("#4f81bd")),
    [headset_plugged], bar(headset_plugged_keys, max_keys, rgb("#c0504d")),
    [speaker_dolby], bar(speaker_dolby_keys, max_keys, rgb("#9bbb59")),
    [speaker_enhance], bar(speaker_enhance_keys, max_keys, rgb("#8064a2")),
    [headset_dolby], bar(headset_dolby_keys, max_keys, rgb("#4f81bd")),
    [headset_enhance], bar(headset_enhance_keys, max_keys, rgb("#c0504d")),
  ),
)

=== Preferred device signatures

#table(
  columns: (auto, auto, auto, auto),
  [Key], [Coverage], [Speaker preferred], [Headset preferred],
  [`(REG_BINARY) {1e94c58f-3e40-4ddb-b10c-a86d8b870a31},2`], [3/3], [`02 00 00 00 01 00 00 00 EF 06`], [`02 00 00 00 01 00 00 00 EF 01`],
  [`(REG_BINARY) Position`], [3/3], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`],
  [`(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},4`], [3/3], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…0 00 40 34 00 00`], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 20 23 00 00`],
  [`(REG_SZ) {24dbb0fc-9311-4b3d-9cf0-18ff155639d4},0`], [3/3], [`{0.0.0.00000000}.{36e664d4-3174-4fd5-ace4-5287bc0bdf22}`], [`{0.0.0.00000000}.{105abd99-be3c-4986-856c-3f24ec337b55}`],
  [`(REG_BINARY) {bb8bdb4a-edac-4660-9056-8e67e68e4e77},4`], [3/3], [`41 00 00 00 01 00 00 00 C7 1B 04 75 36 2…3 E0 37 6D 08 5A`], [`41 00 00 00 01 00 00 00 0B B9 7A 91 18 0…9 1A 56 F8 04 5A`],
)

=== Headset plug signatures

#table(
  columns: (auto, auto, auto, auto),
  [Key], [Coverage], [Headset plugged], [Headset unplugged],
  [`(REG_DWORD) InternalSpeakerStreamActive`], [1/1], [`0x0000`], [`0x0001`],
  [`(REG_BINARY) {5510c7ab-dfc2-40d0-a98b-5f77f697005e},2`], [1/1], [`03 00 00 00 01 00 00 00 28 00 00 00`], [`03 00 00 00 01 00 00 00 00 00 00 00`],
  [`(REG_BINARY) {5510c7ab-dfc2-40d0-a98b-5f77f697005e},1`], [1/1], [`03 00 00 00 01 00 00 00 08 00 00 00`], [`03 00 00 00 01 00 00 00 02 00 00 00`],
  [`(REG_DWORD) {3ba0cd54-830f-4551-a6eb-f3eab68e3700},6`], [1/1], [`0x0000`], [`0x0001`],
  [`(REG_BINARY) {194ef948-7cdb-403e-9f47-19418f7b24fd},2`], [1/1], [`40 00 00 00 01 00 00 00 8D F3 96 28 D4 9A DC 01`], [`40 00 00 00 01 00 00 00 59 36 9F D1 D3 9A DC 01`],
)

=== Speaker Dolby signatures

#table(
  columns: (auto, auto, auto, auto),
  [Key], [Coverage], [Speaker Dolby on], [Speaker Dolby off],
  [`(REG_BINARY) Position`], [6/6], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`],
  [`(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},4`], [6/6], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 20 23 00 00`], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 60 23 00 00`],
  [`(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},1`], [6/6], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 20 23 00 00`], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 60 23 00 00`],
  [`(REG_BINARY) {1e94c58f-3e40-4ddb-b10c-a86d8b870a31},2`], [4/6], [`02 00 00 00 01 00 00 00 20 0C`], [`02 00 00 00 01 00 00 00 EF 07`],
  [`(REG_BINARY) {8a845654-d6c3-4cd7-b4eb-243d4bd99032},2`], [3/6], [`41 00 00 00 01 00 00 00 00 00 00 00 00 0…E F9 95 53 37 90`], [`41 00 00 00 01 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`],
)

=== Speaker enhancement signatures

#table(
  columns: (auto, auto, auto, auto),
  [Key], [Coverage], [Speaker enhancement on], [Speaker enhancement off],
  [`(REG_BINARY) Position`], [6/6], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`],
  [`(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},4`], [6/6], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 20 23 00 00`], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 A0 23 00 00`],
  [`(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},1`], [6/6], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 20 23 00 00`], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 A0 23 00 00`],
  [`(REG_BINARY) {1e94c58f-3e40-4ddb-b10c-a86d8b870a31},2`], [5/6], [`02 00 00 00 01 00 00 00 EF 01`], [`02 00 00 00 01 00 00 00 EF 02`],
  [`(REG_DWORD) {1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5`], [4/6], [`∅`], [`0x0001`],
)

=== Headset Dolby signatures

#table(
  columns: (auto, auto, auto, auto),
  [Key], [Coverage], [Headset Dolby on], [Headset Dolby off],
  [`(REG_BINARY) {8a845654-d6c3-4cd7-b4eb-243d4bd99032},2`], [3/3], [`41 00 00 00 01 00 00 00 00 00 00 00 00 0…F E8 0F 4D 39 5D`], [`41 00 00 00 01 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`],
  [`(REG_BINARY) {1e94c58f-3e40-4ddb-b10c-a86d8b870a31},2`], [3/3], [`02 00 00 00 01 00 00 00 EF 07`], [`02 00 00 00 01 00 00 00 EF 05`],
  [`(REG_BINARY) Position`], [3/3], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`],
  [`(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},4`], [3/3], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…0 00 80 34 00 00`], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 C0 33 00 00`],
  [`(REG_BINARY) {6737016f-5360-48ee-af05-e616c8ff27a7},2`], [3/3], [`02 00 00 00 01 00 00 00 04 00`], [`02 00 00 00 01 00 00 00 00 00`],
)

=== Headset enhancement signatures

#table(
  columns: (auto, auto, auto, auto),
  [Key], [Coverage], [Headset enhancement on], [Headset enhancement off],
  [`(REG_BINARY) Position`], [4/4], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`], [`01 00 00 00 00 00 00 00 00 00 00 00 00 0…0 00 00 00 00 00`],
  [`(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},4`], [4/4], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 A0 23 00 00`], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 20 24 00 00`],
  [`(REG_BINARY) {1b4dab55-b1fb-4d8c-8317-f2d4a96efbb8},1`], [4/4], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 A0 23 00 00`], [`41 00 00 00 01 00 00 00 01 00 01 00 01 0…2 00 20 24 00 00`],
  [`(REG_BINARY) {1e94c58f-3e40-4ddb-b10c-a86d8b870a31},2`], [3/4], [`02 00 00 00 01 00 00 00 EF 01`], [`02 00 00 00 01 00 00 00 EF 02`],
  [`(REG_BINARY) {624f56de-fd24-473e-814a-de40aacaed16},3`], [2/4], [`41 00 00 00 01 00 00 00 FE FF 02 00 80 B…0 AA 00 38 9B 71`], [`∅`],
)

== Conclusion

The device-state verbs are reflected in *registry key/value differences*, not WID line changes. Preferred device and headset plug state show strong, consistent content signatures, while Dolby and enhancement states show fewer but still repeatable key changes across paired comparisons. The signature tables above provide the definitive, content-based mapping from each state to the specific keys that change.

=== Windows vs Linux implementation differences

- Windows: exposes separate speaker/headset endpoints and maintains independent streams. Registry (`REG_*`) deltas track preferred device, Dolby, and enhancement independently per endpoint.
- Linux: exposes a single logical playback device with shared stream IDs for speaker/headphone outputs (node 0x02/0x03). Automute and manual unmute are reflected in pin amp-out values (node 0x14/0x17) and Node 0x20 coefficients, not separate streams.

=== Consistency guidance

To make platform behavior consistent, choose one of these strategies:

1. Match Windows behavior on Linux by exposing separate sinks (speaker/headphone) via ALSA UCM or PipeWire/WirePlumber and routing distinct streams to each output, while disabling automute.
2. Match Linux behavior on Windows by forcing a shared stream (mirrored output) so speaker/headphone always play the same audio flow.

The analysis above indicates that Linux currently controls routing/mute state (pin amp-out values and Node 0x20 coefficients), while Windows controls endpoint selection and processing (registry keys). Aligning the control surface is the key to cross‑platform consistency.

== Appendix: Regeneration

Generate the CSV summary and the PDF report from the current dumps:

```
python rthddump_report.py --output rthddump_summary.csv
typst compile RtHDDump_Report.typ RtHDDump_Report.pdf
```
