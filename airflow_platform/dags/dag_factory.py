"""
dag_factory.py — Tạo DAG tự động cho mỗi game project

Pipeline mỗi game:
    Task 0a: create_stg_dataset       ← tạo dataset 'stg' nếu chưa có
    Task 0b: create_marts_dataset     ← tạo dataset 'marts' nếu chưa có
        (0a và 0b chạy song song)
    Task 1:  dbt_run_{model}          ← 1 task / model, theo thứ tự khai báo
    Task N:  dbt_test                 ← kiểm tra data quality

Để thêm game mới:
    1. Tạo dbt project riêng: dbt_core/projects/<project_name>/
       (dbt_project.yml + models/) — xem dbt_core/projects/annoying_puzzle/
       làm mẫu. KHÔNG copy models vào project khác.
    2. Thêm 1 entry vào GAME_CONFIGS bên dưới.
    Không cần sửa gì khác trong file này.

CÔ LẬP GIỮA CÁC GAME:
    Mỗi game là 1 dbt project riêng, build vào 1 image dùng chung
    (dbt-core:latest) nhưng chạy qua `--project-dir /dbt/projects/<project>`.
    dbt chỉ parse SQL bên trong project-dir được chỉ định -> thêm/sửa model
    hoặc lỗi cú pháp ở project A không ảnh hưởng project B (không giống cách
    dồn hết model vào 1 project rồi lọc bằng --select, vốn vẫn parse toàn bộ
    file .sql của mọi game).

    Convention đặt tên model vẫn giữ prefix theo game (phòng vệ thêm, không
    bắt buộc để tránh xung đột kỹ thuật nhưng giúp truy vết trên BigQuery):
    ap_ = annoying-puzzle | bm_ = brainy-master | ob1_ = obby1

    Ràng buộc bắt buộc: mỗi game 1 GCP project riêng (xem macro
    generate_schema_name trong dbt_core/macros_shared/) — dataset "stg"/
    "marts" không có tiền tố nên 2 game share chung GCP project sẽ đụng dataset.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.docker.operators.docker import DockerOperator
from docker.types import Mount
import os

# ============================================================
# PATHS
# ============================================================
SHARED_KEYS_HOST_PATH      = os.environ.get("SHARED_KEYS_PATH", "")
SHARED_KEYS_CONTAINER_PATH = "/opt/airflow/shared_keys"
DBT_PROJECTS_CONTAINER_DIR = "/dbt/projects"

# Giới hạn số container dbt chạy song song trên cùng máy Docker host, bất kể
# thêm bao nhiêu game (pool được tạo trong airflow-init, xem docker-compose.yaml).
DBT_DOCKER_POOL = "dbt_docker_pool"

# ============================================================
# GAME REGISTRY — Thêm game mới vào đây
# "project_name" PHẢI khớp đúng tên thư mục dbt_core/projects/<project_name>/
# ============================================================
GAME_CONFIGS = {
    "annoying_puzzle": {
        "gcp_project": "annoying-puzzle",
        "dataset":     "analytics_485408210",
        "location":    "US",
        "keyfile":     "annoying-puzzle-dbt.json",
        "description": "dbt pipeline GA4 — Annoying Puzzle",
        "schedule":    "0 1 * * *",   # 08:00 sáng giờ VN
        "models": [
            "ap_event_flatten_raw",   # → stg
            "ap_event_base",          # → stg
            # Thêm marts models vào đây khi có
            # "ap_fact_behavior",     # → marts
            # "ap_fact_ads",          # → marts
        ],
    },
    "brainy_master": {
        "gcp_project": "brainy-master-tricky-story",
        "dataset":     "analytics_495120919",
        "location":    "US",
        "keyfile":     "brainy-master-1.json",
        "description": "dbt pipeline GA4 — Brainy Master",
        "schedule":    "3 1 * * *",   # 08:03 sáng giờ VN — lệch 3' so với game khác, tránh dồn container dbt cùng lúc
        "models": [
            "bm_event_flatten_raw",   # → stg
            "bm_event_base",          # → stg
            # "bm_fact_behavior",     # → marts
        ],
    },
    "obby1": {
        "gcp_project": "suvival-master-obby-parkour",
        "dataset":     "obby1_layer2",
        "location":    "US",
        "keyfile":     "obby1-key.json",
        "description": "dbt marts R2-R8 — Obby 1 (đọc từ Layer 2 evt_*, build riêng bởi DAG obby1_layer2_build)",
        "schedule":    "6 1 * * *",   # 08:06 sáng giờ VN — chạy sau obby1_layer2_build (06:30 VN)
        "models": [
            "ob1_r2_minigame_full",
            "ob1_r3_funnel_monet_ltv",
            "ob1_r4_cohort_ltv",
            "ob1_r5_daily_ad_monetization",
            "ob1_r6_retention_curve",
            "ob1_r8_minigame_play_duration",
        ],
    },
    # --- Thêm game mới: copy block trên, đổi giá trị + tạo dbt_core/projects/<project_name>/ ---
    # "game_b": {
    #     "gcp_project": "game-b-gcp-project",
    #     "dataset":     "analytics_XXXXXXXXX",
    #     "location":    "US",
    #     "keyfile":     "game-b-dbt.json",
    #     "description": "dbt pipeline GA4 — Game B",
    #     "schedule":    "9 1 * * *",
    #     "models":      ["gb_event_flatten_raw", "gb_event_base"],
    # },
}

# ============================================================
# FACTORY — Không cần chỉnh bên dưới khi thêm game mới
# ============================================================
DEFAULT_ARGS = {
    "retries":     1,
    "retry_delay": timedelta(minutes=5),
    "owner":       "son_nguyen",
}

DBT_IMAGE  = "dbt-core:latest"
DOCKER_URL = "unix:///var/run/docker.sock"


def _create_dataset_if_not_exists(gcp_project, location, keyfile_name, dataset_name):
    """
    Kiểm tra dataset trong BigQuery project của game.
    - Chưa có → tạo mới tự động
    - Có rồi  → bỏ qua, không lỗi

    Dùng chung cho cả 'stg' và 'marts' — truyền dataset_name vào.
    """
    from google.cloud import bigquery
    from google.oauth2 import service_account
    from google.api_core.exceptions import Conflict

    keyfile_path = os.path.join(SHARED_KEYS_CONTAINER_PATH, keyfile_name)

    credentials = service_account.Credentials.from_service_account_file(
        keyfile_path,
        scopes=["https://www.googleapis.com/auth/cloud-platform"],
    )

    client = bigquery.Client(project=gcp_project, credentials=credentials)

    dataset_ref = bigquery.Dataset(f"{gcp_project}.{dataset_name}")
    dataset_ref.location = location

    try:
        client.create_dataset(dataset_ref, timeout=30)
        print(f"✅ Đã tạo dataset '{dataset_name}' trong project '{gcp_project}'")
    except Conflict:
        print(f"✅ Dataset '{dataset_name}' đã tồn tại trong project '{gcp_project}' — bỏ qua")


def make_dbt_task(dag, task_id, dbt_command, env_vars):
    """Tạo 1 DockerOperator task chạy lệnh dbt, giới hạn qua DBT_DOCKER_POOL."""
    return DockerOperator(
        task_id=task_id,
        image=DBT_IMAGE,
        command=dbt_command,
        auto_remove=True,
        docker_url=DOCKER_URL,
        network_mode="bridge",
        mount_tmp_dir=False,
        environment=env_vars,
        dag=dag,
        pool=DBT_DOCKER_POOL,
        mounts=[
            Mount(
                source=SHARED_KEYS_HOST_PATH,
                target="/dbt/keys",
                type="bind",
            )
        ],
    )


def build_env_vars(config: dict) -> dict:
    """Tạo env vars inject vào dbt container."""
    return {
        "DBT_GCP_PROJECT":  config["gcp_project"],
        "DBT_DATASET":      config["dataset"],
        "DBT_LOCATION":     config.get("location", "US"),
        "DBT_KEYFILE_PATH": f"/dbt/keys/{config['keyfile']}",
        "DBT_PROFILES_DIR": "/dbt",
    }


def create_dag(project_name: str, config: dict) -> DAG:
    """Tạo 1 DAG hoàn chỉnh cho 1 game project."""
    dag = DAG(
        dag_id=f"{project_name}_dbt_pipeline",
        default_args=DEFAULT_ARGS,
        description=config["description"],
        schedule_interval=config.get("schedule", "0 1 * * *"),
        start_date=datetime(2026, 4, 23),
        catchup=False,
        tags=["dbt", "ga4", project_name],
    )

    env_vars    = build_env_vars(config)
    project_dir = f"{DBT_PROJECTS_CONTAINER_DIR}/{project_name}"
    dbt_flags   = f"--profiles-dir /dbt --project-dir {project_dir}"

    # ----------------------------------------------------------
    # Task 0a + 0b: Kiểm tra và tạo dataset nếu chưa tồn tại
    # Chạy SONG SONG với nhau — độc lập, không phụ thuộc nhau
    # ----------------------------------------------------------
    create_stg = PythonOperator(
        task_id="create_stg_dataset",
        python_callable=_create_dataset_if_not_exists,
        op_kwargs={
            "gcp_project":  config["gcp_project"],
            "location":     config.get("location", "US"),
            "keyfile_name": config["keyfile"],
            "dataset_name": "stg",
        },
        dag=dag,
    )

    create_marts = PythonOperator(
        task_id="create_marts_dataset",
        python_callable=_create_dataset_if_not_exists,
        op_kwargs={
            "gcp_project":  config["gcp_project"],
            "location":     config.get("location", "US"),
            "keyfile_name": config["keyfile"],
            "dataset_name": "marts",
        },
        dag=dag,
    )

    # ----------------------------------------------------------
    # Task 1..N: dbt run từng model theo thứ tự, --project-dir cô lập
    # riêng project của game này (không đụng project khác)
    # ----------------------------------------------------------
    dbt_tasks = []
    for model_name in config["models"]:
        task = make_dbt_task(
            dag=dag,
            task_id=f"dbt_run_{model_name}",
            dbt_command=f"dbt run --select {model_name} {dbt_flags}",
            env_vars=env_vars,
        )
        dbt_tasks.append(task)

    # ----------------------------------------------------------
    # Task cuối: dbt test — project-dir đã tự giới hạn đúng model của game này
    # ----------------------------------------------------------
    test_task = make_dbt_task(
        dag=dag,
        task_id="dbt_test",
        dbt_command=f"dbt test {dbt_flags}",
        env_vars=env_vars,
    )
    dbt_tasks.append(test_task)

    # ----------------------------------------------------------
    # Chain:
    # create_stg   ─┐
    #                ├─→ dbt_task_1 >> dbt_task_2 >> ... >> dbt_test
    # create_marts ─┘
    #
    # 0a và 0b chạy song song, cả 2 xong mới chạy dbt tasks
    # ----------------------------------------------------------
    [create_stg, create_marts] >> dbt_tasks[0]

    for i in range(len(dbt_tasks) - 1):
        dbt_tasks[i] >> dbt_tasks[i + 1]

    return dag


# ============================================================
# Đăng ký tất cả DAGs vào Airflow global namespace
# ============================================================
for _project_name, _config in GAME_CONFIGS.items():
    globals()[f"{_project_name}_dbt_pipeline"] = create_dag(_project_name, _config)
