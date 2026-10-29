import os
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))

OUTPUT_DIR_PORTRAIT_2778 = os.path.join(REPO_ROOT, "Media/Screenshots/AppStore")
OUTPUT_DIR_PORTRAIT_2688 = os.path.join(REPO_ROOT, "Media/Screenshots/AppStore_1242x2688")
OUTPUT_DIR_LANDSCAPE_2778 = os.path.join(REPO_ROOT, "Media/Screenshots/AppStore_2778x1284")
OUTPUT_DIR_LANDSCAPE_2688 = os.path.join(REPO_ROOT, "Media/Screenshots/AppStore_2688x1242")
OUTPUT_DIR_DUO_OUTER_PORTRAIT = os.path.join(REPO_ROOT, "Media/Screenshots/iPhoneDuo_Outer_1398x2034")
OUTPUT_DIR_DUO_OUTER_LANDSCAPE = os.path.join(REPO_ROOT, "Media/Screenshots/iPhoneDuo_Outer_2034x1398")
OUTPUT_DIR_DUO_INNER_PORTRAIT = os.path.join(REPO_ROOT, "Media/Screenshots/iPhoneDuo_Inner_2007x2853")
OUTPUT_DIR_DUO_INNER_LANDSCAPE = os.path.join(REPO_ROOT, "Media/Screenshots/iPhoneDuo_Inner_2853x2007")
WEB_DIR = os.path.join(REPO_ROOT, "website/assets/images")

os.makedirs(OUTPUT_DIR_PORTRAIT_2778, exist_ok=True)
os.makedirs(OUTPUT_DIR_PORTRAIT_2688, exist_ok=True)
os.makedirs(OUTPUT_DIR_LANDSCAPE_2778, exist_ok=True)
os.makedirs(OUTPUT_DIR_LANDSCAPE_2688, exist_ok=True)
os.makedirs(OUTPUT_DIR_DUO_OUTER_PORTRAIT, exist_ok=True)
os.makedirs(OUTPUT_DIR_DUO_OUTER_LANDSCAPE, exist_ok=True)
os.makedirs(OUTPUT_DIR_DUO_INNER_PORTRAIT, exist_ok=True)
os.makedirs(OUTPUT_DIR_DUO_INNER_LANDSCAPE, exist_ok=True)
os.makedirs(WEB_DIR, exist_ok=True)

# Target App Store Connect Specifications:
# Portrait: 1284 x 2778 (6.7"), 1242 x 2688 (6.5")
WIDTH_P = 1284
HEIGHT_P = 2778

# Landscape: 2778 x 1284 (6.7"), 2688 x 1242 (6.5")
WIDTH_L = 2778
HEIGHT_L = 1284

# Load fonts
FONT_HEAD_BOLD = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

def get_font(size, bold=True):
    path = FONT_HEAD_BOLD if bold else "/System/Library/Fonts/HelveticaNeue.ttc"
    try:
        return ImageFont.truetype(path, size)
    except:
        return ImageFont.load_default()

def frame_screenshot(screenshot_path, scale_factor=0.86, corner_radius=68):
    src = Image.open(screenshot_path).convert("RGBA")
    sw, sh = src.size
    
    target_w = int(sw * scale_factor)
    target_h = int(sh * scale_factor)
    src_scaled = src.resize((target_w, target_h), Image.Resampling.LANCZOS)
    
    # Rounded corners mask
    mask = Image.new("L", (target_w, target_h), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, target_w, target_h], radius=corner_radius, fill=255)
    
    # Create framed screen
    framed = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    framed.paste(src_scaled, (0, 0), mask=mask)
    
    # Minimalist sleek bezel border for device framing against black
    border_draw = ImageDraw.Draw(framed)
    border_draw.rounded_rectangle([0, 0, target_w, target_h], radius=corner_radius, outline=(255, 255, 255, 75), width=3)
    border_draw.rounded_rectangle([2, 2, target_w - 2, target_height if 'target_height' in locals() else target_h - 2], radius=corner_radius - 2, outline=(0, 0, 0, 160), width=2)
    
    return framed

def render_portrait_card(title, subtitle, screenshot_path, output_filename):
    bg = Image.new("RGBA", (WIDTH_P, HEIGHT_P), (0, 0, 0, 255))
    draw = ImageDraw.Draw(bg)
    
    # 1. Main Title (White)
    font_title = get_font(72, bold=True)
    tb_title = draw.textbbox((0, 0), title, font=font_title)
    title_w = tb_title[2] - tb_title[0]
    title_x = (WIDTH_P - title_w) // 2
    title_y = 160
    draw.text((title_x, title_y), title, fill=(255, 255, 255, 255), font=font_title)
    
    # 2. Subtitle (White / Soft White)
    font_sub = get_font(38, bold=False)
    tb_sub = draw.textbbox((0, 0), subtitle, font=font_sub)
    sub_w = tb_sub[2] - tb_sub[0]
    sub_x = (WIDTH_P - sub_w) // 2
    sub_y = title_y + 94
    draw.text((sub_x, sub_y), subtitle, fill=(230, 230, 235, 255), font=font_sub)
    
    # 3. Framed Screenshot
    framed = frame_screenshot(screenshot_path, scale_factor=0.86, corner_radius=68)
    fw, fh = framed.size
    fx = (WIDTH_P - fw) // 2
    fy = sub_y + 85
    bg.paste(framed, (fx, fy), mask=framed)
    
    # Save primary 1284 x 2778 (6.7" / 6.9" display)
    out_2778 = os.path.join(OUTPUT_DIR_PORTRAIT_2778, output_filename)
    bg_rgb = bg.convert("RGB")
    bg_rgb.save(out_2778, "PNG", quality=98)
    print(f"Rendered Portrait 1284x2778: {out_2778}")

    # Save 1242 x 2688 (6.5" display)
    out_2688 = os.path.join(OUTPUT_DIR_PORTRAIT_2688, output_filename)
    bg_2688 = bg_rgb.resize((1242, 2688), Image.Resampling.LANCZOS)
    bg_2688.save(out_2688, "PNG", quality=98)
    print(f"Rendered Portrait 1242x2688: {out_2688}")

    # Save iPhone Duo Outer Display 1398 x 2034 (Portrait)
    out_duo_outer = os.path.join(OUTPUT_DIR_DUO_OUTER_PORTRAIT, output_filename)
    bg_duo_outer = bg_rgb.resize((1398, 2034), Image.Resampling.LANCZOS)
    bg_duo_outer.save(out_duo_outer, "PNG", quality=98)
    print(f"Rendered iPhone Duo Outer Portrait 1398x2034: {out_duo_outer}")

    # Save iPhone Duo Inner Display 2007 x 2853 (Portrait)
    out_duo_inner = os.path.join(OUTPUT_DIR_DUO_INNER_PORTRAIT, output_filename)
    bg_duo_inner = bg_rgb.resize((2007, 2853), Image.Resampling.LANCZOS)
    bg_duo_inner.save(out_duo_inner, "PNG", quality=98)
    print(f"Rendered iPhone Duo Inner Portrait 2007x2853: {out_duo_inner}")

    # Save to website assets
    out_web = os.path.join(WEB_DIR, output_filename)
    bg_rgb.save(out_web, "PNG", quality=98)

def render_landscape_card(title, subtitle, screenshot_path, output_filename):
    bg = Image.new("RGBA", (WIDTH_L, HEIGHT_L), (0, 0, 0, 255))
    draw = ImageDraw.Draw(bg)
    
    font_title = get_font(68, bold=True)
    tb_title = draw.textbbox((0, 0), title, font=font_title)
    title_w = tb_title[2] - tb_title[0]
    title_x = (WIDTH_L - title_w) // 2
    title_y = 50
    draw.text((title_x, title_y), title, fill=(255, 255, 255, 255), font=font_title)
    
    font_sub = get_font(36, bold=False)
    tb_sub = draw.textbbox((0, 0), subtitle, font=font_sub)
    sub_w = tb_sub[2] - tb_sub[0]
    sub_x = (WIDTH_L - sub_w) // 2
    sub_y = 135
    draw.text((sub_x, sub_y), subtitle, fill=(220, 220, 225, 255), font=font_sub)
    
    src = Image.open(screenshot_path).convert("RGBA")
    sw, sh = src.size
    target_h = 980
    scale = target_h / sh
    target_w = int(sw * scale)
    src_scaled = src.resize((target_w, target_h), Image.Resampling.LANCZOS)
    
    mask = Image.new("L", (target_w, target_h), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, target_w, target_h], radius=50, fill=255)
    
    framed = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    framed.paste(src_scaled, (0, 0), mask=mask)
    
    border_draw = ImageDraw.Draw(framed)
    border_draw.rounded_rectangle([0, 0, target_w, target_h], radius=50, outline=(255, 255, 255, 75), width=3)
    border_draw.rounded_rectangle([2, 2, target_w - 2, target_h - 2], radius=48, outline=(0, 0, 0, 160), width=2)
    
    fw, fh = framed.size
    fx = (WIDTH_L - fw) // 2
    fy = 220
    bg.paste(framed, (fx, fy), mask=framed)
    
    # Save 2778 x 1284 (6.7" display landscape)
    out_2778 = os.path.join(OUTPUT_DIR_LANDSCAPE_2778, output_filename)
    bg_rgb = bg.convert("RGB")
    bg_rgb.save(out_2778, "PNG", quality=98)
    print(f"Rendered Landscape 2778x1284: {out_2778}")

    # Save 2688 x 1242 (6.5" display landscape)
    out_2688 = os.path.join(OUTPUT_DIR_LANDSCAPE_2688, output_filename)
    bg_2688 = bg_rgb.resize((2688, 1242), Image.Resampling.LANCZOS)
    bg_2688.save(out_2688, "PNG", quality=98)
    print(f"Rendered Landscape 2688x1242: {out_2688}")

    # Save iPhone Duo Outer Display 2034 x 1398 (Landscape)
    out_duo_outer_l = os.path.join(OUTPUT_DIR_DUO_OUTER_LANDSCAPE, output_filename)
    bg_duo_outer_l = bg_rgb.resize((2034, 1398), Image.Resampling.LANCZOS)
    bg_duo_outer_l.save(out_duo_outer_l, "PNG", quality=98)
    print(f"Rendered iPhone Duo Outer Landscape 2034x1398: {out_duo_outer_l}")

    # Save iPhone Duo Inner Display 2853 x 2007 (Landscape)
    out_duo_inner_l = os.path.join(OUTPUT_DIR_DUO_INNER_LANDSCAPE, output_filename)
    bg_duo_inner_l = bg_rgb.resize((2853, 2007), Image.Resampling.LANCZOS)
    bg_duo_inner_l.save(out_duo_inner_l, "PNG", quality=98)
    print(f"Rendered iPhone Duo Inner Landscape 2853x2007: {out_duo_inner_l}")

cards = [
    {
        "title": "Intelligent Running Biometrics",
        "subtitle": "Live cadence deltas & 30-day relative baselines",
        "screenshot": os.path.join(REPO_ROOT, "Media/Screenshots/iPhone_Raw/screen_dashboard.png"),
        "output": "01_Intelligent_Biometrics.png",
    },
    {
        "title": "On-Device AI Coaching",
        "subtitle": "Apple FoundationModels guidance tailored to fatigue",
        "screenshot": os.path.join(REPO_ROOT, "Media/Screenshots/iPhone_Raw/screen_run_detail.png"),
        "output": "02_AI_Coaching.png",
    },
    {
        "title": "Targeted Form Drills",
        "subtitle": "Structured phase breakdown & Apple Watch export",
        "screenshot": os.path.join(REPO_ROOT, "Media/Screenshots/iPhone_Raw/screen_drill_readout.png"),
        "output": "03_Targeted_Drills.png",
    },
    {
        "title": "Biomechanical Form Analysis",
        "subtitle": "Vertical bounce, ground contact time & overstride alerts",
        "screenshot": os.path.join(REPO_ROOT, "Media/Screenshots/iPhone_Raw/screen_biomechanics.png"),
        "output": "04_Biomechanical_Analysis.png",
    },
    {
        "title": "Structured Runs & Primers",
        "subtitle": "Daily workout prescriptions & pre-run primers for Watch",
        "screenshot": os.path.join(REPO_ROOT, "Media/Screenshots/iPhone_Raw/screen_drills.png"),
        "output": "05_PreRun_Library.png",
    },
    {
        "title": "Longitudinal Progression",
        "subtitle": "Track efficiency factor gains and cadence over time",
        "screenshot": os.path.join(REPO_ROOT, "Media/Screenshots/iPhone_Raw/screen_progression.png"),
        "output": "06_Longitudinal_Progression.png",
    },
    {
        "title": "100% Private & HealthKit-Native",
        "subtitle": "Zero cloud tracking. Seamless Apple Watch sync.",
        "screenshot": os.path.join(REPO_ROOT, "Media/Screenshots/iPhone_Raw/screen_settings.png"),
        "output": "07_HealthKit_Privacy.png",
    }
]

if __name__ == "__main__":
    for c in cards:
        render_portrait_card(c["title"], c["subtitle"], c["screenshot"], c["output"])
        render_landscape_card(c["title"], c["subtitle"], c["screenshot"], c["output"])
