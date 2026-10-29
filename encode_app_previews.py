import os
import subprocess
import json
import shutil

RAW_IPHONE = "/tmp/raw_iphone_tour.mp4"
RAW_IPAD = "/tmp/raw_ipad_tour.mp4"

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))

PREVIEWS_DIR = os.path.join(REPO_ROOT, "Media/AppStorePreviews")
WEBSITE_VIDEO = os.path.join(REPO_ROOT, "website/assets/videos/app_tour_web.mp4")

IPHONE_START = "00:00:03.900"
IPAD_START = "00:00:03.800"
DURATION = "25.000"

TARGETS = [
    # iPhone Portrait & Landscape
    {
        "name": "Runalyst_AppPreview_886x1920.mp4",
        "raw": RAW_IPHONE,
        "start": IPHONE_START,
        "vf": "scale=886:1920,setsar=1",
        "width": 886,
        "height": 1920,
    },
    {
        "name": "Runalyst_AppPreview_1920x886.mp4",
        "raw": RAW_IPHONE,
        "start": IPHONE_START,
        "vf": "scale=-2:886,pad=1920:886:(ow-iw)/2:0:black,setsar=1",
        "width": 1920,
        "height": 886,
    },
    {
        "name": "Runalyst_AppPreview_1284x2778.mp4",
        "raw": RAW_IPHONE,
        "start": IPHONE_START,
        "vf": "scale=1284:2778,setsar=1",
        "width": 1284,
        "height": 2778,
    },
    {
        "name": "Runalyst_AppPreview_2778x1284.mp4",
        "raw": RAW_IPHONE,
        "start": IPHONE_START,
        "vf": "scale=-2:1284,pad=2778:1284:(ow-iw)/2:0:black,setsar=1",
        "width": 2778,
        "height": 1284,
    },
    {
        "name": "Runalyst_AppPreview_1242x2688.mp4",
        "raw": RAW_IPHONE,
        "start": IPHONE_START,
        "vf": "scale=1242:2688,setsar=1",
        "width": 1242,
        "height": 2688,
    },
    {
        "name": "Runalyst_AppPreview_2688x1242.mp4",
        "raw": RAW_IPHONE,
        "start": IPHONE_START,
        "vf": "scale=-2:1242,pad=2688:1242:(ow-iw)/2:0:black,setsar=1",
        "width": 2688,
        "height": 1242,
    },
    # iPad Accepted & Device Resolutions (4:3 aspect ratio)
    {
        "name": "Runalyst_AppPreview_iPad_1200x1600.mp4",
        "raw": RAW_IPAD,
        "start": IPAD_START,
        "vf": "scale=1200:1600,setsar=1",
        "width": 1200,
        "height": 1600,
    },
    {
        "name": "Runalyst_AppPreview_iPad_1600x1200.mp4",
        "raw": RAW_IPAD,
        "start": IPAD_START,
        "vf": "scale=-2:1200,pad=1600:1200:(ow-iw)/2:0:black,setsar=1",
        "width": 1600,
        "height": 1200,
    },
    {
        "name": "Runalyst_AppPreview_iPad_2732x2048.mp4",
        "raw": RAW_IPAD,
        "start": IPAD_START,
        "vf": "scale=-2:2048,pad=2732:2048:(ow-iw)/2:0:black,setsar=1",
        "width": 2732,
        "height": 2048,
    },
    {
        "name": "Runalyst_AppPreview_iPad_2752x2064.mp4",
        "raw": RAW_IPAD,
        "start": IPAD_START,
        "vf": "scale=-2:2064,pad=2752:2064:(ow-iw)/2:0:black,setsar=1",
        "width": 2752,
        "height": 2064,
    },
]

def encode_video(item):
    out_path = os.path.join(PREVIEWS_DIR, item["name"])
    print(f"\n[ENCODING] {item['name']} ({item['width']}x{item['height']})...")

    cmd = [
        "ffmpeg", "-y",
        "-ss", item["start"],
        "-t", DURATION,
        "-i", item["raw"],
        "-f", "lavfi",
        "-i", "anullsrc=r=44100:cl=stereo",
        "-vf", item["vf"],
        "-c:v", "libx264",
        "-profile:v", "high",
        "-level", "4.2",
        "-pix_fmt", "yuv420p",
        "-r", "30",
        "-fps_mode", "cfr",
        "-c:a", "aac",
        "-b:a", "128k",
        "-ar", "44100",
        "-ac", "2",
        "-movflags", "+faststart",
        "-shortest",
        out_path
    ]

    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        print(f"Error encoding {item['name']}: {res.stderr[-500:]}")
        raise RuntimeError(f"FFmpeg failed for {item['name']}")

    # Verify with ffprobe
    probe_cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration,size",
        "-show_entries", "stream=width,height,codec_name,profile,level,r_frame_rate",
        "-of", "json",
        out_path
    ]
    probe_res = subprocess.run(probe_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    data = json.loads(probe_res.stdout)

    v_stream = next(s for s in data["streams"] if s["codec_name"] == "h264")
    a_stream = next(s for s in data["streams"] if s["codec_name"] == "aac")
    duration = float(data["format"]["duration"])
    size_mb = float(data["format"]["size"]) / (1024 * 1024)

    print(f"  ✓ {item['name']}: {v_stream['width']}x{v_stream['height']} @ {v_stream['r_frame_rate']}fps, "
          f"Profile={v_stream['profile']} L{v_stream['level']}, Audio={a_stream['codec_name']}, "
          f"Duration={duration:.2f}s, Size={size_mb:.2f}MB")

    assert v_stream["width"] == item["width"], f"Width mismatch: {v_stream['width']} != {item['width']}"
    assert v_stream["height"] == item["height"], f"Height mismatch: {v_stream['height']} != {item['height']}"
    assert 15.0 <= duration <= 30.0, f"Duration out of range: {duration}"

def main():
    os.makedirs(PREVIEWS_DIR, exist_ok=True)

    # 1. Prune outdated or non-spec files
    prune_files = [
        "Runalyst_AppPreview_1290x2796.mp4",
        "Runalyst_AppPreview_iPad_2048x2732.mp4",
        "Runalyst_AppPreview_iPad_2064x2752.mp4"
    ]
    for pf in prune_files:
        p_path = os.path.join(PREVIEWS_DIR, pf)
        if os.path.exists(p_path):
            os.remove(p_path)
            print(f"Removed non-spec/outdated {pf}")

    # 2. Encode all targets
    for item in TARGETS:
        encode_video(item)

    # 3. Update website video
    src_web = os.path.join(PREVIEWS_DIR, "Runalyst_AppPreview_886x1920.mp4")
    if os.path.exists(src_web):
        os.makedirs(os.path.dirname(WEBSITE_VIDEO), exist_ok=True)
        shutil.copyfile(src_web, WEBSITE_VIDEO)
        print(f"\n✓ Updated website preview video: {WEBSITE_VIDEO}")

    print("\nAll App Preview videos successfully encoded and validated!")

if __name__ == "__main__":
    main()
