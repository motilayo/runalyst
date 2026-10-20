import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
import coremltools as ct

def train_and_export():
    # Load data
    print("Loading data...")
    train_df = pd.read_csv("CoreML_Training_Data_v6.csv")
    test_df = pd.read_csv("CoreML_Testing_Data_v6.csv")

    features = [
        "paceDelta", "hrDelta", "percentZone4", "cadenceDelta", 
        "verticalOscillation", "cv", "paceSlope", "runnerStage",
        "durationMinutes", "cadenceCV", "hrCV"
    ]
    target = "targetClass"

    X_train = train_df[features]
    y_train = train_df[target]
    X_test = test_df[features]
    y_test = test_df[target]

    print("Training RandomForestClassifier...")
    model = RandomForestClassifier(n_estimators=150, max_depth=14, random_state=42)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    print(f"Model Accuracy on Test Set: {acc * 100:.2f}%")

    # Test suite covering crucial real-world cases across all 11 taxonomic classes:
    test_cases = [
        ("Progressive Intervals (should be Intervals, not Progression)", {
            "paceDelta": -50.0, "hrDelta": 25.0, "percentZone4": 0.55,
            "cadenceDelta": 12.0, "verticalOscillation": 9.0, "cv": 0.13,
            "paceSlope": -0.30, "runnerStage": 1, "durationMinutes": 30.0, "cadenceCV": 0.048,
            "hrCV": 0.115
        }, "Intervals"),
        ("Cadence Pyramids Ladder", {
            "paceDelta": -40.0, "hrDelta": 20.0, "percentZone4": 0.55,
            "cadenceDelta": 15.0, "verticalOscillation": 9.2, "cv": 0.08,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 18.0, "cadenceCV": 0.052,
            "hrCV": 0.095
        }, "Pyramids"),
        ("Hill Repeats", {
            "paceDelta": -10.0, "hrDelta": 26.0, "percentZone4": 0.65,
            "cadenceDelta": 4.0, "verticalOscillation": 11.5, "cv": 0.085,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 22.0, "cadenceCV": 0.035,
            "hrCV": 0.120
        }, "Hill Repeats"),
        ("Long Run (Duration >= 90 min)", {
            "paceDelta": 15.0, "hrDelta": -5.0, "percentZone4": 0.10,
            "cadenceDelta": -1.0, "verticalOscillation": 8.8, "cv": 0.04,
            "paceSlope": 0.02, "runnerStage": 1, "durationMinutes": 105.0, "cadenceCV": 0.014,
            "hrCV": 0.035
        }, "Long Run"),
        ("Urban Traffic (Chaotic Crosswalk Stops)", {
            "paceDelta": 10.0, "hrDelta": 0.0, "percentZone4": 0.05,
            "cadenceDelta": -5.0, "verticalOscillation": 8.6, "cv": 0.16,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 35.0, "cadenceCV": 0.065,
            "hrCV": 0.060
        }, "Urban Traffic"),
        ("Steady Effort with High HR / Cardiac Drift", {
            "paceDelta": 0.0, "hrDelta": 18.0, "percentZone4": 0.60,
            "cadenceDelta": 1.0, "verticalOscillation": 9.9, "cv": 0.045,
            "paceSlope": -0.02, "runnerStage": 1, "durationMinutes": 40.0, "cadenceCV": 0.013,
            "hrCV": 0.055
        }, "Steady Effort"),
        ("True Fartlek (Cadence & Pace Surges)", {
            "paceDelta": -20.0, "hrDelta": 18.0, "percentZone4": 0.45,
            "cadenceDelta": 6.0, "verticalOscillation": 9.5, "cv": 0.10,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 35.0, "cadenceCV": 0.042,
            "hrCV": 0.075
        }, "Fartlek"),
        ("Pure Tempo Run (Fast Paced Threshold)", {
            "paceDelta": -55.0, "hrDelta": 25.0, "percentZone4": 0.85,
            "cadenceDelta": 10.0, "verticalOscillation": 9.0, "cv": 0.05,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 45.0, "cadenceCV": 0.014,
            "hrCV": 0.040
        }, "Tempo Run"),
        ("Easy Recovery Run", {
            "paceDelta": 60.0, "hrDelta": -25.0, "percentZone4": 0.01,
            "cadenceDelta": -5.0, "verticalOscillation": 10.2, "cv": 0.015,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 30.0, "cadenceCV": 0.010,
            "hrCV": 0.015
        }, "Recovery Run"),
        ("Indoor Treadmill Zone 2 Easy Run (Oct 20 Incident)", {
            "paceDelta": 86.5, "hrDelta": -4.0, "percentZone4": 0.012,
            "cadenceDelta": -4.0, "verticalOscillation": 9.5, "cv": 0.035,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 42.0, "cadenceCV": 0.038,
            "hrCV": 0.058
        }, "Easy Run"),
    ]

    print("\n--- Validation Test Suite ---")
    all_passed = True
    for name, data, expected in test_cases:
        pred = model.predict(pd.DataFrame([data]))[0]
        match = "✓" if pred == expected else "✗"
        if pred != expected:
            all_passed = False
        print(f"[{match}] {name}: Predicted '{pred}' (Expected '{expected}')")

    if not all_passed:
        print("\nWarning: Some validation cases did not match expected class.")

    print("\nConverting to CoreML...")
    coreml_model = ct.converters.sklearn.convert(model, features, target)
    coreml_model.author = "Antigravity"
    coreml_model.short_description = "Runalyst AI Coach Classifier"
    
    # Save the model
    model_path = "RunalystClassifier.mlmodel"
    coreml_model.save(model_path)
    print(f"Successfully saved new model to {model_path}")

if __name__ == '__main__':
    train_and_export()
