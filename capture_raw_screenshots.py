import os
import subprocess
import time

def get_booted_device_id(device_type="iPhone"):
    try:
        out = subprocess.check_output(["xcrun", "simctl", "list", "devices", "booted"], text=True)
        for line in out.splitlines():
            if device_type in line and "(" in line and ")" in line:
                parts = line.split("(")
                for p in parts[1:]:
                    if ")" in p:
                        cand = p.split(")")[0].strip()
                        if len(cand) == 36 and "-" in cand:
                            return cand
    except Exception:
        pass
    return "9B8ADDDA-B76A-4A28-BCA3-239FB5B25BC6" if device_type == "iPhone" else "F37FD237-165F-4849-8A85-2E4817486EC5"

IPHONE_ID = get_booted_device_id("iPhone")
IPAD_ID = get_booted_device_id("iPad")
BUNDLE_ID = "com.runalyzer.Runalyzer"

IPHONE_DIR = "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw"
IPAD_DIR = "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPad_Raw"

os.makedirs(IPHONE_DIR, exist_ok=True)
os.makedirs(IPAD_DIR, exist_ok=True)

SCREENS = [
    ("screen_dashboard.png", "DASHBOARD"),
    ("screen_run_detail.png", "RUN_DETAIL"),
    ("screen_drill_readout.png", "DRILL_READOUT"),
    ("screen_biomechanics.png", "BIOMECHANICS"),
    ("screen_drills.png", "WORKOUTS"),
    ("screen_progression.png", "PROGRESSION"),
    ("screen_settings.png", "SETTINGS"),
]

def capture_device(device_id, out_dir, label):
    print(f"\n==========================================")
    print(f"Capturing Screenshots for {label} ({device_id})")
    print(f"==========================================")

    # Setup simulator defaults
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "hasCompletedOnboarding", "-bool", "true"])
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "useMetricSystem", "-bool", "true"])
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "dashboardTimeRange", "-string", "30 Days"])
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "minimumRunDistance", "-float", "1.0"])

    # Seed mock data once before capturing screens
    print("--> Seeding mock workout telemetry...")
    subprocess.run(["xcrun", "simctl", "terminate", device_id, BUNDLE_ID], stderr=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "RUNALYST_PREVIEW_SCREEN", "-string", "DASHBOARD"])
    env_seed = os.environ.copy()
    env_seed["SIMCTL_CHILD_RUNALYST_FORCE_SEED"] = "true"
    subprocess.run(["xcrun", "simctl", "launch", device_id, BUNDLE_ID], env=env_seed, capture_output=True)
    time.sleep(4.0)
    subprocess.run(["xcrun", "simctl", "terminate", device_id, BUNDLE_ID], stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    for filename, screen_key in SCREENS:
        out_path = os.path.join(out_dir, filename)
        print(f"--> Capturing {screen_key} -> {filename}...")

        subprocess.run(["xcrun", "simctl", "terminate", device_id, BUNDLE_ID], stderr=subprocess.DEVNULL)
        time.sleep(0.8)

        subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "RUNALYST_PREVIEW_SCREEN", "-string", screen_key])

        env = os.environ.copy()
        env["SIMCTL_CHILD_RUNALYST_PREVIEW_SCREEN"] = screen_key

        res = subprocess.run([
            "xcrun", "simctl", "launch", device_id, BUNDLE_ID
        ], env=env, capture_output=True, text=True)

        # Wait for views to render and transitions to settle
        time.sleep(3.5)

        subprocess.run([
            "xcrun", "simctl", "io", device_id, "screenshot", out_path
        ], check=True)

        if os.path.exists(out_path):
            size_kb = os.path.getsize(out_path) // 1024
            print(f"    ✓ Saved {out_path} ({size_kb} KB)")
        else:
            print(f"    ✗ Failed to save {out_path}")

        subprocess.run(["xcrun", "simctl", "terminate", device_id, BUNDLE_ID], stderr=subprocess.DEVNULL)
        time.sleep(0.3)

if __name__ == "__main__":
    import sys
    target = sys.argv[1] if len(sys.argv) > 1 else "all"

    if target in ("all", "iphone"):
        capture_device(IPHONE_ID, IPHONE_DIR, "iPhone 17 Pro")
    if target in ("all", "ipad"):
        capture_device(IPAD_ID, IPAD_DIR, "iPad Pro 13-inch (M5)")

    print("\nAll raw screenshots successfully captured!")
