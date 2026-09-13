# layer2_toolkit — engine dùng chung cho mọi game

`python/l2_generator.py` là engine **game-agnostic**: nhận 1 `L2Config` (game
nào, raw dataset nào, dataset L2 nào, danh sách event/param nào) và sinh SQL
theo pattern idempotent-partition-load (`CREATE TABLE IF NOT EXISTS` →
`DELETE` đúng partition ngày đang chạy → `INSERT` lại đúng partition đó).
Logic tách 1 event GA4 export thành 1 bảng L2 nằm ở ĐÂY, không lặp lại ở
từng project game.

## Vì sao tách riêng thế này

- **Engine dùng chung, config riêng từng game** — game mới không phải viết
  lại logic build SQL, chỉ khai báo sự khác biệt của mình.
- **Độc lập giữa các game**: mỗi game có `game_config.py` + `sql/` riêng
  trong `layer2_projects/<game>/`. Sửa `game_config.py` của Obby 1 không ảnh
  hưởng Obby 2, Obby 3... (miễn không sửa `l2_generator.py`).
- Chỉ sửa `l2_generator.py` khi cần thay đổi hành vi CHUNG cho mọi game
  (vd đổi pattern DELETE+INSERT, thêm cột chuẩn mới) — thay đổi này ảnh
  hưởng TẤT CẢ game dùng toolkit, cân nhắc kỹ trước khi sửa.

## Onboard 1 game mới (vd "Obby 2")

1. Tạo thư mục `layer2_projects/obby2/`.
2. Copy `layer2_projects/obby1/game_config.py` và `gen_layer2.py` sang, sửa:
   - `game_config.py`: đổi `gcp_project`, `raw_dataset`, `dst_dataset`,
     `context_events`, và dict `EVENTS` (event/param thực tế của game này).
   - `gen_layer2.py`: chỉ cần sửa docstring — logic import `game_config` +
     `l2_generator` giữ nguyên, không cần sửa code.
3. Tạo DAG riêng trong `airflow_platform/dags/` theo mẫu
   `obby1_layer2_build_dag.py` (đổi `PROJECT_DIR`, `dag_id`, `CREDS`,
   giờ chạy — nên lệch giờ với DAG layer2 của game khác và chạy TRƯỚC DAG
   dbt marts đọc dữ liệu L2 của game đó).
4. Thêm entry cho game vào `GAME_CONFIGS` trong `dag_factory.py` (dbt marts
   đọc bảng `evt_*` qua `source()`) — xem `dbt_core/projects/obby1/` làm mẫu
   dbt project đọc Layer 2.

## Nguyên tắc bắt buộc (mọi game, không ngoại lệ)

- **INSERT-only**: mỗi lần chạy chỉ được đụng đúng 1 partition
  (`event_date` của ngày đang generate). KHÔNG BAO GIỜ dùng
  `CREATE OR REPLACE TABLE` — sẽ xoá sạch dữ liệu các ngày khác đã build.
- **1 event = 1 bảng**, data-driven theo event thực tế có trong data GA4
  export của game, không theo tracking plan JSON của game khác.
- Cột chuẩn mọi bảng (do `l2_generator.BASE_COLS` sinh, không tự thêm lại):
  `user_pseudo_id`, `user_id`, `event_name`, `event_date`, `event_timestamp`,
  `event_ts`, `ga_session_id`.
- Chỉ 2 event context (`first_open`, `session_start` theo mặc định, có thể
  đổi qua `context_events`) mang thêm cột user/device/geo/app
  (`l2_generator.CONTEXT_COLS`) — event khác join ngược về bảng context khi
  cần.
