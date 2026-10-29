import os, math, subprocess, shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(REPO_ROOT, "Media/PromoVideo")
TEMP_FRAMES_DIR = os.path.join(OUTPUT_DIR, "temp_ipad_frames")
os.makedirs(OUTPUT_DIR, exist_ok=True)
if os.path.exists(TEMP_FRAMES_DIR):
    shutil.rmtree(TEMP_FRAMES_DIR)
os.makedirs(TEMP_FRAMES_DIR, exist_ok=True)

WIDTH = 1920
HEIGHT = 1080
FPS = 30
TOTAL_DURATION = 25.0
TOTAL_FRAMES = int(TOTAL_DURATION * FPS)

FONT_PATH = "/System/Library/Fonts/SFNS.ttf"

def get_font(size, bold=True):
    path = FONT_PATH if bold else "/System/Library/Fonts/HelveticaNeue.ttc"
    try:
        return ImageFont.truetype(path, size)
    except:
        return ImageFont.load_default()

card_files = [
    os.path.join(REPO_ROOT, "Media/Screenshots/iPad_2048x2732/01_Intelligent_Biometrics.png"),
    os.path.join(REPO_ROOT, "Media/Screenshots/iPad_2048x2732/02_AI_Coaching.png"),
    os.path.join(REPO_ROOT, "Media/Screenshots/iPad_2048x2732/03_Targeted_Drills.png"),
    os.path.join(REPO_ROOT, "Media/Screenshots/iPad_2048x2732/04_Biomechanical_Analysis.png"),
    os.path.join(REPO_ROOT, "Media/Screenshots/iPad_2048x2732/06_Longitudinal_Progression.png"),
]
loaded_cards = [Image.open(f).convert("RGBA") for f in card_files]

def render_ipad_frame(card_img, zoom=1.0, focus_y=0.45):
    """Smooth Ken Burns zoom and crop for iPad presentation cards in 16:9 canvas"""
    cw, ch = card_img.size
    
    # Target 16:9 aspect inside the card
    target_aspect = WIDTH / HEIGHT
    card_aspect = cw / ch
    
    if card_aspect > target_aspect:
        base_h = ch
        base_w = int(ch * target_aspect)
    else:
        base_w = cw
        base_h = int(cw / target_aspect)
        
    crop_w = int(base_w / zoom)
    crop_h = int(base_h / zoom)
    
    cx = cw // 2
    cy = int(ch * focus_y)
    
    left = max(0, min(cw - crop_w, cx - crop_w // 2))
    top = max(0, min(ch - crop_h, cy - crop_h // 2))
    right = left + crop_w
    bottom = top + crop_h
    
    cropped = card_img.crop((left, top, right, bottom))
    return cropped.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)

def draw_title_card(t, is_intro=True):
    img = Image.new("RGBA", (WIDTH, HEIGHT), (8, 12, 22, 255))
    draw = ImageDraw.Draw(img)
    
    pulse = 0.5 + 0.5 * math.sin(t * 3.5)
    glow_color = (0, 210, 255) if is_intro else (0, 235, 170)
    glow_radius = int(600 + 80 * pulse)
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    
    for r in range(glow_radius, 0, -32):
        alpha = int((1.0 - (r / glow_radius) ** 1.6) * 70)
        glow_draw.ellipse(
            [WIDTH//2 - r, HEIGHT//2 - r, WIDTH//2 + r, HEIGHT//2 + r],
            fill=(glow_color[0], glow_color[1], glow_color[2], alpha)
        )
    glow = glow.filter(ImageFilter.GaussianBlur(65))
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)
    
    if is_intro:
        tag = "DESIGNED FOR IPAD & APPLE WATCH"
        f_tag = get_font(26, bold=True)
        tb_tag = draw.textbbox((0, 0), tag, font=f_tag)
        tw = tb_tag[2] - tb_tag[0]
        th = tb_tag[3] - tb_tag[1]
        px = (WIDTH - (tw + 48)) // 2
        py = 320
        draw.rounded_rectangle([px, py, px + tw + 48, py + th + 22], radius=(th + 22)//2, fill=(0, 210, 255, 30), outline=(0, 210, 255, 120), width=2)
        draw.text((px + 24, py + 9), tag, fill=(0, 235, 255, 255), font=f_tag)
        
        title = "RUNALYST FOR IPAD"
        f_title = get_font(88, bold=True)
        tb_title = draw.textbbox((0, 0), title, font=f_title)
        draw.text(((WIDTH - (tb_title[2]-tb_title[0]))//2, 400), title, fill=(255, 255, 255, 255), font=f_title)
        
        sub = "Expansive Running Biometrics, Drill Breakdowns & AI Coaching"
        f_sub = get_font(36, bold=False)
        tb_sub = draw.textbbox((0, 0), sub, font=f_sub)
        draw.text(((WIDTH - (tb_sub[2]-tb_sub[0]))//2, 530), sub, fill=(200, 220, 245, 240), font=f_sub)
        
        pills = "11-Profile Taxonomy  •  Mental Readiness Readouts  •  Overstride Kinematics  •  100% Private"
        f_p = get_font(24, bold=True)
        tb_p = draw.textbbox((0, 0), pills, font=f_p)
        draw.text(((WIDTH - (tb_p[2]-tb_p[0]))//2, 620), pills, fill=(130, 165, 205, 230), font=f_p)
    else:
        tag = "UNLOCK YOUR TRUE RUNNING ECONOMY"
        f_tag = get_font(26, bold=True)
        tb_tag = draw.textbbox((0, 0), tag, font=f_tag)
        tw = tb_tag[2] - tb_tag[0]
        th = tb_tag[3] - tb_tag[1]
        px = (WIDTH - (tw + 48)) // 2
        py = 330
        draw.rounded_rectangle([px, py, px + tw + 48, py + th + 22], radius=(th + 22)//2, fill=(0, 230, 160, 30), outline=(0, 230, 160, 120), width=2)
        draw.text((px + 24, py + 9), tag, fill=(0, 240, 180, 255), font=f_tag)
        
        title = "RUNALYST"
        f_title = get_font(90, bold=True)
        tb_title = draw.textbbox((0, 0), title, font=f_title)
        draw.text(((WIDTH - (tb_title[2]-tb_title[0]))//2, 410), title, fill=(255, 255, 255, 255), font=f_title)
        
        sub = "Download on the App Store for iPhone, iPad & Apple Watch"
        f_sub = get_font(36, bold=False)
        tb_sub = draw.textbbox((0, 0), sub, font=f_sub)
        draw.text(((WIDTH - (tb_sub[2]-tb_sub[0]))//2, 540), sub, fill=(220, 235, 255, 240), font=f_sub)
        
        pill_w = 400
        pill_h = 70
        bx = (WIDTH - pill_w) // 2
        by = 640
        draw.rounded_rectangle([bx, by, bx + pill_w, by + pill_h], radius=35, fill=(255, 255, 255, 35), outline=(255, 255, 255, 100), width=2)
        badge_txt = "Available on App Store"
        f_b = get_font(28, bold=True)
        tb_b = draw.textbbox((0, 0), badge_txt, font=f_b)
        draw.text((bx + (pill_w - (tb_b[2]-tb_b[0]))//2, by + 19), badge_txt, fill=(255, 255, 255, 255), font=f_b)
        
    return img

print(f"Rendering {TOTAL_FRAMES} iPad promo frames...")

# Timeline:
# 0.0 - 3.5s: Intro
# 3.5 - 7.8s: Card 1 (Biometrics)
# 7.8 - 12.0s: Card 2 (AI Coaching)
# 12.0 - 16.5s: Card 3 (Targeted Drills & Breakdown)
# 16.5 - 20.5s: Card 4 (Biomechanical Form & Overstride)
# 20.5 - 22.5s: Card 5 (Progression)
# 22.5 - 25.0s: Outro Call to Action

for frame_idx in range(TOTAL_FRAMES):
    t = frame_idx / FPS
    
    if t < 3.5:
        base = draw_title_card(t, is_intro=True)
        if t > 2.9:
            alpha = (t - 2.9) / 0.6
            c1_frame = render_ipad_frame(loaded_cards[0], zoom=1.0)
            base = Image.blend(base, c1_frame, alpha)
    elif t < 7.8:
        rel_t = t - 3.5
        prog = rel_t / 4.3
        zoom = 1.0 + 0.14 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.44 + 0.04 * prog
        curr = render_ipad_frame(loaded_cards[0], zoom=zoom, focus_y=focus_y)
        if rel_t > 3.7:
            alpha = (rel_t - 3.7) / 0.6
            c2_frame = render_ipad_frame(loaded_cards[1], zoom=1.0)
            curr = Image.blend(curr, c2_frame, alpha)
        base = curr
    elif t < 12.0:
        rel_t = t - 7.8
        prog = rel_t / 4.2
        zoom = 1.0 + 0.16 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.40 + 0.04 * prog
        curr = render_ipad_frame(loaded_cards[1], zoom=zoom, focus_y=focus_y)
        if rel_t > 3.6:
            alpha = (rel_t - 3.6) / 0.6
            c3_frame = render_ipad_frame(loaded_cards[2], zoom=1.0)
            curr = Image.blend(curr, c3_frame, alpha)
        base = curr
    elif t < 16.5:
        rel_t = t - 12.0
        prog = rel_t / 4.5
        zoom = 1.0 + 0.14 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.43 + 0.04 * prog
        curr = render_ipad_frame(loaded_cards[2], zoom=zoom, focus_y=focus_y)
        if rel_t > 3.9:
            alpha = (rel_t - 3.9) / 0.6
            c4_frame = render_ipad_frame(loaded_cards[3], zoom=1.0)
            curr = Image.blend(curr, c4_frame, alpha)
        base = curr
    elif t < 20.5:
        rel_t = t - 16.5
        prog = rel_t / 4.0
        zoom = 1.02 + 0.14 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.42 + 0.04 * prog
        curr = render_ipad_frame(loaded_cards[3], zoom=zoom, focus_y=focus_y)
        if rel_t > 3.4:
            alpha = (rel_t - 3.4) / 0.6
            c5_frame = render_ipad_frame(loaded_cards[4], zoom=1.0)
            curr = Image.blend(curr, c5_frame, alpha)
        base = curr
    elif t < 22.5:
        rel_t = t - 20.5
        prog = rel_t / 2.0
        zoom = 1.0 + 0.10 * math.sin(prog * (math.pi / 2.0))
        focus_y = 0.48
        curr = render_ipad_frame(loaded_cards[4], zoom=zoom, focus_y=focus_y)
        if rel_t > 1.5:
            alpha = (rel_t - 1.5) / 0.5
            outro = draw_title_card(0.0, is_intro=False)
            curr = Image.blend(curr, outro, alpha)
        base = curr
    else:
        rel_t = t - 22.5
        base = draw_title_card(rel_t, is_intro=False)
        
    frame_path = os.path.join(TEMP_FRAMES_DIR, f"frame_{frame_idx:05d}.jpg")
    base.convert("RGB").save(frame_path, "JPEG", quality=94)
    
    if frame_idx % 90 == 0:
        print(f"Rendered iPad frame {frame_idx}/{TOTAL_FRAMES} ({(frame_idx/TOTAL_FRAMES)*100:.1f}%)")

print("All frames rendered! Encoding iPad promo video...")

video_ipad_16x9 = os.path.join(OUTPUT_DIR, "Runalyst_Promo_iPad_16x9.mp4")

cmd = [
    "ffmpeg", "-y",
    "-framerate", "30",
    "-i", os.path.join(TEMP_FRAMES_DIR, "frame_%05d.jpg"),
    "-an",
    "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
    "-t", str(TOTAL_DURATION),
    video_ipad_16x9
]
subprocess.run(cmd, check=True)
print(f"Created landscape iPad promo video: {video_ipad_16x9}")

shutil.rmtree(TEMP_FRAMES_DIR)
print("Complete!")
