{% macro generate_schema_name(custom_schema_name, node) -%}
    {#
        Override behavior mặc định của dbt:
        - Mặc định: dataset_gốc + "_" + custom_schema  →  analytics_485408210_stg  ❌
        - Sau override: chỉ dùng đúng custom_schema    →  stg                      ✅

        Ràng buộc bắt buộc đi kèm: mỗi game PHẢI có 1 GCP project riêng (xem
        GAME_CONFIGS trong dag_factory.py). Macro này bỏ qua default_schema (dataset
        gốc) nên nếu 2 game share chung 1 GCP project, dataset "stg"/"marts" của chúng
        sẽ đụng nhau. Không share GCP project giữa các game.
    #}

    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
