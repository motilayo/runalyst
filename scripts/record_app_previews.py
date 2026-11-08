import os
import subprocess
import time
import signal

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
    return "9B8ADDDA-B76A-4A28-BCA3-239FB5B25BC6" if device_type == "iPhone" else "AC8423AB-A1C1-44E2-BA23-89FDC58521C8"

IPHONE_ID = get_booted_device_id("iPhone")
IPAD_ID = get_booted_device_id("iPad")
BUNDLE_ID = "com.runalyzer.Runalyzer"
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PREVIEWS_DIR = os.path.join(REPO_ROOT, "Media/AppStorePreviews")
os.makedirs(PREVIEWS_DIR, exist_ok=True)

RAW_IPHONE = "/tmp/raw_iphone_tour.mp4"
RAW_IPAD = "/tmp/raw_ipad_tour.mp4"

def setup_simulator(device_id):
    print(f"Setting up {device_id}...")
    subprocess.run(["xcrun", "simctl", "terminate", device_id, BUNDLE_ID], stderr=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "hasCompletedOnboarding", "-bool", "true"])
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "useMetricSystem", "-bool", "true"])
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "dashboardTimeRange", "-string", "30 Days"])
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "minimumRunDistance", "-float", "1.0"])
    subprocess.run(["xcrun", "simctl", "spawn", device_id, "defaults", "write", BUNDLE_ID, "RUNALYST_PREVIEW_SCREEN", "-string", "AUTO_TOUR"])

def record_tour(device_id, output_raw, duration_sec=32.0):
    if os.path.exists(output_raw):
        try:
            os.remove(output_raw)
        except:
            pass

    setup_simulator(device_id)

    print(f"Starting recordVideo on {device_id} -> {output_raw}...")
    rec_proc = subprocess.Popen([
        "xcrun", "simctl", "io", device_id, "recordVideo",
        "--codec=h264",
        "--mask=black",
        "--force",
        output_raw
    ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    time.sleep(1.5)

    print(f"Launching app with AUTO_TOUR on {device_id}...")
    env = os.environ.copy()
    env["SIMCTL_CHILD_RUNALYST_PREVIEW_SCREEN"] = "AUTO_TOUR"
    env["SIMCTL_CHILD_RUNALYST_FORCE_SEED"] = "true"
    res = subprocess.run([
        "xcrun", "simctl", "launch", device_id, BUNDLE_ID
    ], env=env, capture_output=True, text=True)
    print(f"Launch result: {res.stdout.strip()}")

    print(f"Recording for {duration_sec}s...")
    time.sleep(duration_sec)

    print("Stopping recording...")
    rec_proc.send_signal(signal.SIGINT)
    try:
        rec_proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        rec_proc.kill()

    subprocess.run(["xcrun", "simctl", "terminate", device_id, BUNDLE_ID], stderr=subprocess.DEVNULL)
    print(f"Saved raw recording: {output_raw} ({os.path.getsize(output_raw)} bytes)")

if __name__ == "__main__":
    import sys
    target = sys.argv[1] if len(sys.argv) > 1 else "all"
    iphone_id = get_booted_device_id("iPhone")
    ipad_id = get_booted_device_id("iPad")
    if target in ("all", "iphone"):
        record_tour(iphone_id, RAW_IPHONE, duration_sec=32.0)
    if target in ("all", "ipad"):
        record_tour(ipad_id, RAW_IPAD, duration_sec=32.0)

