#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path
import re

WIN_WID_HEADER = re.compile(r"^\*{10} Wid=\[0x([0-9A-Fa-f]{2})\]")
WIN_INDEX_LINE = re.compile(r"^Index 0x([0-9A-Fa-f]{2})\s+0x([0-9A-Fa-f]{4})")
LIN_NODE_HEADER = re.compile(r"^Node 0x([0-9A-Fa-f]{2})")
LIN_COEFF_LINE = re.compile(r"^\s*Coeff 0x([0-9A-Fa-f]{2}): 0x([0-9A-Fa-f]{4})")
DSP_EXCLUDED_BLOCK = "20"


def read_windows_coefficients(path: Path) -> dict[str, dict[int, str]]:
    blocks: dict[str, dict[int, str]] = {}
    current: str | None = None
    for line in path.read_text(errors="ignore").splitlines():
        header = WIN_WID_HEADER.match(line)
        if header:
            current = header.group(1).upper()
            continue
        if current:
            entry = WIN_INDEX_LINE.match(line)
            if entry:
                blocks.setdefault(current, {})[int(entry.group(1), 16)] = entry.group(2).upper()
            elif line.startswith("**********"):
                current = None
    return blocks


def read_linux_coefficients(path: Path) -> dict[str, dict[int, str]]:
    blocks: dict[str, dict[int, str]] = {}
    current: str | None = None
    for line in path.read_text(errors="ignore").splitlines():
        header = LIN_NODE_HEADER.match(line)
        if header:
            current = header.group(1).upper()
            continue
        if current:
            entry = LIN_COEFF_LINE.match(line)
            if entry:
                blocks.setdefault(current, {})[int(entry.group(1), 16)] = entry.group(2).upper()
    return blocks


def collect_indices(*blocks: dict[int, str]) -> list[int]:
    indices = set()
    for block in blocks:
        indices.update(block.keys())
    return sorted(indices)


def compare_coefficients(
    windows_blocks: dict[str, dict[int, str]],
    linux_blocks: dict[str, dict[int, str]],
    mismatches_only: bool,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    rows: list[dict[str, str]] = []
    dsp_rows: list[dict[str, str]] = []

    all_blocks = sorted(set(windows_blocks) | set(linux_blocks), key=lambda item: int(item, 16))
    for block in all_blocks:
        win_block = windows_blocks.get(block, {})
        lin_block = linux_blocks.get(block, {})
        for index in collect_indices(win_block, lin_block):
            win_value = win_block.get(index, "")
            lin_value = lin_block.get(index, "")
            if mismatches_only and win_value == lin_value:
                continue
            note = "match"
            if win_value and not lin_value:
                note = "windows_only"
            elif lin_value and not win_value:
                note = "linux_only"
            elif win_value != lin_value:
                note = "baseline_mismatch"
            rows.append(
                {
                    "block": f"0x{block}",
                    "index": f"0x{index:02X}",
                    "windows_value": win_value,
                    "linux_value": lin_value,
                    "note": note,
                }
            )

        if block == DSP_EXCLUDED_BLOCK or block in linux_blocks:
            continue
        non_zero = {idx: val for idx, val in win_block.items() if val != "0000"}
        if not non_zero:
            continue
        sample = ", ".join(f"0x{idx:02X}={val}" for idx, val in list(sorted(non_zero.items()))[:6])
        dsp_rows.append(
            {
                "block": f"0x{block}",
                "coeff_count": str(len(win_block)),
                "non_zero_coeffs": str(len(non_zero)),
                "sample_non_zero_values": sample,
            }
        )

    return rows, dsp_rows


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Cross-compare Windows RtHDDump coefficient blocks with Linux codec dumps."
    )
    parser.add_argument(
        "--windows",
        type=Path,
        default=Path(__file__).resolve().parent / "RtHDDump_spk.txt",
        help="Windows RtHDDump baseline file (default: RtHDDump_spk.txt)",
    )
    parser.add_argument(
        "--linux",
        type=Path,
        default=Path(__file__).resolve().parent / "lin_codec-dump-spk",
        help="Linux codec dump baseline file (default: lin_codec-dump-spk)",
    )
    parser.add_argument(
        "--diff-output",
        type=Path,
        help="Optional CSV output for coefficient differences.",
    )
    parser.add_argument(
        "--dsp-output",
        type=Path,
        help="Optional CSV output listing Windows-only DSP/IIR/EQ/DRC candidate blocks.",
    )
    parser.add_argument(
        "--mismatches-only",
        action="store_true",
        help="Only emit coefficient rows where Windows and Linux differ.",
    )
    args = parser.parse_args()

    windows_blocks = read_windows_coefficients(args.windows)
    linux_blocks = read_linux_coefficients(args.linux)

    rows, dsp_rows = compare_coefficients(
        windows_blocks, linux_blocks, mismatches_only=args.mismatches_only
    )

    if args.diff_output:
        write_csv(args.diff_output, rows)
    else:
        writer = csv.DictWriter(
            sys.stdout,
            fieldnames=["block", "index", "windows_value", "linux_value", "note"],
        )
        writer.writeheader()
        writer.writerows(rows)

    if args.dsp_output:
        write_csv(args.dsp_output, dsp_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
