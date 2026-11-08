# Computer Vision Benchmark ETL Pipeline & Data Warehouse

[![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python&logoColor=white)](https://www.python.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15%2B-336791?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Pydantic](https://img.shields.io/badge/Pydantic-v2.0%2B-E92063?logo=pydantic&logoColor=white)](https://docs.pydantic.dev/)
[![psycopg3](https://img.shields.io/badge/psycopg-v3-336791?logo=postgresql&logoColor=white)](https://www.psycopg.org/psycopg3/)
[![Code Style](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/psf/black)

A high-performance, transactional ETL pipeline and relational data warehouse designed for computer vision algorithm benchmark evaluation (e.g., Connected Component Labeling / CCL libraries like **FlyRLECCL** and **OpenCV**).

The system adopts a **Fail-Fast architecture** with isolated benchmark bundles, multi-stage schema enforcement, and an in-database transformation pipeline triggered via PostgreSQL PL/pgSQL procedures.

---

## 📐 Architecture Overview

The system processes benchmark runs as **atomic bundles**. Each bundle contains a metadata manifest (`<benchmark_name>.json`) and performance metrics recorded in raw CSV logs.

```
                  +-----------------------------------+
                  |      Raw Benchmark Bundle         |
                  |  JSON Passport + Metric CSVs      |
                  +-----------------------------------+
                                    |
                                    v
+-----------------------------------------------------------------------+
|                        PYTHON ETL RUNTIME                             |
|                                                                       |
|  [Step 1: Parse JSON]  --->  [Step 2: Check Schema]                  |
|  Strict Pydantic models       CSV headers vs. models                  |
|                                                                       |
|  [Step 3: Register Entities]---> [Step 4: Line-by-Line Validation]    |
|  Users, Environment, Binaries  Coercion & bad row isolation           |
|                                (invalid -> _errors.csv)               |
|                                                                       |
|  [Step 5: Bulk Load]                                                  |
|  psycopg3 parameterization -> PostgreSQL buffer (tmp_log)             |
|                                                                       |
|  [Step 6: Finalize Run]                                               |
|  UPDATE benchmarks SET end_at = NOW()                                 |
+-----------------------------------------------------------------------+
                                    |
                                    v
+-----------------------------------------------------------------------+
|                       POSTGRESQL DATAWAREHOUSE                        |
|                                                                       |
|  [PL/pgSQL Trigger: trg_benchmark_finished]                           |
|    ├── Normalize path strings & dataset tokens                        |
|    ├── Verify reference outputs vs actual execution                   |
|    ├── Upsert test modes, test settings, & image dimensions           |
|    ├── Insert performance metrics into core facts table (metrics)     |
|    └── Clear buffer (tmp_log)                                         |
|                                                                       |
|  [Analytical View: v_metrics_dashboard]                               |
|    └── Pre-calculated CPU cycles / pixel for Tableau / BI             |
+-----------------------------------------------------------------------+
```

---

## 🌟 Key Features

* **Atomic Bundle Processing:** Benchmarks are fully processed or rolled back on failure ("All-or-Nothing").
* **Fail-Fast & Row-Isolation:** Schema mismatches halt execution before modifying database tables. Individual malformed metric rows are safely written to localized `<file>_errors.csv` reports for debugging without corrupting the pipeline.
* **In-Database ETL:** Heavy data processing, path parsing, and verification logic are handled directly inside PostgreSQL via set-based PL/pgSQL triggers (`trg_fn_process_benchmark_etl`), minimizing Python memory overhead.
* **SQL Injection Prevention:** Dynamic query synthesis via `psycopg.sql` identifiers and placeholders.
* **Analytical BI Mart:** Denormalized view `v_metrics_dashboard` converts raw timings (milliseconds) into standardized **CPU cycles per pixel** using hardware frequency specs (`cpu_ghz`).

---

## 🛠 Tech Stack

* **Language:** Python 3.10+
* **Validation & Settings:** Pydantic v2, `pydantic-settings`
* **Database Driver:** `psycopg3` (Native binary protocol, connection pooling)
* **Database:** PostgreSQL 15+ (Compatible with Neon / Cloud Postgres)
* **Logging:** `loguru` (Console output + structured JSON file rotation)

---

## 📁 Repository Structure

```
.
├── main.py                # Pipeline orchestrator & CLI entrypoint
├── settings.py            # Global configuration (pydantic-settings)
├── .env.example           # Environment variable template
├── pyproject.toml         # Modern project metadata and dependency management (PEP 621)
├── requirements.txt       # Legacy/direct dependency list for quick pip installation
├── src/
│   ├── __init__.py
│   ├── logger.py          # Loguru configuration with console & JSON sinks
│   ├── schemas.py         # Pydantic schemas for passports & metrics
│   ├── parser.py          # JSON passport parsing & business rule validation
│   ├── data_validator.py  # CSV schema enforcement & line-by-line validation
│   └── loader.py          # Database registration & dynamic psycopg3 loader
└── sql/
    └── schema.sql         # DDL, indexes, triggers, and analytical views
```

---

## 🗄 Database Model

The database follows a normalized star-schema variation optimized for benchmark variability:

* **Dimensions:** `users`, `roles`, `datasets`, `images`, `libs`, `binaries`, `environments`, `stats_layouts`, `validation_types`, `validation_modes`, `test_modes`, `test_settings`.
* **Fact / Junction:** `benchmarks`, `test_treatments`, `metrics`.
* **Staging Buffer:** `tmp_log` (unlogged/indexed staging buffer for raw ingest).

### Core Analytical View
`v_metrics_dashboard` computes standardized micro-performance metrics on verified runs:

$$\text{Cycles Per Pixel} = \frac{\text{Time (ms)} \times \text{CPU Clock (GHz)} \times 10^6}{\text{Image Width} \times \text{Image Height}}$$

---

## 🚀 Getting Started

### 1. Prerequisites
* Python 3.10+
* PostgreSQL 15+

### 2. Environment Setup

Clone the repository and install dependencies:
```bash
git clone https://github.com/your-username/cv-benchmark-etl.git
cd cv-benchmark-etl
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 3. Database Initialization

Execute the SQL script to create tables, default catalogs, triggers, and analytical views:
```bash
psql -h <db_host> -U <db_user> -d <db_name> -f sql/schema.sql
```

### 4. Configuration

Create a `.env` file in the project root:
```env
ENVIRONMENT=development
DEBUG=true
DATABASE_URL=postgresql://user:password@localhost:5432/benchmark_db?sslmode=disable
DB_POOL_SIZE=5
DB_MAX_OVERFLOW=10
```

---

## 🏃 Running the Pipeline

### 1. Prepare benchmark folder bundles
Place your benchmark folder bundles inside `data/staging/`:

```
data/staging/
└── benchmark_run_001/
    ├── benchmark_run_001.json
    ├── flyrleccl_results.csv
    └── opencv_results.csv
```

### 2. Install Dependencies
Before running the pipeline for the first time, ensure all required Python packages are installed:

Using modern pyproject.toml (recommended) from the project root:

```bash
pip install .
```

Or using traditional requirements.txt from the project root:

```bash
pip install -r requirements.txt
```

(Optional) Verify that all dependencies are installed correctly:

```bash
python -c "import typer, psycopg, pydantic, pydantic_settings, loguru, click; print('Environment ready!')"
```

### 3. Execute the Pipeline
Run the pipeline from the project root:
1) without parameters:
```bash
python main.py
```
2) or with parameters, for example:
```bash
python main.py --source s3 --benchmark-list "bench_2026_q1,bench_2026_q2"
```

### Bundle Lifecycle:
1. **Validation Success:** Metrics are loaded into `tmp_log`, the database trigger executes ETL transformations, and the bundle directory moves to `data/archive/`.
2. **Data Failure:** Corrupted lines are written to `data/staging/<bundle>/<file>_errors.csv`.
3. **Schema Failure:** Pipeline halts before committing database modifications.

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.