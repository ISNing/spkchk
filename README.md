# spkchk

This repository stores RtHDDump captures. Use `rthddump_report.py` to read the files and infer the meaning of filename tokens while also reporting basic content stats:

```bash
python rthddump_report.py --output rthddump_summary.csv
```

`rthddump_summary.csv` is the current report generated from all dumps. It lists each file with inferred device flags plus size/line-count stats.

Academic report files:

- `RtHDDump_Report.md` (markdown version with charts)
- `RtHDDump_Report.typ` (Typst source)
- `RtHDDump_Report.pdf` (compiled PDF)

Filename inference rules encoded in the script:

- `dual` means the headset is plugged in (absence means unplugged).
- The first device token (`spk` or `h`) is the preferred device.
- `spk` means speaker, `h` means headset.
- `dolbyh` means Dolby for headset.
- `dolbys` or `dolby` means Dolby for speaker.
- `enhance` after `spk` means system audio enhancement is enabled for speaker.
- `enhance` after `h` means system audio enhancement is enabled for headset.

To regenerate the report PDF after updating the data:

```bash
python rthddump_report.py --output rthddump_summary.csv
typst compile RtHDDump_Report.typ RtHDDump_Report.pdf
```
