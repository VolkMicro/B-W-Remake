"""Compare corresponding original/remake frames without hiding camera errors.

Captures and output belong outside Git (for example scratch/visual-reference).
Pillow is required. Metrics describe image differences; they are not a pass/fail
verdict about a restoration rendered by two different engines.
"""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageStat


def crop_rect(value):
    try:
        x, y, width, height = map(int, value.split(","))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("use x,y,width,height") from exc
    if min(x, y) < 0 or min(width, height) <= 0:
        raise argparse.ArgumentTypeError("crop must have a nonnegative origin and positive size")
    return x, y, x + width, y + height


def load_frame(path, crop):
    with Image.open(path) as source:
        frame = source.convert("RGB")
    if crop:
        if crop[2] > frame.width or crop[3] > frame.height:
            raise ValueError(f"crop lies outside {path}: {frame.size}")
        frame = frame.crop(crop)
    return frame


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--event", required=True, help="shared story event, not wall-clock time")
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--reference-crop", type=crop_rect)
    parser.add_argument("--candidate-crop", type=crop_rect)
    parser.add_argument("--reference-meta", type=Path)
    parser.add_argument("--candidate-meta", type=Path)
    args = parser.parse_args()

    reference = load_frame(args.reference, args.reference_crop)
    candidate = load_frame(args.candidate, args.candidate_crop)
    if reference.size != candidate.size:
        parser.error(f"viewport sizes differ: {reference.size} vs {candidate.size}; recapture at the same size or crop explicit window borders. No automatic resizing/alignment is performed.")
    args.out_dir.mkdir(parents=True, exist_ok=True)

    delta = ImageChops.difference(reference, candidate)
    maximum = ImageChops.lighter(ImageChops.lighter(*delta.split()[:2]), delta.split()[2])
    histogram = maximum.histogram()
    total = reference.width * reference.height
    report = {
        "schema": 1,
        "event": args.event,
        "status": "comparison-only-not-a-validation-pass",
        "viewport": list(reference.size),
        "reference": {"path": str(args.reference.resolve()), "sha256": sha256(args.reference), "crop": args.reference_crop},
        "candidate": {"path": str(args.candidate.resolve()), "sha256": sha256(args.candidate), "crop": args.candidate_crop},
        "alignment": "none",
        "resized": False,
        "metrics": {
            "mean_absolute_rgb_0_255": sum(ImageStat.Stat(delta).mean) / 3,
            "pixels_any_channel_delta_gt_16_percent": sum(histogram[17:]) * 100 / total,
            "pixels_any_channel_delta_gt_64_percent": sum(histogram[65:]) * 100 / total,
        },
        "limits": "Lighting, materials, vegetation, animation and nondeterministic simulation can differ. Inspect the pair; these metrics do not establish behavioral or pixel equivalence.",
    }
    for side in ("reference", "candidate"):
        metadata = getattr(args, side + "_meta")
        if metadata:
            report[side]["metadata"] = json.loads(metadata.read_text(encoding="utf-8-sig"))

    pair = Image.new("RGB", (reference.width * 2, reference.height + 52), "#16191d")
    pair.paste(reference, (0, 52))
    pair.paste(candidate, (reference.width, 52))
    draw = ImageDraw.Draw(pair)
    draw.text((12, 8), "REFERENCE / ORIGINAL", fill="white")
    draw.text((reference.width + 12, 8), "CANDIDATE / GODOT", fill="white")
    # Keep labels ASCII so this also works with Pillow's fallback font.
    pair.save(args.out_dir / "pair.png")
    Image.blend(reference, candidate, 0.5).save(args.out_dir / "overlay.png")
    ImageEnhance.Brightness(delta).enhance(3).save(args.out_dir / "difference.png")
    (args.out_dir / "comparison.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.out_dir.resolve()), **report["metrics"]}))


if __name__ == "__main__":
    main()
