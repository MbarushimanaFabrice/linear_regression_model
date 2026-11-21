"""Model loading, single-row prediction and retraining logic.

This module deliberately has no FastAPI imports so it can be tested on its own.
`prediction.py` (the FastAPI app) calls the functions defined here.
"""
from __future__ import annotations

import threading
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.linear_model import SGDRegressor
from sklearn.metrics import mean_squared_error

BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "best_model.pkl"          # saved by the notebook (preprocessing + model)
TRAIN_CSV = BASE_DIR / "facility_training.csv"    # cleaned training data saved by the notebook

CAT_COLS = ["country", "facility_level", "publicprivate", "ruralurban"]
BIN_COLS = ["has_autosyringe", "has_dispsyringe", "has_fridge", "has_gloves", "has_sharps", "has_vaccarrier"]
NUM_COLS = BIN_COLS + ["readiness_count"]
FEATURES = CAT_COLS + NUM_COLS                    # the 11 columns the saved pipeline expects
TARGET = "absence_rate"
RAW_COLUMNS = CAT_COLS + BIN_COLS + [TARGET]      # the 11 columns a /retrain CSV must contain

SGD_EPOCHS_ON_NEW_DATA = 20                       # passes over the new rows when the model is an SGDRegressor

_lock = threading.Lock()
_model = None


def add_readiness(frame: pd.DataFrame) -> pd.DataFrame:
    """Same feature engineering as the notebook: how many of the 6 basic items are available (0-6)."""
    frame = frame.copy()
    frame["readiness_count"] = frame[BIN_COLS].sum(axis=1)
    return frame


def load_model():
    """Load the saved pipeline from disk (called once at start-up)."""
    global _model
    _model = joblib.load(MODEL_PATH)
    return _model


def get_model():
    return _model if _model is not None else load_model()


def model_name() -> str:
    return type(get_model().steps[-1][1]).__name__


def predict_one(record: dict) -> float:
    """Predict the absence rate for ONE facility given the 10 raw inputs. Result is clipped to [0, 1]."""
    frame = add_readiness(pd.DataFrame([record])[CAT_COLS + BIN_COLS])
    prediction = float(get_model().predict(frame[FEATURES])[0])
    return float(np.clip(prediction, 0.0, 1.0))


def prepare_upload(raw: pd.DataFrame) -> pd.DataFrame:
    """Validate and clean an uploaded CSV. Raises ValueError with a readable message."""
    missing = [c for c in RAW_COLUMNS if c not in raw.columns]
    if missing:
        raise ValueError(f"The CSV is missing required column(s): {missing}. Required columns: {RAW_COLUMNS}")

    df = raw[RAW_COLUMNS].copy().replace(r"^\s*$", np.nan, regex=True)
    for col in BIN_COLS + [TARGET]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    received = len(df)
    df = df.dropna().reset_index(drop=True)
    if df.empty:
        raise ValueError("No usable rows: every row has a missing or non-numeric value.")

    if not df[BIN_COLS].isin([0, 1]).all().all():
        raise ValueError(f"Columns {BIN_COLS} may only contain 0 or 1.")
    if not df[TARGET].between(0, 1).all():
        raise ValueError(f"'{TARGET}' must be between 0 and 1.")

    for col in CAT_COLS:
        df[col] = df[col].astype(str).str.strip()
    df[BIN_COLS] = df[BIN_COLS].astype(int)
    df.attrs["rows_received"] = received
    return df


def retrain_model(raw: pd.DataFrame) -> dict:
    """Update the deployed model with the uploaded rows and start using it immediately.

    * SGDRegressor  -> continue training the saved model on the new rows with partial_fit.
    * any other model -> refit a fresh copy of the pipeline on the original data + the new rows.
    """
    global _model
    new = prepare_upload(raw)
    received = new.attrs["rows_received"]
    new_feat = add_readiness(new)

    with _lock:
        model = get_model()
        y_new = new[TARGET].values
        mse_before = float(mean_squared_error(y_new, model.predict(new_feat[FEATURES])))
        estimator = model.steps[-1][1]

        if isinstance(estimator, SGDRegressor):
            strategy = "partial_fit: continued training the saved SGDRegressor on the new rows"
            X_new = model.named_steps["pre"].transform(new_feat[FEATURES])
            for _ in range(SGD_EPOCHS_ON_NEW_DATA):
                estimator.partial_fit(X_new, y_new)
            updated = model
            base = pd.read_csv(TRAIN_CSV)
            combined = pd.concat([base[RAW_COLUMNS], new[RAW_COLUMNS]], ignore_index=True)
        else:
            strategy = f"refit: retrained {type(estimator).__name__} pipeline on original data + new rows"
            base = pd.read_csv(TRAIN_CSV)
            combined = pd.concat([base[RAW_COLUMNS], new[RAW_COLUMNS]], ignore_index=True)
            comb_feat = add_readiness(combined)
            updated = clone(model).fit(comb_feat[FEATURES], combined[TARGET].values)

        mse_after = float(mean_squared_error(y_new, updated.predict(new_feat[FEATURES])))
        _model = updated                      # /predict uses the new model immediately (no redeploy)

        saved = True
        try:                                  # persist (on Render's free plan these files are lost on restart)
            joblib.dump(updated, MODEL_PATH, compress=3)
            combined.to_csv(TRAIN_CSV, index=False)
        except OSError:
            saved = False

    return {
        "message": "Model retrained and now in use by /predict.",
        "model": type(updated.steps[-1][1]).__name__,
        "strategy": strategy,
        "rows_received": int(received),
        "rows_used": int(len(new)),
        "rows_dropped_incomplete": int(received - len(new)),
        "training_rows_total": int(len(combined)),
        "mse_on_new_rows_before": round(mse_before, 5),
        "mse_on_new_rows_after": round(mse_after, 5),
        "saved_to_disk": saved,
    }
