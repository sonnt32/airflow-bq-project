from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from datetime import datetime, timedelta

# Định nghĩa các tham số mặc định
default_args = {
    'owner': 'son_nguyen',
    'depends_on_past': False,
    'email_on_failure': False,
    'retries': 0,
    'retry_delay': timedelta(minutes=1),
}

with DAG(
    'game_bq_pipeline_v1',
    default_args=default_args,
    description='Pipeline ETL chạy Flat và Base trên BigQuery',
    schedule_interval='0 2 * * *', # Chạy 2 giờ sáng mỗi ngày
    start_date=datetime(2024, 1, 1),
    catchup=False,
    template_searchpath=['/opt/airflow/sql'], # Đường dẫn để Airflow tìm file .sql
) as dag:

    # Task 1: Chạy SQL Flat từ Raw
    run_flatten_raw = BigQueryInsertJobOperator(
        task_id='run_flatten_raw',
        configuration={
            "query": {
                "query": "{% include 'flatten_raw.sql' %}",
                "useLegacySql": False,
            }
        },
        gcp_conn_id='google_cloud_default' # ID kết nối đã tạo trên giao diện Airflow
    )

    # Task 2: Chạy SQL đưa dữ liệu vào Base
    run_event_base = BigQueryInsertJobOperator(
        task_id='run_event_base',
        configuration={
            "query": {
                "query": "{% include 'event_base.sql' %}",
                "useLegacySql": False,
            }
        },
        gcp_conn_id='google_cloud_default'
    )

    # Thiết lập thứ tự: Flat chạy xong mới đến Base
    run_flatten_raw >> run_event_base