"""Discovery Card generator — shareable images for high-confidence findings.

When a miner detects a high-confidence exoplanet, galaxy, or anomaly,
this generates a beautiful shareable card for Twitter/social media.

Usage:
    voidmap-card --result path/to/result.json
    voidmap-card --target TOI-732 --prediction PLANET --confidence 0.92
"""
from __future__ import annotations

import argparse
import json
import random
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class CardSpec:
    """Specification for one Discovery Card."""
    target: str
    tic_id: str
    task: str
    prediction: str
    confidence: float
    quality: int
    miner: str
    backend: str
    timestamp: int
    block: Optional[int] = None
    tx_hash: Optional[str] = None
    extra: dict = None

    @property
    def title(self) -> str:
        if self.task == "exoplanet_transit":
            return f"🌍 Exoplanet Candidate: {self.target}"
        if self.task == "galaxy_morphology":
            return f"🌌 Galaxy Classified: {self.target}"
        if self.task == "anomaly_detection":
            return f"⚠️  Anomaly Detected in ZTF Survey"
        return f"✨ Discovery: {self.target}"

    @property
    def subtitle(self) -> str:
        if self.task == "exoplanet_transit":
            return f"Predicted: {self.prediction} • Confidence: {self.confidence:.1%}"
        return f"Class: {self.prediction} • Confidence: {self.confidence:.1%}"

    @property
    def caption(self) -> str:
        return (
            f"I just discovered something in the night sky with Voidmap. "
            f"Find more: voidmap.org"
        )

    def to_text(self) -> str:
        """Plain text version (for Twitter without image)."""
        text = f"{self.title}\n\n"
        text += f"{self.subtitle}\n"
        text += f"Quality: {self.quality}/100\n"
        if self.tic_id:
            text += f"TIC: {self.tic_id}\n"
        text += f"Miner: {self.miner[:8]}...{self.miner[-4:]}\n"
        if self.tx_hash:
            text += f"TX: {self.tx_hash[:10]}...{self.tx_hash[-6:]}\n"
        text += f"\nMined with Voidmap — proof of useful work\n"
        text += f"voidmap.org"
        return text


def render_card(spec: CardSpec, output: Path) -> Path:
    """Render a Discovery Card image. Returns the output path."""
    try:
        from PIL import Image, ImageDraw, ImageFont, ImageFilter
    except ImportError:
        # Fall back to text if PIL not available
        return render_text_card(spec, output)

    W, H = 1200, 675
    img = Image.new("RGB", (W, H), color=(8, 12, 28))
    draw = ImageDraw.Draw(img)

    # ── Background gradient (procedural stars) ──
    rng = random.Random(spec.target + str(spec.timestamp))
    for _ in range(300):
        x = rng.randint(0, W)
        y = rng.randint(0, H)
        r = rng.randint(1, 3)
        brightness = rng.randint(150, 255)
        draw.ellipse([x - r, y - r, x + r, y + r],
                     fill=(brightness, brightness, brightness))

    # Add a few colored stars
    for _ in range(20):
        x = rng.randint(0, W)
        y = rng.randint(0, H)
        color = rng.choice([(255, 200, 100), (100, 200, 255), (255, 100, 150)])
        draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=color)

    # ── Title ──
    try:
        title_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 56)
        body_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 28)
        small_font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
    except Exception:
        try:
            title_font = ImageFont.truetype("arial.ttf", 56)
            body_font = ImageFont.truetype("arial.ttf", 28)
            small_font = ImageFont.truetype("arial.ttf", 20)
        except Exception:
            title_font = ImageFont.load_default()
            body_font = ImageFont.load_default()
            small_font = ImageFont.load_default()

    # Title
    title = spec.title
    bbox = draw.textbbox((0, 0), title, font=title_font)
    tw = bbox[2] - bbox[0]
    draw.text(((W - tw) // 2, 100), title, fill=(255, 255, 255), font=title_font)

    # Subtitle
    sub = spec.subtitle
    bbox = draw.textbbox((0, 0), sub, font=body_font)
    sw = bbox[2] - bbox[0]
    draw.text(((W - sw) // 2, 200), sub, fill=(180, 200, 255), font=body_font)

    # Quality bar
    bar_x, bar_y = 300, 320
    bar_w, bar_h = 600, 40
    draw.rectangle([bar_x, bar_y, bar_x + bar_w, bar_y + bar_h],
                   fill=(40, 50, 80), outline=(100, 120, 180), width=2)
    fill_w = int(bar_w * spec.quality / 100)
    color = (100, 255, 100) if spec.quality >= 70 else (255, 200, 100) if spec.quality >= 50 else (255, 100, 100)
    draw.rectangle([bar_x, bar_y, bar_x + fill_w, bar_y + bar_h], fill=color)
    quality_text = f"Quality: {spec.quality}/100"
    bbox = draw.textbbox((0, 0), quality_text, font=body_font)
    qw = bbox[2] - bbox[0]
    draw.text(((W - qw) // 2, bar_y + 5), quality_text, fill=(20, 20, 30), font=body_font)

    # Details box
    details_y = 420
    details = []
    if spec.tic_id:
        details.append(f"TIC: {spec.tic_id}")
    details.append(f"Miner: {spec.miner[:8]}...{spec.miner[-4:]}")
    details.append(f"Backend: {spec.backend}")
    if spec.tx_hash:
        details.append(f"TX: {spec.tx_hash[:10]}...{spec.tx_hash[-6:]}")
    details.append(f"voidmap.org")

    for i, line in enumerate(details):
        bbox = draw.textbbox((0, 0), line, font=small_font)
        lw = bbox[2] - bbox[0]
        draw.text(((W - lw) // 2, details_y + i * 28), line,
                  fill=(150, 180, 220), font=small_font)

    # Footer
    footer = "Voidmap — Proof of Useful Work on Base"
    bbox = draw.textbbox((0, 0), footer, font=small_font)
    fw = bbox[2] - bbox[0]
    draw.text(((W - fw) // 2, H - 50), footer,
              fill=(120, 140, 180), font=small_font)

    # Save
    output.parent.mkdir(parents=True, exist_ok=True)
    img.save(output, "PNG", quality=95)
    return output


def render_text_card(spec: CardSpec, output: Path) -> Path:
    """Text-only fallback (no PIL)."""
    output.parent.mkdir(parents=True, exist_ok=True)
    with open(output.with_suffix(".txt"), "w") as f:
        f.write(spec.to_text())
    return output.with_suffix(".txt")


def from_result(result_path: Path, miner: str = "0x0000", tx_hash: Optional[str] = None,
                block: Optional[int] = None) -> CardSpec:
    """Build a CardSpec from a result JSON file."""
    with open(result_path) as f:
        r = json.load(f)
    return CardSpec(
        target=r.get("target", "Unknown"),
        tic_id=r.get("extra", {}).get("tic_id", ""),
        task=r.get("task", ""),
        prediction=r.get("prediction", ""),
        confidence=r.get("confidence", 0),
        quality=r.get("quality_score", 0),
        miner=miner,
        backend=r.get("backend", ""),
        timestamp=r.get("timestamp", int(time.time())),
        block=block,
        tx_hash=tx_hash or r.get("tx_hash"),
        extra=r.get("extra", {}),
    )


# ─── CLI ──────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description="Voidmap Discovery Card generator")
    p.add_argument("--result", type=Path, help="Path to result JSON file")
    p.add_argument("--target", help="Target name (TOI-732, NGC 4565, etc.)")
    p.add_argument("--tic", help="TIC ID (for exoplanets)")
    p.add_argument("--task", choices=["exoplanet_transit", "galaxy_morphology", "anomaly_detection"])
    p.add_argument("--prediction", help="Prediction (PLANET, Spiral, etc.)")
    p.add_argument("--confidence", type=float, help="Confidence 0-1")
    p.add_argument("--quality", type=int, help="Quality 0-100")
    p.add_argument("--miner", default="0x0000000000000000000000000000000000000000", help="Miner address")
    p.add_argument("--backend", default="", help="Backend used")
    p.add_argument("--tx", help="Transaction hash (if submitted)")
    p.add_argument("--output", "-o", type=Path, default=Path("./discovery_card.png"),
                   help="Output path")
    p.add_argument("--text", action="store_true", help="Also output text version")
    args = p.parse_args()

    if args.result:
        spec = from_result(args.result, miner=args.miner, tx_hash=args.tx)
    else:
        if not all([args.target, args.task, args.prediction, args.confidence is not None, args.quality is not None]):
            p.error("Must provide --result OR all of --target --task --prediction --confidence --quality")
        spec = CardSpec(
            target=args.target,
            tic_id=args.tic or "",
            task=args.task,
            prediction=args.prediction,
            confidence=args.confidence,
            quality=args.quality,
            miner=args.miner,
            backend=args.backend,
            timestamp=int(time.time()),
            tx_hash=args.tx,
        )

    out = render_card(spec, args.output)
    print(f"Card rendered: {out}")

    if args.text:
        text_out = args.output.with_suffix(".txt")
        with open(text_out, "w") as f:
            f.write(spec.to_text())
        print(f"Text version: {text_out}")


if __name__ == "__main__":
    main()
