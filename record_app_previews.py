import os
import subprocess
import time
import signal

IPHONE_ID = "A59BB117-5AD3-4BEF-959A-95B526E29F06"
IPAD_ID = "F37FD237-165F-4849-8A85-2E4817486EC5"
BUNDLE_ID = "com.runalyzer.Runalyzer"
REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
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
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

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
    if target in ("all", "iphone"):
        record_tour(IPHONE_ID, RAW_IPHONE, duration_sec=32.0)
    if target in ("all", "ipad"):
        record_tour(IPAD_ID, RAW_IPAD, duration_sec=32.0)

