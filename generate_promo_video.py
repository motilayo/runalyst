import os, math, subprocess, shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(REPO_ROOT, "Media/PromoVideo")
TEMP_FRAMES_DIR = os.path.join(OUTPUT_DIR, "temp_frames")
os.makedirs(OUTPUT_DIR, exist_ok=True)
if os.path.exists(TEMP_FRAMES_DIR):
    shutil.rmtree(TEMP_FRAMES_DIR)
os.makedirs(TEMP_FRAMES_DIR, exist_ok=True)

WIDTH = 1080
HEIGHT = 1920
FPS = 30
TOTAL_DURATION = 25.0
TOTAL_FRAMES = int(TOTAL_DURATION * FPS)

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

def get_font(size, bold=True):
    path = FONT_PATH if bold else "/System/Library/Fonts/HelveticaNeue.ttc"
    try:
        return ImageFont.truetype(path, size)
    except:
        return ImageFont.load_default()


# Preload rendered cards
card_files = [
    os.path.join(REPO_ROOT, "Media/Screenshots/AppStore/01_Intelligent_Biometrics.png"),
    os.path.join(REPO_ROOT, "Media/Screenshots/AppStore/02_AI_Coaching.png"),
    os.path.join(REPO_ROOT, "Media/Screenshots/AppStore/03_Targeted_Drills.png"),
    os.path.join(REPO_ROOT, "Media/Screenshots/AppStore/06_Longitudinal_Progression.png"),
]
loaded_cards = [Image.open(f).convert("RGBA") for f in card_files]

def render_camera_frame(card_img, zoom=1.0, focus_y=0.45):
    """Smooth Ken Burns camera zoom and crop"""
    cw, ch = card_img.size
    crop_w = int(cw / zoom)
    crop_h = int(ch / zoom)
    
    # Calculate crop box centered horizontally and anchored at focus_y vertically
    cx = cw // 2
    cy = int(ch * focus_y)
    
    left = max(0, min(cw - crop_w, cx - crop_w // 2))
    top = max(0, min(ch - crop_h, cy - crop_h // 2))
    right = left + crop_w
    bottom = top + crop_h
    
    cropped = card_img.crop((left, top, right, bottom))
    return cropped.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)

def draw_title_card(t, is_intro=True):
    img = Image.new("RGBA", (WIDTH, HEIGHT), (6, 9, 18, 255))
    draw = ImageDraw.Draw(img)
    
    # Multi-layered glowing ambient particles
    pulse = 0.5 + 0.5 * math.sin(t * 3.5)
    glow_color = (0, 220, 255) if is_intro else (0, 235, 170)
    glow_radius = int(550 + 80 * pulse)
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    
    for r in range(glow_radius, 0, -28):
        alpha = int((1.0 - (r / glow_radius) ** 1.6) * 75)
        glow_draw.ellipse(
            [WIDTH//2 - r, HEIGHT//2 - 80 - r, WIDTH//2 + r, HEIGHT//2 - 80 + r],
            fill=(glow_color[0], glow_color[1], glow_color[2], alpha)
        )
    glow = glow.filter(ImageFilter.GaussianBlur(55))
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)
    
    if is_intro:
        # Category Pill
        tag = "ON-DEVICE RUNNING INTELLIGENCE"
        f_tag = get_font(30, bold=True)
        tb_tag = draw.textbbox((0, 0), tag, font=f_tag)
        tw = tb_tag[2] - tb_tag[0]
        th = tb_tag[3] - tb_tag[1]
        px = (WIDTH - (tw + 48)) // 2
        py = 560
        draw.rounded_rectangle([px, py, px + tw + 48, py + th + 24], radius=(th + 24)//2, fill=(0, 220, 255, 30), outline=(0, 220, 255, 120), width=2)
        draw.text((px + 24, py + 10), tag, fill=(0, 235, 255, 255), font=f_tag)
        
        # App Title
        title = "RUNALYST"
        f_title = get_font(98, bold=True)
        tb_title = draw.textbbox((0, 0), title, font=f_title)
        draw.text(((WIDTH - (tb_title[2]-tb_title[0]))//2, 640), title, fill=(255, 255, 255, 255), font=f_title)
        
        # Subtitle
        sub = "AI Coaching Built for Apple Watch & iPhone"
        f_sub = get_font(38, bold=False)
        tb_sub = draw.textbbox((0, 0), sub, font=f_sub)
        draw.text(((WIDTH - (tb_sub[2]-tb_sub[0]))//2, 780), sub, fill=(200, 220, 245, 240), font=f_sub)
        
        # Feature Badges
        pills = ["Apple FoundationModels", "Biomechanical Telemetry", "100% Private"]
        f_p = get_font(26, bold=True)
        y_p = 860
        for p in pills:
            tb = draw.textbbox((0, 0), p, font=f_p)
            w = tb[2] - tb[0]
            draw.text(((WIDTH - w)//2, y_p), f"•  {p}", fill=(130, 160, 195, 220), font=f_p)
            y_p += 46
    else:
        # Outro Call to Action
        tag = "ELEVATE YOUR RUNNING FORM"
        f_tag = get_font(30, bold=True)
        tb_tag = draw.textbbox((0, 0), tag, font=f_tag)
        tw = tb_tag[2] - tb_tag[0]
        th = tb_tag[3] - tb_tag[1]
        px = (WIDTH - (tw + 48)) // 2
        py = 580
        draw.rounded_rectangle([px, py, px + tw + 48, py + th + 24], radius=(th + 24)//2, fill=(0, 230, 160, 30), outline=(0, 230, 160, 120), width=2)
        draw.text((px + 24, py + 10), tag, fill=(0, 240, 180, 255), font=f_tag)
        
        title = "RUNALYST"
        f_title = get_font(100, bold=True)
        tb_title = draw.textbbox((0, 0), title, font=f_title)
        draw.text(((WIDTH - (tb_title[2]-tb_title[0]))//2, 660), title, fill=(255, 255, 255, 255), font=f_title)
        
        sub = "Run Smarter. Recover Faster."
        f_sub = get_font(42, bold=False)
        tb_sub = draw.textbbox((0, 0), sub, font=f_sub)
        draw.text(((WIDTH - (tb_sub[2]-tb_sub[0]))//2, 800), sub, fill=(220, 235, 255, 240), font=f_sub)
        
        # App Store Button
        pill_w = 440
        pill_h = 80
        bx = (WIDTH - pill_w) // 2
        by = 920
        draw.rounded_rectangle([bx, by, bx + pill_w, by + pill_h], radius=40, fill=(255, 255, 255, 35), outline=(255, 255, 255, 100), width=2)
        badge_txt = "Download on App Store"
        f_b = get_font(32, bold=True)
        tb_b = draw.textbbox((0, 0), badge_txt, font=f_b)
        draw.text((bx + (pill_w - (tb_b[2]-tb_b[0]))//2, by + 22), badge_txt, fill=(255, 255, 255, 255), font=f_b)
        
    return img

print(f"Rendering {TOTAL_FRAMES} high-motion cinematic frames...")

# Timeline:
# 0.0 - 3.8s: Intro
# 3.8 - 8.8s: Card 1 (Biometrics - Ken Burns zoom into VO2 max and Cadence deltas)
# 8.8 - 14.0s: Card 2 (AI Coaching - Ken Burns zoom into AI Run Analysis text)
# 14.0 - 18.5s: Card 3 (Targeted Drills - Ken Burns zoom into Pre-Run Library)
# 18.5 - 22.0s: Card 4 (Progression - Ken Burns pan across 38-run curve)
# 22.0 - 25.0s: Outro Call to Action

for frame_idx in range(TOTAL_FRAMES):
    t = frame_idx / FPS
    
    if t < 3.8:
        base = draw_title_card(t, is_intro=True)
        if t > 3.2:
            alpha = (t - 3.2) / 0.6
            c1_frame = render_camera_frame(loaded_cards[0], zoom=1.0)
            base = Image.blend(base, c1_frame, alpha)
    elif t < 8.8:
        rel_t = t - 3.8
        prog = rel_t / 5.0
        # Smooth zoom from 1.0 to 1.18 into the metrics & coach alert
        zoom = 1.0 + 0.18 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.42 + 0.06 * prog
        curr = render_camera_frame(loaded_cards[0], zoom=zoom, focus_y=focus_y)
        if rel_t > 4.4:
            alpha = (rel_t - 4.4) / 0.6
            c2_frame = render_camera_frame(loaded_cards[1], zoom=1.0)
            curr = Image.blend(curr, c2_frame, alpha)
        base = curr
    elif t < 14.0:
        rel_t = t - 8.8
        prog = rel_t / 5.2
        # Smooth zoom into AI coaching text
        zoom = 1.0 + 0.20 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.38 + 0.05 * prog
        curr = render_camera_frame(loaded_cards[1], zoom=zoom, focus_y=focus_y)
        if rel_t > 4.6:
            alpha = (rel_t - 4.6) / 0.6
            c3_frame = render_camera_frame(loaded_cards[2], zoom=1.0)
            curr = Image.blend(curr, c3_frame, alpha)
        base = curr
    elif t < 18.5:
        rel_t = t - 14.0
        prog = rel_t / 4.5
        # Zoom into drills card
        zoom = 1.0 + 0.16 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.42 + 0.04 * prog
        curr = render_camera_frame(loaded_cards[2], zoom=zoom, focus_y=focus_y)
        if rel_t > 3.9:
            alpha = (rel_t - 3.9) / 0.6
            c4_frame = render_camera_frame(loaded_cards[3], zoom=1.0)
            curr = Image.blend(curr, c4_frame, alpha)
        base = curr
    elif t < 22.0:
        rel_t = t - 18.5
        prog = rel_t / 3.5
        # Pan across longitudinal progression curve
        zoom = 1.05 + 0.15 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.48
        curr = render_camera_frame(loaded_cards[3], zoom=zoom, focus_y=focus_y)
        if rel_t > 2.9:
            alpha = (rel_t - 2.9) / 0.6
            outro = draw_title_card(0.0, is_intro=False)
            curr = Image.blend(curr, outro, alpha)
        base = curr
    else:
        rel_t = t - 22.0
        base = draw_title_card(rel_t, is_intro=False)
        
    frame_path = os.path.join(TEMP_FRAMES_DIR, f"frame_{frame_idx:05d}.jpg")
    base.convert("RGB").save(frame_path, "JPEG", quality=94)
    
    if frame_idx % 90 == 0:
        print(f"Rendered frame {frame_idx}/{TOTAL_FRAMES} ({(frame_idx/TOTAL_FRAMES)*100:.1f}%)")

print("All frames rendered! Encoding silent promo videos...")

video_vertical = os.path.join(OUTPUT_DIR, "Runalyst_Promo_9x16.mp4")
video_landscape = os.path.join(OUTPUT_DIR, "Runalyst_Promo_16x9.mp4")

# 1. Vertical 9:16 Video
cmd_vert = [
    "ffmpeg", "-y",
    "-framerate", "30",
    "-i", os.path.join(TEMP_FRAMES_DIR, "frame_%05d.jpg"),
    "-an",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
    "-t", str(TOTAL_DURATION),
    video_vertical
]
subprocess.run(cmd_vert, check=True)
print(f"Created vertical promo video: {video_vertical}")

# 2. Landscape 16:9 Video
cmd_horiz = [
    "ffmpeg", "-y",
    "-i", video_vertical,
    "-filter_complex",
    "[0:v]split=2[fg][bg];[bg]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,gblur=sigma=45[blurred];[fg]scale=-1:1000[fg_scaled];[blurred][fg_scaled]overlay=(W-w)/2:(H-h)/2[v]",
    "-map", "[v]",
    "-an",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
    "-t", str(TOTAL_DURATION),
    video_landscape
]
subprocess.run(cmd_horiz, check=True)
print(f"Created landscape promo video: {video_landscape}")

shutil.rmtree(TEMP_FRAMES_DIR)
web_landscape = os.path.join(REPO_ROOT, "website/assets/videos/promo_landscape.mp4")
os.makedirs(os.path.dirname(web_landscape), exist_ok=True)
shutil.copyfile(video_landscape, web_landscape)
print(f"Copied landscape promo video to {web_landscape}")
print("Complete!")
