#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import hashlib
import sys
from pathlib import Path
from typing import Dict, List


DEVICE_NAMES = {"spk": "speaker", "h": "headset"}
SPEAKER_DOLBY_TOKENS = {"dolby", "dolbys"}
HEADSET_DOLBY_TOKENS = {"dolbyh"}


def parse_tokens(tokens: List[str]) -> Dict[str, object]:
    headset_plugged = "dual" in tokens
    tokens = [token for token in tokens if token != "dual"]
    device_positions = [(idx, token) for idx, token in enumerate(tokens) if token in DEVICE_NAMES]
    preferred_device = DEVICE_NAMES[device_positions[0][1]] if device_positions else ""

    speaker_dolby = False
    headset_dolby = False
    speaker_enhance = False
    headset_enhance = False
    unknown_tokens: List[str] = []

    if not device_positions:
        unknown_tokens.extend(tokens)
        return {
            "preferred_device": preferred_device,
            "headset_plugged": headset_plugged,
            "speaker_dolby": speaker_dolby,
            "speaker_enhance": speaker_enhance,
            "headset_dolby": headset_dolby,
            "headset_enhance": headset_enhance,
            "unknown_tokens": unknown_tokens,
        }

    first_device_index = device_positions[0][0]
    if first_device_index:
        unknown_tokens.extend(tokens[:first_device_index])

    for index, (position, device) in enumerate(device_positions):
        next_position = device_positions[index + 1][0] if index + 1 < len(device_positions) else len(tokens)
        segment = tokens[position + 1 : next_position]
        for token in segment:
            if token == "enhance":
                if device == "spk":
                    speaker_enhance = True
                else:
                    headset_enhance = True
            elif token in SPEAKER_DOLBY_TOKENS:
                speaker_dolby = True
            elif token in HEADSET_DOLBY_TOKENS:
                headset_dolby = True
            else:
                unknown_tokens.append(token)

    return {
        "preferred_device": preferred_device,
        "headset_plugged": headset_plugged,
        "speaker_dolby": speaker_dolby,
        "speaker_enhance": speaker_enhance,
        "headset_dolby": headset_dolby,
        "headset_enhance": headset_enhance,
        "unknown_tokens": unknown_tokens,
    }


def parse_filename(filename: str) -> Dict[str, object]:
    stem = Path(filename).stem
    if stem.startswith("RtHDDump_"):
        stem = stem[len("RtHDDump_") :]
    tokens = [token for token in stem.split("_") if token]
    return parse_tokens(tokens)


def file_stats(path: Path) -> Dict[str, object]:
    data = path.read_bytes()
    line_count = data.count(b"\n")
    if data and not data.endswith(b"\n"):
        line_count += 1
    return {
        "size_bytes": len(data),
        "line_count": line_count,
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def collect_dump(path: Path) -> Dict[str, object]:
    parsed = parse_filename(path.name)
    stats = file_stats(path)
    return {
        "file": path.name,
        "preferred_device": parsed["preferred_device"],
        "headset_plugged": parsed["headset_plugged"],
        "speaker_dolby": parsed["speaker_dolby"],
        "speaker_enhance": parsed["speaker_enhance"],
        "headset_dolby": parsed["headset_dolby"],
        "headset_enhance": parsed["headset_enhance"],
        "line_count": stats["line_count"],
        "size_bytes": stats["size_bytes"],
        "sha256": stats["sha256"],
        "unknown_tokens": "|".join(parsed["unknown_tokens"]),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Summarize RtHDDump files and infer device flags from filenames."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="Directory containing RtHDDump_*.txt files.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional CSV output path. Defaults to stdout.",
    )
    args = parser.parse_args()

    dumps = sorted(args.root.glob("RtHDDump_*.txt"))
    rows = [collect_dump(path) for path in dumps]

    fieldnames = [
        "file",
        "preferred_device",
        "headset_plugged",
        "speaker_dolby",
        "speaker_enhance",
        "headset_dolby",
        "headset_enhance",
        "line_count",
        "size_bytes",
        "sha256",
        "unknown_tokens",
    ]

    if args.output:
        with args.output.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
    else:
        writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
