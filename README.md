# Predicting Health-Facility Staff Absenteeism in Sub-Saharan Africa

**Mission:** improve access to healthcare in sub-Saharan Africa so fewer people lose their lives because they cannot reach working health services.
**Problem:** patients may travel to a clinic where the health workers are absent, so the visit is wasted.
This project predicts a facility's staff **absence rate** (0 to 1) from basic facility characteristics.
District managers and patient-access platforms can use it to flag facilities to verify before routing patients there.

## Dataset

World Bank **Service Delivery Indicators (SDI)** health-facility surveys: real, de-identified data from ten survey rounds across nine African countries (2010 to 2016); nine rounds have complete equipment data and are used.
**Source:** World Bank SDI-Health project, <https://worldbank.github.io/SDI-Health/> (harmonized data and code: <https://github.com/worldbank/SDI-Health>).
Exact files used: `SDI_AllCountries_Absenteeism.csv` (target) and `SDI_AllCountries_Facility.csv` (predictors), included in `summative/linear_regression/data/`.

* **Target:** `absence_rate`, the share of sampled staff absent at an unannounced visit (continuous, 0 to 1). One value per facility, so the provider-level file was reduced to one row per facility (5,201 facilities).
* **Inputs (10):** country-survey, facility level, public/private, rural/urban (categorical) and six 0/1 availability indicators (auto-disable syringes, disposable syringes, refrigerator, gloves, sharps container, vaccine carrier). A numeric `readiness_count` (0 to 6) is computed from them.
* **Rows used:** 3,942 facilities with complete inputs, 9 country-surveys. Cleaning decisions are documented in the notebook.

## Public API (Swagger UI)

**https://health-facility-absence-api.onrender.com/docs**  

Routes: `POST /predict`, `POST /retrain` (CSV upload), `GET /docs`. The free Render plan sleeps after 15 minutes, so the first request can take up to a minute.

## Video demo

[Watch the video demo on YouTube](https://youtu.be/MU7nNhV4sFM)

## Run the mobile app (Android/iOS emulator or phone, not web)

Requirements: [Flutter SDK](https://docs.flutter.dev/get-started/install), Android Studio (Android emulator) or Xcode (iOS), and the API above must be live.

1. Clone the repository and open a terminal in the Flutter folder:
   ```bash
   git clone https://github.com/MbarushimanaFabrice/linear_regression_model.git
   cd linear_regression_model/summative/FlutterApp
   ```
2. Generate the Android/iOS project files (keeps the existing `lib/main.dart` and `pubspec.yaml`):
   ```bash
   flutter create .
   ```
3. **Android only:** Internet access is already enabled in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   ```
4. Install packages:
   ```bash
   flutter pub get
   ```
5. Open `https://health-facility-absence-api.onrender.com/docs` in a browser once to wake the free server.
6. Start an emulator (Android Studio > Device Manager > Start) or plug in a phone with USB debugging, then check it with `flutter devices`.
7. Run the app, pointing it at your API:
   ```bash
   flutter run --dart-define=API_BASE_URL=https://health-facility-absence-api.onrender.com
   ```
   For local API development, use `http://127.0.0.1:8000` on Flutter web,
   desktop or an iOS simulator, and `http://10.0.2.2:8000` on an Android emulator:
   ```bash
   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
   ```
8. Type the 10 values (for example `Tanzania-2014`, `Health Post`, `Private`, `Rural`, then `1` for all six indicators) and tap **Predict**. Leave a field empty, type `abc` in a 0/1 field, or type `5` to see the readable error messages.

---

## Repository layout

```
linear_regression_model/
├── README.md
└── summative/
    ├── pyproject.toml, uv.lock          (notebook + tooling environment)
    ├── linear_regression/
    │   ├── multivariate.ipynb           (EDA, 4 models, loss curve, comparison, saved model)
    │   └── data/                        (the two SDI CSV files)
    ├── API/
    │   ├── prediction.py                (FastAPI app: /predict, /retrain, /docs, CORS)
    │   ├── retrain.py                   (model loading, prediction, retraining logic)
    │   ├── best_model.pkl               (saved pipeline: preprocessing + best model)
    │   ├── facility_training.csv        (cleaned training data used by /retrain)
    │   ├── requirements.txt, pyproject.toml, uv.lock
    └── FlutterApp/                      (one-page Flutter app)
```

## Run the API locally

```bash
cd summative/API
uv sync
uv run uvicorn prediction:app --reload
# open http://127.0.0.1:8000/docs
```

## Re-run the notebook

```bash
cd summative
uv sync
uv run jupyter lab      # open linear_regression/multivariate.ipynb and Run All
```
Running the notebook regenerates `API/best_model.pkl` and `API/facility_training.csv`.

## Deploy on Render

Web service, root directory `summative/API`, build command `pip install -r requirements.txt`, start command `uvicorn prediction:app --host 0.0.0.0 --port $PORT`, environment variable `PYTHON_VERSION=3.12.3`, free instance type.
