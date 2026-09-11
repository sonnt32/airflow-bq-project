"""
obby1_layer2_build_dag.py — Build Layer 2 per-event tables cho Obby 1
(gen_layer2.py + bq_guard.py) — HOÀN TOÀN ĐỘC LẬP với dag_factory.py.

Lý do tách riêng, không nhét vào GAME_CONFIGS của dag_factory.py:
  dag_factory.py chỉ biết orchestrate `dbt run` qua DockerOperator (image dbt-core:latest).
  Bước build Layer 2 của Obby 1 KHÔNG phải dbt — là script Python (gen_layer2.py) sinh SQL rồi
  chạy qua bq_guard.py (dry-run + cap GB bắt buộc theo policy cost-guard nội bộ, dùng
  google-cloud-bigquery đã có sẵn trong image Airflow qua _PIP_ADDITIONAL_REQUIREMENTS).

Nguyên tắc bắt buộc: pipeline tự động CHỈ được INSERT data mới, KHÔNG BAO GIỜ REPLACE/overwrite
data đã có — gen_layer2.py sinh SQL theo pattern CREATE TABLE IF NOT EXISTS -> DELETE đúng
partition event_date của ngày đang chạy -> INSERT lại đúng partition đó. Mỗi lần chạy chỉ đụng
1 ngày, an toàn tự động hoá daily.

Sau khi DAG này build xong Layer 2 (obby1_layer2.evt_*), DAG `obby1_dbt_pipeline` (sinh tự động
bởi dag_factory.py từ entry "obby1" trong GAME_CONFIGS) đọc các bảng evt_* này để build 6 mart
R2-R8 vào dataset obby1_layer2_reports. Lịch 06:30 sáng VN — chạy xong trước 08:00 (giờ dbt
marts của cả 3 game) để mart Obby 1 luôn đọc đúng data L2 mới nhất cùng ngày.

Code nguồn nằm trong chính repo này (không mount ra ngoài, xem docker-compose.yaml):
  layer2_projects/obby1/                    <- gen_layer2.py, game_config.py, sql/
  layer2_projects/_shared/layer2_toolkit/   <- l2_generator.py (engine dùng chung mọi game)
  scripts/bq_guard.py                       <- cost guard bắt buộc (bản vendor)
"""
from __future__ import annotations

import pendulum

from airflow import DAG
from airflow.operators.bash import BashOperator

PROJECT_DIR = "/opt/airflow/layer2_projects/obby1"
TOOLKIT_DIR = "/opt/airflow/layer2_projects/_shared/layer2_toolkit/python"
GUARD = "/opt/airflow/scripts/bq_guard.py"
CREDS = "/opt/airflow/shared_keys/obby1-key.json"

with DAG(
    dag_id="obby1_layer2_build",
    description="Layer 2 evt_* daily append cho Obby 1 (gen_layer2.py + bq_guard) — insert-only",
    schedule="30 6 * * *",  # 06:30 sáng giờ Việt Nam (start_date tz=Asia/Ho_Chi_Minh)
    start_date=pendulum.datetime(2026, 9, 1, tz="Asia/Ho_Chi_Minh"),
    catchup=False,
    max_active_runs=1,
    tags=["obby1", "layer2", "bigquery", "insert-only"],
) as dag:

    generate_l2_sql = BashOperator(
        task_id="generate_l2_sql",
        bash_command=(
            f"cd '{PROJECT_DIR}' && "
            f"LAYER2_TOOLKIT_PYTHON_DIR='{TOOLKIT_DIR}' python gen_layer2.py {{{{ ds_nodash }}}}"
        ),
    )

    run_l2_sql = BashOperator(
        task_id="run_l2_sql",
        bash_command=(
            f"cd '{PROJECT_DIR}' && "
            f"python '{GUARD}' sql/_00_create_dataset.sql --creds '{CREDS}' && "
            "for f in sql/_[0-9][0-9]_evt_*.sql; do "
            f"  echo \">> $f\" && python '{GUARD}' \"$f\" --creds '{CREDS}' || exit 1; "
            "done"
        ),
    )

    generate_l2_sql >> run_l2_sql
