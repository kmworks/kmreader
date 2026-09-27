#!/usr/bin/env python3

import json
import os
import subprocess

from PIL import Image

# Configuration
ICON_SVG = "icon.svg"

ASSETS_DIR = "KMReader/Assets.xcassets"
BRAND_ASSETS_DIR = os.path.join(ASSETS_DIR, "AppIcon.brandassets")

# In-app logo imagesets, one per AppIconOption case; artwork matches each .icon bundle
LOGO_IMAGESETS = {
    "logo": ICON_SVG,
    "logoClassic": "KMReader/AppIconClassic.icon/Assets/icon-classic.svg",
    "logoLegacy": "KMReader/AppIconLegacy.icon/Assets/icon.svg",
}

# Scale Factors
SCALE_FACTOR_APP = 1  # iOS/Mac
SCALE_FACTOR_TV = 1  # tvOS (Zoomed/Cropped)

# Maximum texture size
MAX_RENDER_DIM = 8000


def ensure_dir(path):
    if not os.path.exists(path):
        os.makedirs(path)


def generate_icon_render_supersampled(target_size, svg_file):
    """
    Render a specific SVG to a larger size using rsvg-convert, then downscale using Bicubic.
    """
    if not os.path.exists(svg_file):
        print(f"Warning: {svg_file} not found! Falling back to {ICON_SVG}...")
        if os.path.exists(ICON_SVG):
            svg_file = ICON_SVG
        else:
            return None

    # 8x Supersampling
    factor = 8

    render_size = int(target_size * factor)

    if render_size > MAX_RENDER_DIM:
        render_size = MAX_RENDER_DIM
        factor = render_size / target_size

    temp_filename = f"temp_{os.path.basename(svg_file)}_{render_size}.png"

    try:
        subprocess.run(
            [
                "rsvg-convert",
                "-w",
                str(render_size),
                "-h",
                str(render_size),
                svg_file,
                "-o",
                temp_filename,
            ],
            check=True,
        )

        # Open and convert to RGBA immediately
        img = Image.open(temp_filename).convert("RGBA")

        if target_size > 0 and target_size != render_size:
            img = img.resize((target_size, target_size), Image.Resampling.BICUBIC)

        return img

    except Exception as e:
        print(f"Error rendering {svg_file}: {e}")
        return None
    finally:
        if os.path.exists(temp_filename):
            os.remove(temp_filename)


def create_composition(
    width,
    height,
    dest_path,
    svg_file,
    bg_color=None,
    transparent=False,
    scale_factor=SCALE_FACTOR_APP,
):
    """
    Create an icon composition.
    """

    if transparent:
        canvas = Image.new("RGBA", (width, height), (255, 255, 255, 0))
    else:
        # Strictly RGB for Opaque
        color = bg_color if bg_color else (255, 255, 255)
        canvas = Image.new("RGB", (width, height), color)

    # Logo dimensions
    target_h = int(height * scale_factor)
    if target_h % 2 != 0:
        target_h -= 1
    target_w = target_h

    # Scale relative to width if width is smaller (for landscape)
    # But for scaling > 1.0 (Full Bleed/Cropped), we might want to respect the requested dimension
    # logic: if we want 1.08 * height, then height is the constraint.
    # If the canvas is wide (Top Shelf), 1.08 height is fine.
    # If the canvas is square, 1.08 height is fine (crop vertical).

    # Check width constraint for App Icons (usually < 1.0 scale)
    if scale_factor <= 1.0 and target_w > width * scale_factor:
        target_w = int(width * scale_factor)
        if target_w % 2 != 0:
            target_w -= 1
        target_h = target_w

    logo_img = generate_icon_render_supersampled(target_w, svg_file)
    if logo_img is None:
        return

    x = (width - target_w) // 2
    y = (height - target_h) // 2

    if canvas.mode == "RGBA":
        canvas.paste(logo_img, (x, y), logo_img)
    else:
        # Paste RGBA onto RGB
        canvas.paste(logo_img, (x, y), logo_img)

    logo_img.close()

    ensure_dir(os.path.dirname(dest_path))
    canvas.save(dest_path)
    print(f"Saved: {dest_path}")


def create_top_shelf_composition(width, height, dest_path):
    # Specialized for TV Top Shelf using DEFAULT icon style
    canvas = Image.new("RGB", (width, height), (255, 255, 255))

    # 1. Ghost Logo (Decorative) - Sized relative to height
    ghost_size = int(height * 1.1)
    if ghost_size % 2 != 0:
        ghost_size -= 1

    ghost_img = generate_icon_render_supersampled(ghost_size, ICON_SVG).convert("RGBA")
    r, g, b, a = ghost_img.split()
    a = a.point(lambda p: p * 0.05)
    ghost_img = Image.merge("RGBA", (r, g, b, a))

    ghost_y = (height - ghost_size) // 2
    ghost_x_left = -(ghost_size // 2) + int(width * 0.05)
    ghost_x_right = width - (ghost_size // 2) - int(width * 0.05)

    canvas.paste(ghost_img, (ghost_x_left, ghost_y), ghost_img)
    canvas.paste(ghost_img, (ghost_x_right, ghost_y), ghost_img)
    ghost_img.close()

    # 2. Center Logo (Main) -> Use TV Scale (1.08)
    # Using Default Icon for Top Shelf
    target_h = int(height * SCALE_FACTOR_TV)
    if target_h % 2 != 0:
        target_h -= 1
    target_w = target_h

    logo_img = generate_icon_render_supersampled(target_w, ICON_SVG)
    x = (width - target_w) // 2
    y = (height - target_h) // 2
    canvas.paste(logo_img, (x, y), logo_img)
    logo_img.close()

    ensure_dir(os.path.dirname(dest_path))
    canvas.save(dest_path)
    print(f"Saved Top Shelf: {dest_path}")


def create_white_back(width, height, dest_path):
    canvas = Image.new("RGB", (width, height), (255, 255, 255))
    ensure_dir(os.path.dirname(dest_path))
    canvas.save(dest_path)
    print(f"Saved Back: {dest_path}")


def main():
    if not os.path.exists(ICON_SVG):
        print(f"Error: {ICON_SVG} not found.")
        return

    print("Generating ALL assets...")
    print(f"  - App Scale: {SCALE_FACTOR_APP}")
    print(f"  - TV Scale:  {SCALE_FACTOR_TV}")

    # ==========================
    # 1. TV Brand Assets (Uses Default Light Icon) -> Scale: SCALE_FACTOR_TV
    # ==========================

    # App Icon (Small)
    base_dir = os.path.join(BRAND_ASSETS_DIR, "App Icon.imagestack")
    front_dir = os.path.join(base_dir, "Front.imagestacklayer", "Content.imageset")
    create_composition(
        400,
        240,
        os.path.join(front_dir, "icon-400-1x.png"),
        ICON_SVG,
        transparent=True,
        scale_factor=SCALE_FACTOR_TV,
    )
    create_composition(
        800,
        480,
        os.path.join(front_dir, "icon-400-2x.png"),
        ICON_SVG,
        transparent=True,
        scale_factor=SCALE_FACTOR_TV,
    )

    back_dir = os.path.join(base_dir, "Back.imagestacklayer", "Content.imageset")
    create_white_back(400, 240, os.path.join(back_dir, "back-400-1x.png"))
    create_white_back(800, 480, os.path.join(back_dir, "back-400-2x.png"))

    # App Icon - App Store (Large)
    store_dir = os.path.join(BRAND_ASSETS_DIR, "App Icon - App Store.imagestack")
    front_store = os.path.join(store_dir, "Front.imagestacklayer", "Content.imageset")
    create_composition(
        1280,
        768,
        os.path.join(front_store, "icon-1280-1x.png"),
        ICON_SVG,
        transparent=True,
        scale_factor=SCALE_FACTOR_TV,
    )
    create_composition(
        2560,
        1536,
        os.path.join(front_store, "icon-1280-2x.png"),
        ICON_SVG,
        transparent=True,
        scale_factor=SCALE_FACTOR_TV,
    )

    back_store = os.path.join(store_dir, "Back.imagestacklayer", "Content.imageset")
    create_white_back(1280, 768, os.path.join(back_store, "back-1280-1x.png"))
    create_white_back(2560, 1536, os.path.join(back_store, "back-1280-2x.png"))

    # Top Shelf Images (Designed)
    top_dir = os.path.join(BRAND_ASSETS_DIR, "Top Shelf Image.imageset")
    create_top_shelf_composition(1920, 720, os.path.join(top_dir, "topshelf-1x.png"))
    create_top_shelf_composition(3840, 1440, os.path.join(top_dir, "topshelf-2x.png"))

    # Top Shelf Wide
    wide_dir = os.path.join(BRAND_ASSETS_DIR, "Top Shelf Image Wide.imageset")
    create_top_shelf_composition(
        2320, 720, os.path.join(wide_dir, "topshelf-wide-1x.png")
    )
    create_top_shelf_composition(
        4640, 1440, os.path.join(wide_dir, "topshelf-wide-2x.png")
    )

    # ==========================
    # 2. logo imagesets (in-app use, one per AppIconOption)
    # ==========================
    for name, svg_file in LOGO_IMAGESETS.items():
        imageset_dir = os.path.join(ASSETS_DIR, f"{name}.imageset")
        for size, suffix in ((1024, ""), (2048, "@2x"), (3072, "@3x")):
            create_composition(
                size,
                size,
                os.path.join(imageset_dir, f"{name}{suffix}.png"),
                svg_file,
                transparent=True,
                scale_factor=1.0,
            )
        contents = {
            "images": [
                {"filename": f"{name}{s}.png", "idiom": "universal", "scale": sc}
                for s, sc in (("", "1x"), ("@2x", "2x"), ("@3x", "3x"))
            ],
            "info": {"author": "xcode", "version": 1},
        }
        ensure_dir(imageset_dir)
        with open(os.path.join(imageset_dir, "Contents.json"), "w") as fp:
            json.dump(contents, fp, indent=2)
            fp.write("\n")
        print(f"Saved: {imageset_dir}/Contents.json")

    print("All Top Shelf and Logo assets regenerated.")


if __name__ == "__main__":
    main()
