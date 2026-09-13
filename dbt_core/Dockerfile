# ============================================================
# Dockerfile — 1 image dùng chung cho tất cả game projects.
#
# Mỗi game là 1 dbt project ĐỘC LẬP dưới projects/<game>/ (dbt_project.yml +
# models/ riêng). dbt chỉ parse model-paths bên trong project được chỉ định
# qua --project-dir (xem airflow_platform/dags/dag_factory.py) -> thêm/sửa
# SQL của 1 game KHÔNG được parse chung, KHÔNG thể làm hỏng game khác dù lỗi
# cú pháp hay đổi tên model.
#
# Build: docker build -f dbt_core/Dockerfile -t dbt-core:latest .
# ============================================================

FROM python:3.11-slim

# Cài dbt-bigquery (bao gồm dbt-core)
RUN pip install --no-cache-dir \
    dbt-bigquery==1.8.0

WORKDIR /dbt

# profiles.yml dùng chung cho mọi project (không chứa secret — xem file).
COPY dbt_core/profiles.yml /dbt/profiles.yml

# Mỗi game 1 project riêng: dbt_project.yml + models/ chỉ chứa SQL của chính nó.
COPY dbt_core/projects/ /dbt/projects/

# Macro dùng chung (1 nguồn duy nhất trong git): nhân bản vào macros/ của
# TỪNG project ở BUILD-TIME, không phải runtime mount/symlink — mỗi project
# trong image vẫn tự chứa đủ để chạy độc lập, không phụ thuộc project khác
# lúc container thực thi. Thêm thư mục project mới tự động được bao phủ,
# không cần sửa Dockerfile.
COPY dbt_core/macros_shared/ /dbt/macros_shared/
RUN for d in /dbt/projects/*/; do \
        mkdir -p "${d}macros" && cp -r /dbt/macros_shared/. "${d}macros/"; \
    done

# Thư mục chứa service account key
# (được mount lúc runtime, không baked vào image)
RUN mkdir -p /dbt/keys

# Verify cài đặt thành công
CMD ["dbt", "--version"]
