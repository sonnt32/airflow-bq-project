# Mobile Game Data Pipeline: Incremental ETL with Airflow & BigQuery

## 📌 Project Overview
This project implements a professional **Incremental ETL pipeline** for mobile game analytics. It transitions from raw Firebase/GA4 event exports to structured analytical models. The architecture is designed to handle large-scale data efficiently by processing only daily delta changes, significantly reducing BigQuery processing costs and improving data reliability.

The pipeline automates the transformation of event-level data (User Progression, Monetization, Engagement) into high-level Business KPIs like DAU (Daily Active Users) and Average Events per User.

## 🚀 Key Features
- **Incremental Data Loading**: Uses `MERGE` and `DELETE/INSERT` patterns to handle daily data updates without duplication (Idempotency).
- **BigQuery Optimization**: Implements **Table Partitioning** (by date) and **Clustering** (by event/user) for high-performance querying.
- **Workflow Orchestration**: Scheduled at 02:00 AM daily via Apache Airflow to ensure stakeholders have fresh data every morning.
- **Data Modeling**: Separates concerns into **Staging (STG)** for raw flattened data and **Fact (FCT)** for aggregated metrics.

## 🛠 Tech Stack
- **Orchestration**: Apache Airflow (Dockerized)
- **Data Warehouse**: Google BigQuery (Standard SQL)
- **Infrastructure**: Docker & Docker Compose
- **Scripting**: Python (DAGs) & Jinja2 (SQL Templating)

## 📂 Project Structure
```text
airflow-bq-project/
├── dags/
│   └── merge_dag.py                # Workflow orchestration & scheduling
├── sql/
│   ├── flatten_raw.sql     # Schema init & Incremental Staging load
│   └── event_base.sql      # Daily KPI aggregation (DAU, Events/User)
├── keys/                           # Service Account JSON (Git-ignored)
├── airflow-db/                     # Airflow metadata configuration
├── docker-compose.yaml             # Container orchestration
└── README.md
```
## ⚙️ How to Run (Step-by-Step)

### 1. Prerequisites
* Install **Docker Desktop** on Windows/Mac.
* A **Google Cloud Project** with BigQuery API enabled.
* A **Service Account** with roles: `BigQuery Job User` and `BigQuery Data Editor`.

### 2. Environment Setup
* Clone this repository:
    ```bash
    git clone [https://github.com/sonnt32/airflow-bq-project.git](https://github.com/sonnt32/airflow-bq-project.git)
    cd airflow-bq-project
    ```
* Create a folder named `keys/` and place your Service Account JSON file inside.
* Create a `.env` file in the root directory and add your User ID (to avoid permission issues in Docker):
    ```env
    AIRFLOW_UID=50000
    ```

### 3. Launching Airflow
* **Initialize the database** (First time only):
    ```bash
    docker-compose up airflow-init
    ```
* **Start all services**:
    ```bash
    docker-compose up -d
    ```
* Access the Airflow UI at `http://localhost:8080` (Default credentials: `airflow` / `airflow`).

### 4. Configure Google Cloud Connection
1.  In Airflow UI, navigate to **Admin > Connections**.
2.  Find or create `google_cloud_default`.
3.  Set **Conn Type** to `Google Cloud`.
4.  Enter your **Project ID**.
5.  Paste the entire content of your **Service Account JSON** into the **Keyfile JSON** field.
6.  Click **Save**.

### 5. Trigger the Pipeline
* Go to the **DAGs** tab, unpause `workflow_game_analytics_pipeline`, and trigger it manually to test the first run.
