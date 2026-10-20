import csv
import random

try:
    import pandas as pd
    import numpy as np
    HAS_PANDAS = True
except ImportError:
    HAS_PANDAS = False

def generate_smooth_seed_data(num_samples=15000):
    runs = []
    
    for _ in range(num_samples):
        # Assign Runner Stage (0 = Beginner, 1 = Intermediate, 2 = Advanced, 3 = Elite)
        runner_stage = random.choices([0, 1, 2, 3], weights=[0.40, 0.35, 0.20, 0.05])[0]
        
        # Base Biomechanics by Stage
        if runner_stage == 0:
            base_cad = 148
            base_osc = 11.5
            cv_multiplier = 1.2
        elif runner_stage == 1:
            base_cad = 158
            base_osc = 10.0
            cv_multiplier = 1.0
        elif runner_stage == 2:
            base_cad = 168
            base_osc = 8.5
            cv_multiplier = 0.85
        else: # Elite
            base_cad = 180
            base_osc = 6.5
            cv_multiplier = 0.70
            
        cadence = float(max(130.0, min(195.0, random.gauss(base_cad, 5))))
        osc = float(max(5.0, min(15.0, random.gauss(base_osc, 1.0))))

        # Pick a base archetype smoothly
        archetype = random.choices(
            [
                "Recovery", "Easy", "Steady", "Progression", "Tempo",
                "Fartlek", "Intervals", "Progressive Intervals", "Rhythm Intervals",
                "Cadence Pyramids", "Hill Repeats", "Long Run", "Urban Traffic",
                "Tempo Surges", "Strides"
            ],
            weights=[0.08, 0.12, 0.12, 0.08, 0.08, 0.08, 0.08, 0.05, 0.05, 0.06, 0.06, 0.07, 0.06, 0.04, 0.05]
        )[0]
        
        if archetype == "Recovery":
            pace_delta = random.gauss(60, 15)          # Slower than baseline
            hr_delta = random.gauss(-25, 5)            # Much lower HR
            percent_zone4 = random.betavariate(1, 20)  
            cv = random.gauss(0.015, 0.004)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(-5, 2)
            duration_mins = random.gauss(30, 5)
            cadence_cv = random.gauss(0.01, 0.002)
            hr_cv = random.gauss(0.015, 0.004)
            workout_class = "Recovery Run"
            
        elif archetype == "Easy":
            pace_delta = random.gauss(45, 25)          # Slower than baseline (Zone 2 / aerobic easy)
            hr_delta = random.gauss(-12, 8)
            percent_zone4 = random.betavariate(1, 10)   
            cv = random.gauss(0.025, 0.010)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(-3, 3)
            duration_mins = random.gauss(42, 12)
            cadence_cv = max(0.008, min(0.045, random.gauss(0.020, 0.008)))
            hr_cv = max(0.010, min(0.075, random.gauss(0.038, 0.014)))
            workout_class = "Easy Run"
            
        elif archetype == "Steady":
            # 65% normal aerobic steady, 20% high cardiac drift / warm weather steady, 15% 'fly and die' pacing fade
            steady_mode = random.choices(["aerobic", "cardiac_drift", "fade"], weights=[0.65, 0.20, 0.15])[0]
            if steady_mode == "cardiac_drift":
                pace_delta = random.gauss(0, 12)           # Baseline pace maintained
                hr_delta = random.gauss(18, 5)             # Elevated HR from heat / drift
                percent_zone4 = random.betavariate(6, 4)   # Substantial Zone 4 (0.40 - 0.85)
                cadence_delta = random.gauss(1, 2)
                cv = random.gauss(0.045, 0.012)            # Normal or slight GPS variation
                pace_slope = random.gauss(-0.02, 0.04)
                duration_mins = random.gauss(40, 12)
                cadence_cv = max(0.005, min(0.022, random.gauss(0.013, 0.003)))  # Rock-solid cadence
                hr_cv = random.gauss(0.055, 0.008)
            elif steady_mode == "fade":
                pace_delta = random.gauss(0, 15)
                hr_delta = random.gauss(5, 5)
                percent_zone4 = random.betavariate(2, 8)
                cadence_delta = random.gauss(0, 2)
                cv = random.gauss(0.09, 0.015)
                pace_slope = random.gauss(0.375, 0.075)
                duration_mins = random.gauss(45, 15)
                cadence_cv = max(0.005, min(0.024, random.gauss(0.015, 0.003)))
                hr_cv = random.gauss(0.045, 0.008)
            else:
                pace_delta = random.gauss(0, 12)           # Anchor: baseline pace
                hr_delta = random.gauss(0, 5)              # Anchor: baseline HR
                percent_zone4 = random.betavariate(2, 8)
                cadence_delta = random.gauss(0, 2)
                cv = random.gauss(0.038, 0.008)
                pace_slope = random.gauss(0.0, 0.038)
                duration_mins = random.gauss(45, 15)
                cadence_cv = max(0.005, min(0.022, random.gauss(0.013, 0.003)))
                hr_cv = random.gauss(0.028, 0.006)
            workout_class = "Steady Effort"
            
        elif archetype == "Progression":
            pace_delta = random.gauss(-30, 15)         # Faster overall
            hr_delta = random.gauss(15, 5)
            percent_zone4 = random.betavariate(4, 4)
            cv = random.gauss(0.052, 0.008)
            pace_slope = random.gauss(-0.25, 0.05)      # Narrowed negative slope
            cadence_delta = random.gauss(5, 2)
            duration_mins = random.gauss(50, 15)
            cadence_cv = max(0.008, min(0.024, random.gauss(0.016, 0.004)))
            hr_cv = random.gauss(0.065, 0.010)
            workout_class = "Progression Run"
            
        elif archetype == "Tempo":
            pace_delta = random.gauss(-55, 12)         # Strictly faster pace (threshold)
            hr_delta = random.gauss(25, 4)
            percent_zone4 = random.betavariate(8, 2)   
            cv = random.gauss(0.05, 0.010)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(10, 2)
            duration_mins = random.gauss(45, 10)       # Tempo runs are sustained, 30-60 min
            cadence_cv = max(0.008, min(0.024, random.gauss(0.014, 0.003)))
            hr_cv = random.gauss(0.040, 0.008)
            workout_class = "Tempo Run"
            
        elif archetype == "Fartlek":
            pace_delta = random.gauss(-20, 15)         # Surges make average pace moderately faster
            hr_delta = random.gauss(18, 5)
            percent_zone4 = random.betavariate(4, 6)   
            cv = random.gauss(0.105, 0.015)            # High variance
            pace_slope = random.gauss(0.0, 0.038)       
            cadence_delta = random.gauss(6, 3)
            duration_mins = random.gauss(35, 10)
            cadence_cv = max(0.030, min(0.080, random.gauss(0.042, 0.008)))  # Clear cadence variation
            hr_cv = random.gauss(0.075, 0.012)
            workout_class = "Fartlek"
            
        elif archetype == "Intervals":
            pace_delta = random.gauss(-90, 15)         # Much faster
            hr_delta = random.gauss(35, 4)
            percent_zone4 = random.betavariate(10, 1)
            cv = random.gauss(0.135, 0.015)              # Very high variance
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(15, 3)
            duration_mins = random.gauss(25, 8)
            cadence_cv = max(0.035, min(0.090, random.gauss(0.048, 0.010)))
            hr_cv = random.gauss(0.115, 0.018)
            workout_class = "Intervals"
            
        elif archetype == "Progressive Intervals":
            pace_delta = random.gauss(-70, 15)         # Faster overall
            hr_delta = random.gauss(30, 5)
            percent_zone4 = random.betavariate(8, 2)
            cv = random.gauss(0.13, 0.015)             # High variance
            pace_slope = random.gauss(-0.30, 0.06)     # Negative slope (progressing through intervals)
            cadence_delta = random.gauss(14, 3)
            duration_mins = random.gauss(30, 8)
            cadence_cv = max(0.035, min(0.090, random.gauss(0.048, 0.010)))
            hr_cv = random.gauss(0.115, 0.018)
            workout_class = "Intervals"
            
        elif archetype == "Rhythm Intervals":
            pace_delta = random.gauss(-75, 10)
            hr_delta = random.gauss(30, 5)             # High sustained HR due to active recovery
            percent_zone4 = random.betavariate(8, 2)   # Lots of zone 4
            cv = random.gauss(0.125, 0.015)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(12, 3)
            duration_mins = random.gauss(15, 4)        # Short drill (10-20 min)
            cadence_cv = max(0.035, min(0.090, random.gauss(0.048, 0.010)))
            hr_cv = random.gauss(0.110, 0.015)
            workout_class = "Intervals"
            
        elif archetype == "Cadence Pyramids":
            pace_delta = random.gauss(-40, 10)
            hr_delta = random.gauss(20, 5)
            percent_zone4 = random.betavariate(5, 5)
            cv = random.gauss(0.08, 0.01)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(15, 2)        # Extremely high cadence delta
            duration_mins = random.gauss(18, 4)        # Short drill
            cadence_cv = max(0.035, min(0.090, random.gauss(0.052, 0.010)))
            hr_cv = random.gauss(0.095, 0.015)
            workout_class = "Pyramids"

        elif archetype == "Hill Repeats":
            pace_delta = random.gauss(-10, 12)
            hr_delta = random.gauss(26, 4)
            percent_zone4 = random.betavariate(7, 3)   # High zone 4/5
            cv = random.gauss(0.085, 0.012)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(4, 3)
            duration_mins = random.gauss(22, 6)
            osc = float(max(9.5, min(14.0, random.gauss(base_osc + 2.0, 0.8)))) # High vertical oscillation
            cadence_cv = max(0.020, min(0.060, random.gauss(0.035, 0.008)))
            hr_cv = random.gauss(0.120, 0.018)
            workout_class = "Hill Repeats"

        elif archetype == "Long Run":
            pace_delta = random.gauss(15, 12)          # Steady aerobic
            hr_delta = random.gauss(-5, 6)
            percent_zone4 = random.betavariate(2, 8)   # Low zone 4
            cv = random.gauss(0.040, 0.010)
            pace_slope = random.gauss(0.02, 0.03)      # Flat
            cadence_delta = random.gauss(-1, 2)
            duration_mins = random.gauss(105, 15)      # >= 90 mins
            cadence_cv = max(0.008, min(0.022, random.gauss(0.014, 0.003)))
            hr_cv = random.gauss(0.035, 0.008)
            workout_class = "Long Run"

        elif archetype == "Urban Traffic":
            pace_delta = random.gauss(10, 15)          # Apparent average pace is slow from stops
            hr_delta = random.gauss(0, 8)              # Aerobic HR
            percent_zone4 = random.betavariate(1, 9)   # Low zone 4
            cv = random.gauss(0.16, 0.03)              # High pace variance from dead stops
            pace_slope = random.gauss(0.0, 0.05)
            cadence_delta = random.gauss(-5, 3)
            duration_mins = random.gauss(35, 10)
            cadence_cv = max(0.045, min(0.120, random.gauss(0.065, 0.015)))
            hr_cv = random.gauss(0.060, 0.012)
            workout_class = "Urban Traffic"
            
        elif archetype == "Tempo Surges":
            pace_delta = random.gauss(-50, 10)
            hr_delta = random.gauss(25, 5)
            percent_zone4 = random.betavariate(6, 4)
            cv = random.gauss(0.070, 0.008)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(8, 2)
            duration_mins = random.gauss(20, 5)        # Short-medium drill
            cadence_cv = max(0.018, min(0.030, random.gauss(0.024, 0.003)))
            hr_cv = random.gauss(0.070, 0.012)
            workout_class = "Tempo Run"
            
        elif archetype == "Strides":
            pace_delta = random.gauss(-10, 10)         # Average pace is slow since it's mostly easy run + short bursts
            hr_delta = random.gauss(5, 5)
            percent_zone4 = random.betavariate(2, 8)
            cv = random.gauss(0.14, 0.02)              # Extremely high variance due to short bursts
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(2, 2)
            duration_mins = random.gauss(12, 3)        # Very short drill
            cadence_cv = max(0.040, min(0.100, random.gauss(0.062, 0.012)))
            hr_cv = random.gauss(0.085, 0.015)
            workout_class = "Intervals"

        # Clamp values to realistic human bounds for deltas
        pace_delta = float(max(-300.0, min(300.0, pace_delta)))
        hr_delta = float(max(-60.0, min(80.0, hr_delta)))
        cadence_delta = float(max(-30.0, min(40.0, cadence_delta)))
        percent_zone4 = float(max(0.0, min(1.0, percent_zone4)))
        # Apply CV multiplier based on runner experience
        cv = float(max(0.0, min(0.35, cv * cv_multiplier)))

        duration_mins = float(max(5.0, min(180.0, duration_mins)))
        cadence_cv = float(max(0.0, min(0.20, cadence_cv)))
        hr_cv = float(max(0.005, min(0.25, hr_cv)))

        runs.append({
            "paceDelta": pace_delta,
            "hrDelta": hr_delta,
            "percentZone4": percent_zone4,
            "cadenceDelta": cadence_delta,
            "verticalOscillation": osc,
            "cv": cv,
            "paceSlope": pace_slope,
            "runnerStage": runner_stage,
            "durationMinutes": duration_mins,
            "cadenceCV": cadence_cv,
            "hrCV": hr_cv,
            "targetClass": workout_class
        })

    return runs

def export_v6_dataset():
    train_runs = generate_smooth_seed_data(35000)
    test_runs = generate_smooth_seed_data(5000)
    
    if HAS_PANDAS:
        df_train = pd.DataFrame(train_runs)
        df_test = pd.DataFrame(test_runs)
        df_train.to_csv("CoreML_Training_Data_v6.csv", index=False)
        df_test.to_csv("CoreML_Testing_Data_v6.csv", index=False)
    else:
        fieldnames = ["paceDelta", "hrDelta", "percentZone4", "cadenceDelta", "verticalOscillation", "cv", "paceSlope", "runnerStage", "durationMinutes", "cadenceCV", "hrCV", "targetClass"]
        for runs, filename in [(train_runs, "CoreML_Training_Data_v6.csv"), (test_runs, "CoreML_Testing_Data_v6.csv")]:
            with open(filename, "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(runs)
            
    print("Generated v6 datasets with hrCV for all 11 run classifications.")

if __name__ == "__main__":
    export_v6_dataset()
