# 🎮 airflow-bq-project — Airflow vận hành nhiều dbt project trên Docker

> **Tác giả:** Son Nguyen
> **Dữ liệu:** Google Analytics 4 (Firebase) → BigQuery → dbt transform
> **Môi trường:** Docker Desktop (Windows)

---

## 📌 Mục đích dự án

Pipeline ELT cho nhiều game (GA4 → BigQuery → dbt), vận hành tự động bởi
1 Airflow instance dùng chung. Kiến trúc trung tâm là **"engine dùng chung,
config riêng từng game"**, áp dụng ở cả 2 tầng dbt và Airflow, để:

- Thêm game mới không phải viết lại hạ tầng (Docker image, DAG factory,
  script build Layer 2).
- Mỗi game vẫn **độc lập hoàn toàn**: sửa/thêm SQL, đổi tên model, hoặc lỗi
  cú pháp ở 1 game không ảnh hưởng game khác — kể cả khi tất cả chạy chung
  1 Docker image và 1 Airflow instance.

Hiện có 3 game: `annoying_puzzle`, `brainy_master` (dbt trực tiếp trên GA4
raw export), `obby1` (thêm 1 lớp Layer 2 trung gian trước dbt — xem phần
Layer 2 bên dưới).

---

## 🏗️ Kiến trúc hệ thống

```
BigQuery (GA4 raw export, mỗi game 1 GCP project riêng)
    │
    │ source()
    ▼
┌───────────────────────────────────────────────────────────┐
│ dbt_core  (1 Docker image: dbt-core:latest)                │
│                                                             │
│  projects/annoying_puzzle/   ← dbt project ĐỘC LẬP          │
│  projects/brainy_master/     ← dbt project ĐỘC LẬP          │
│  projects/obby1/             ← dbt project ĐỘC LẬP          │
│  macros_shared/              ← 1 nguồn, copy vào macros/    │
│                                 của mỗi project lúc build   │
└───────────────────────────────────────────────────────────┘
                     ▲
                     │ DockerOperator: dbt run/test --project-dir /dbt/projects/<game>
                     │
┌───────────────────────────────────────────────────────────┐
│ airflow_platform  (Docker Compose)                          │
│                                                             │
│  dag_factory.py → GAME_CONFIGS{} → 1 DAG / game tự động     │
│    <game>_dbt_pipeline: create_stg/marts_dataset            │
│                          → dbt run (1 task/model) → dbt test│
│    Pool "dbt_docker_pool" giới hạn số container dbt         │
│    chạy song song, bất kể thêm bao nhiêu game                │
│                                                             │
│  obby1_layer2_build (riêng, không qua dag_factory):          │
│    gen_layer2.py (layer2_toolkit) → bq_guard.py → BigQuery   │
└───────────────────────────────────────────────────────────┘
```

### Vì sao mỗi game là 1 dbt project riêng (không dồn chung 1 project)

dbt luôn parse **toàn bộ** file `.sql` trong `model-paths` để dựng dependency
graph, bất kể `--select` chọn model nào. Nếu mọi game dùng chung 1
`dbt_project.yml`/`models/`, một lỗi cú pháp hoặc đổi tên model ở game A vẫn
làm `dbt run`/`dbt test` của game B thất bại — vi phạm nguyên tắc "chung hạ
tầng nhưng độc lập". Giải pháp: mỗi game có `dbt_project.yml` + `models/`
riêng dưới `dbt_core/projects/<game>/`, Airflow gọi đúng project bằng
`--project-dir`. Macro dùng chung (`macros_shared/`) được nhân bản vào
`macros/` của từng project **lúc build image** (không phải mount runtime) nên
mỗi project trong container vẫn tự chứa đủ để chạy một mình.

Quy ước đặt tên model vẫn giữ tiền tố theo game (`ap_`, `bm_`, `ob1_`) như một
lớp phòng vệ thêm và giúp truy vết trên BigQuery, dù không còn bắt buộc để
tránh xung đột kỹ thuật (đã được `--project-dir` đảm bảo).

**Ràng buộc bắt buộc:** mỗi game 1 GCP project riêng. Macro
`generate_schema_name` (trong `macros_shared/`) bỏ qua dataset gốc, chỉ dùng
đúng tên schema khai báo (`stg`/`marts`) — nên 2 game share chung 1 GCP
project sẽ đụng dataset.

---

## 📁 Cấu trúc thư mục

```
airflow-bq-project/
│
├── dbt_core/
│   ├── Dockerfile                 # Build 1 image chứa mọi project (copy-at-build)
│   ├── profiles.yml               # Dùng chung mọi project — không chứa secret, AN TOÀN commit
│   ├── macros_shared/             # Nguồn duy nhất cho macro dùng chung
│   └── projects/
│       ├── annoying_puzzle/       # dbt project độc lập
│       │   ├── dbt_project.yml
│       │   └── models/
│       ├── brainy_master/         # dbt project độc lập
│       └── obby1/                 # dbt project độc lập — đọc từ obby1_layer2.evt_*
│
├── airflow_platform/
│   ├── docker-compose.yaml        # Webserver + Scheduler + Postgres; tạo pool dbt_docker_pool
│   └── dags/
│       ├── dag_factory.py         # GAME_CONFIGS{} → sinh DAG *_dbt_pipeline tự động
│       └── obby1_layer2_build_dag.py  # Build Layer 2 cho Obby 1 (không qua dbt)
│
├── layer2_projects/                # Lớp trung gian evt_* cho game cần transform phức tạp
│   ├── _shared/layer2_toolkit/     # Engine game-agnostic + README onboard game mới
│   └── obby1/                      # Config + SQL sinh ra riêng của Obby 1
│
├── scripts/bq_guard.py             # Cost guard bắt buộc cho mọi query BigQuery ad-hoc
│
├── shared_keys/                    # Service account key (KHÔNG commit — .gitignore)
└── .env                            # Biến môi trường (KHÔNG commit — .gitignore)
```

---

## 🚀 Hướng dẫn cài đặt và chạy

### Yêu cầu

- Docker Desktop, Git, VS Code (khuyến nghị)
- Google Cloud account với BigQuery + service account key cho mỗi game

### Bước 1 — Đặt service account key

```bash
mkdir -p shared_keys
# copy key thật của từng game vào, đúng tên khai báo trong GAME_CONFIGS
# (annoying-puzzle-dbt.json, brainy-master-1.json, obby1-key.json)
```

### Bước 2 — Build Docker image cho dbt (dùng chung mọi game)

```bash
docker build -f dbt_core/Dockerfile -t dbt-core:latest .
docker run --rm dbt-core:latest   # kỳ vọng: Core: installed: 1.8.0 | Plugins: bigquery: 1.8.0
```

### Bước 3 — Khởi động Airflow

```bash
cd airflow_platform
docker compose run --rm airflow-init   # tạo DB, user admin, pool dbt_docker_pool
docker compose up -d
```

### Bước 4 — Truy cập Airflow UI

```
http://localhost:8080   (admin / admin)
```

Mỗi game trong `GAME_CONFIGS` xuất hiện thành 1 DAG `<game>_dbt_pipeline` —
bật toggle và trigger. Obby 1 có thêm DAG `obby1_layer2_build` chạy trước
(06:30 sáng VN) để build dữ liệu Layer 2 mà `obby1_dbt_pipeline` sẽ đọc.

---

## ➕ Thêm game mới

**Game chỉ cần dbt trực tiếp trên GA4 raw** (như annoying_puzzle/brainy_master):

1. Tạo `dbt_core/projects/<game>/` với `dbt_project.yml` + `models/` riêng
   (copy từ `projects/annoying_puzzle/` làm mẫu, đổi `name:`, source, schema).
2. Thêm 1 entry vào `GAME_CONFIGS` trong `airflow_platform/dags/dag_factory.py`
   — `project_name` (key của dict) phải khớp đúng tên thư mục ở bước 1.
3. Rebuild image dbt (`docker build ...`) — Dockerfile tự động copy macro
   dùng chung vào project mới, không cần sửa Dockerfile.

**Game cần lớp Layer 2 trung gian** (như obby1): làm thêm theo hướng dẫn
trong [`layer2_projects/_shared/layer2_toolkit/README.md`](layer2_projects/_shared/layer2_toolkit/README.md)
trước khi làm 3 bước trên.

Không sửa gì khác — không đụng tới project dbt hay DAG của game đang chạy.

---

## 🔒 Bảo mật

Không bao giờ commit: `.env`, `shared_keys/`, file key dạng
`*-key.json` / `*-dbt.json` / `*service-account*.json` (xem `.gitignore`).
`dbt_core/profiles.yml` AN TOÀN để commit — chỉ chứa template `env_var()`,
giá trị thật được inject lúc container chạy bởi `dag_factory.build_env_vars()`.

Mọi truy vấn BigQuery ad-hoc (ngoài pipeline dbt) phải qua
`scripts/bq_guard.py` — dry-run ước lượng chi phí trước, chặn nếu vượt
ngưỡng, ghi log audit.

---

## 🧠 Kiến thức kỹ thuật đã áp dụng

### dbt

- **Multi-project trong 1 image**: mỗi game 1 `dbt_project.yml` độc lập,
  chọn qua `--project-dir` — cô lập lỗi/đổi tên giữa các game.
- **generate_schema_name override**: dataset đúng bằng tên schema khai báo,
  không nối thêm dataset gốc (đổi lại: bắt buộc 1 GCP project / game).
- **Incremental + partition + cluster** cho staging (annoying_puzzle,
  brainy_master); **table full-rebuild** cho marts đọc từ Layer 2 (obby1).
- **Surrogate key** (MD5) để dedup; **source()/ref()** quản lý phụ thuộc.

### Airflow

- **DAG factory pattern**: `GAME_CONFIGS` là nguồn sự thật duy nhất, DAG sinh
  tự động — thêm game không sửa code factory.
- **DockerOperator** cô lập môi trường dbt khỏi container Airflow.
- **Pool** giới hạn số container dbt chạy song song, không phụ thuộc số
  lượng game đã thêm.

### Layer 2 (obby1 và các game tương tự sau này)

- Engine game-agnostic (`l2_generator.py`) + config riêng từng game
  (`game_config.py`) — xem `layer2_projects/_shared/layer2_toolkit/README.md`.
- Pattern **insert-only theo partition** (`CREATE IF NOT EXISTS` → `DELETE`
  đúng ngày → `INSERT`) — không bao giờ `CREATE OR REPLACE TABLE`.

---

## 🔜 Kế hoạch phát triển tiếp theo

- CI tối thiểu: `dbt parse`/`dbt compile` cho từng project trong PR, bắt lỗi
  cú pháp trước khi merge (đặc biệt hữu ích khi số project tăng).
- Slack/Email alerting khi DAG thất bại.
- Chuyển credential sang Google Secret Manager cho môi trường production.
- Cân nhắc CeleryExecutor nếu số game tăng đủ lớn để LocalExecutor + pool
  không còn đủ song song.

---

## 📚 Tài liệu tham khảo

- [dbt Documentation](https://docs.getdbt.com)
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [GA4 BigQuery Export Schema](https://support.google.com/analytics/answer/7029846)
- [Docker Documentation](https://docs.docker.com)
