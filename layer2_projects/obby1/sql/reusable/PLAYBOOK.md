# Playbook — Reusable Queries bản Layer 2 (Obby 1)

Bộ query phân tích chuẩn của skill `game-data-analyst`, đã transform từ raw GA4 export
sang **`obby1_layer2.evt_*`** (mỗi event 1 bảng). Kèm: mỗi query trả lời câu hỏi gì,
và gặp câu hỏi tương tự thì chỉnh ở đâu.

- Project: `suvival-master-obby-parkour` · dataset đích: `obby1_layer2` · location US
- Data L2 hiện có: **ngày 20260901** (1 partition). Metric cần nhiều ngày → build thêm.
- File SQL: `r3_*`…`r8_*` (chạy lẻ) hoặc `reusable_LAYER2.sql` (gộp, **chạy từng khối R#**).

---

## 1. Bảng tra nhanh — query nào cho câu hỏi nào

| Query | Trả lời câu hỏi chính | Grain output |
|---|---|---|
| **R3** New User Funnel Monetization + LTV | "Phiên bản X kiếm tiền tốt không? imp/DAU, eCPM, ARPDAU, LTV D0/D3/D7 bao nhiêu?" | 1 dòng / version |
| **R4** Cohort LTV D0/D1/D3/D7 | "LTV theo từng ngày cài (cohort) tăng giảm ra sao? Cohort nào tốt hơn?" | 1 dòng / (version × cohort_date) |
| **R5** Daily Ad Monetization Dashboard | "Mỗi ngày: imp/DAU, viewer rate, eCPM, ARPDAU theo từng format quảng cáo?" | 1 dòng / ngày |
| **R6** Retention Curve D1–D7 | "Giữ chân người mới thế nào? D1/D3/D7 retention theo cohort?" | 1 dòng / (version × cohort_date) |
| **R8** Minigame Play Duration & Result Rate | "Minigame nào bị bỏ nhiều? Chơi bao lâu? Tỉ lệ win/lose/quit?" | 1 dòng / (version × minigame_id) |

---

## 2. Quy tắc transform raw → Layer 2 (để tự viết query mới)

| Raw GA4 export | Layer 2 |
|---|---|
| `FROM events_* WHERE event_name='X'` + `_TABLE_SUFFIX BETWEEN …` | `FROM obby1_layer2.evt_X` (không suffix; "range ngày" = partition đang có) |
| `EXECUTE IMMEDIATE FORMAT(""" … """, var_dataset_path)` | bỏ hẳn — tên bảng cố định, chỉ cần `DECLARE` cho version/geo |
| `(SELECT value.double_value FROM UNNEST(event_params) WHERE key='value')` | cột `value` (đã là FLOAT64) |
| `(SELECT value.string_value FROM UNNEST(event_params) WHERE key='minigame_id')` | cột `minigame_id` (đã là STRING; param số cũng lưu STRING → `SAFE_CAST` khi tính) |
| `app_info.version` trên bảng bất kỳ | **KHÔNG có** trên bảng event — join `evt_first_open` (hoặc `evt_session_start`) để lấy |
| `geo.country`, `device.*`, `traffic_source.*` | chỉ có trên `evt_first_open` / `evt_session_start` |
| `(SELECT value.string_value FROM UNNEST(user_properties) WHERE key='current_Screen')` | cột `current_screen` (có trên mọi bảng) |
| `UPPER(ad_format) LIKE '%BANNER%'` | `STARTS_WITH(UPPER(ad_format),'BANNER')` — nhóm: BANNER / MREC(`MREC`,`MEDIUM_`) / INTER / REWARDED / else OTHER |
| DAU = user có `user_engagement` | DAU = user có `evt_session_start` (chuẩn Data Foundation) |
| join 2 event theo `user_pseudo_id` + session | `USING (user_pseudo_id, ga_session_id)` — `ga_session_id` có trên mọi bảng |

**Bảng context** (mang toàn bộ user/device/geo/app): `evt_first_open`, `evt_session_start`.
**Cột chung mọi bảng**: `user_pseudo_id`, `user_id`(NULL), `event_name`, `event_date`,
`event_timestamp`, `event_ts`, `ga_session_id`, `current_screen`.

**Chi phí**: query L2 quét ~0.01–0.05 GB (vs raw 0.4–2 GB, và raw lặp `FROM` nhiều lần trong
EXECUTE IMMEDIATE). Vẫn chạy qua `bq_guard.py`.

---

## 3. Chi tiết từng query

### R3 — New User Funnel Monetization + LTV D0/D3/D7
**File**: `r3_funnel_monet_ltv.sql`

**Trả lời**:
- "Version 1.0.8 với 1.0.9, cái nào ARPDAU / eCPM / LTV D7 cao hơn?"
- "Người mới (cohort first_open) xem bao nhiêu ad mỗi ngày? tỉ lệ ai có xem ad (viewer rate)?"
- "eCPM từng format (banner/mrec/inter/reward) của version này?"
- "LTV D0/D3/D7 trung bình của các cohort trong kỳ?"

**Input** (`DECLARE`): `var_versions` (rỗng = mọi version), `var_exclude_geo` (mặc định `['China']`).

**Output** (1 dòng/version): `avg_dau`, `avg_new_users`, `*_imp_per_dau`, `*_viewer_rate`,
`arpdau`, `ecpm` + `banner/mrec/inter/reward_ecpm`, `ltv_d0/d3/d7`.

**Câu hỏi tương tự → chỉnh**:
- Chỉ 1 vài version: `SET var_versions = ['1.0.8','1.0.9']`.
- Loại thêm nước: `var_exclude_geo = ['China','North Korea']`.
- Đổi cohort sang "user active" thay vì "first_open": đổi CTE `user_identity` đọc từ
  `evt_session_start` thay vì `evt_first_open` (mất cột geo → bỏ điều kiện `geo_country`).
- Thêm format Native/AppOpen: thêm nhánh `STARTS_WITH` trong `ad_events_normalized` + cột tương ứng.

**Verify**: ✅ khớp raw 100% (mọi version, cohort 20260901).
**LTV D3/D7**: cần L2 có 20260901→20260908; hiện `ltv_d3=ltv_d7=ltv_d0`.

---

### R4 — New User Cohort LTV D0/D1/D3/D7
**File**: `r4_cohort_ltv.sql`

**Trả lời**:
- "LTV D0/D1/D3/D7 của **từng ngày cài** (không gộp) — cohort ngày nào kiếm tiền tốt hơn?"
- "Cohort đã đủ 7 ngày tuổi chưa (tránh so cohort non)?" → cột `is_d7_mature`.
- "Số user mới mỗi ngày mỗi version?" → cột `new_users`.

**Input**: `var_versions`, `var_exclude_geo`.

**Output** (1 dòng / version × cohort_date): `new_users`, `ltv_d0/d1/d3/d7`, `is_d7_mature`.

**Câu hỏi tương tự → chỉnh**:
- Muốn LTV tới D14/D30: đổi `BETWEEN 0 AND 7` (2 chỗ: `user_cohort_day_rev`, các dòng `rev_dX`)
  thành 14/30 + thêm cột `rev_d14` … (cần build L2 đủ ngày).
- Muốn LTV theo **doanh thu IAP** thay vì ad: đổi `daily_revenue` đọc từ bảng purchase
  (obby 1 chưa có event IAP → hiện chỉ ad).
- LTV per country/network: thêm country vào `user_identity` (từ `evt_first_open.geo_country`)
  và `GROUP BY` thêm cột đó.

**Verify**: ✅ khớp raw (1.0.8 → ltv_d0 `0.028889`, 1.0.9 → `0.001901`).

---

### R5 — Daily Ad Monetization Dashboard
**File**: `r5_daily_ad_monetization.sql`

**Trả lời**:
- "Mỗi ngày: imp/DAU, viewer rate, eCPM, ARPDAU theo banner / mrec / inter / reward?"
- "eCPM inter đang tụt từ ngày nào?"
- "Tỉ lệ user có xem ít nhất 1 ad mỗi ngày (`total_ad_viewer_rate`)?"

**Input**: `var_versions`, `var_cohort_event` (`'first_open'` | `'session_start'`).

**Output** (1 dòng/ngày): `active_user`, `*_imp_per_dau`, `*_viewer_rate`,
`*_ecpm`, `arpdau`, `cohort_rr_d1`.

**Câu hỏi tương tự → chỉnh**:
- Tách theo version: `GROUP BY 1` → `GROUP BY 1, uv.app_version` và thêm cột version vào SELECT.
- Không giới hạn cohort (toàn bộ user active, kể cả cũ): bỏ `INNER JOIN user_identity`.
- Đổi "active" về đúng skill gốc (`user_engagement`): thay `evt_session_start` bằng
  `evt_user_engagement` trong nhánh `is_active_today` (không khuyến nghị — lệch Data Foundation).

**Verify**: ✅ eCPM từng format khớp raw (banner `0.618`, inter `7.42`, reward `8.62`).
`cohort_rr_d1` cần ≥ 2 ngày → hiện NULL.

---

### R6 — Retention Curve D1–D7
**File**: `r6_retention_curve.sql`

**Trả lời**:
- "D1 / D3 / D7 retention theo từng cohort_date × version?"
- "Cohort nào giữ chân tốt/tệ bất thường?"
- "Cohort đã đủ tuổi để đọc D7 chưa?" → `is_d7_mature`.

**Input**: `var_versions`.

**Output** (1 dòng / version × cohort_date): `new_users`, `d1..d7_retention` (%), `is_d7_mature`.

**Câu hỏi tương tự → chỉnh**:
- Retention D14/D30: mở `BETWEEN 1 AND 7` trong `user_cohort_activity` thành 30, thêm
  `dXX_active` trong `retention_pivot` + cột retention tương ứng.
- Rolling retention (active ngày ≥ N thay vì đúng ngày N): đổi `cohort_day = X` thành `>= X`.
- Retention theo country / network: thêm cột đó vào `user_identity` + `GROUP BY`.

**Verify**: cấu trúc OK, `new_users` khớp. D1–D7 = NULL (chưa có ngày sau 20260901).
Build L2 20260901→20260908 để ra số thật.

---

### R8 — Minigame Play Duration & Result Rate
**File**: `r8_minigame_play_duration.sql`

**Trả lời**:
- "Minigame nào bị bỏ nhiều (complete_rate thấp / quit_rate cao)?"
- "Mỗi minigame chơi trung bình bao lâu? khi win vs lose vs quit?"
- "Bao nhiêu người mới thử từng minigame (`users_start`)?"

**Input**: `var_versions`.

**Output** (1 dòng / version × minigame_id): `users_start`, `users_end`, `complete_rate_pct`,
`win/lose/quit_rate_pct`, `avg_duration_*_s`.

**Câu hỏi tương tự → chỉnh**:
- Game có param `level` (puzzle/level-based, không phải obby): đổi `minigame_id` → cột level
  (`SAFE_CAST(... AS INT64)`), thêm `DECLARE var_level_from/to` + filter.
- Chỉ 1 minigame: thêm `WHERE minigame_id = 'PushTheBall'`.
- Thêm chỉ số attempt/deaths (obby 1 có sẵn trên `evt_level_end`): thêm
  `AVG(SAFE_CAST(attempt AS INT64))`, `AVG(SAFE_CAST(deaths AS INT64))` vào `agg_end`.
- Bổ sung bucket kết quả khác: `result_by` thực tế = `win` / `lose` / `quit`; thêm nhánh nếu version mới có giá trị khác.

**Verify**: ✅ khớp raw — `users_start` / `users_end` / `win_count` từng minigame khớp tuyệt đối
(PushTheBall 779/557/310, RedLightGreenLight 976/925/447, StealTheBrainrot 869/247/0…).

---

## 4. Chưa chuyển được — cần đổi schema Layer 2

| Query gốc (memory skills.md) | Trả lời câu hỏi gì | Vướng | Cần làm |
|---|---|---|---|
| **A/B Test Ad Monetization Summary** | "Variant nào của AB test cho ARPDAU / eCPM / ARPU cao hơn?" | L2 chỉ giữ `current_screen` từ user_properties, **không có cột experiment variant** | thêm param `experiment_key` → cột `exp_variant` trong `gen_layer2.py` (đọc `user_properties[key]`); obby 1 hiện chỉ có `firebase_exp_8`, rất ít user |
| **Sankey User Journey (Session 1)** | "Người mới đi qua các bước/màn hình theo luồng nào? rơi ở đâu?" | cần duyệt **toàn bộ event** của user theo thứ tự thời gian + lọc `ga_session_number = 1`; `ga_session_number` chỉ có ở `evt_session_start` | thêm `ga_session_number` vào mọi bảng + tạo view `evt__all` = `UNION ALL` các `evt_*` (cột chung + `event_name`) |
| **New User Journey Event Reach (Session 1)** | "% người mới chạm tới từng event trong session đầu?" | như trên | như trên |
| **Minigame Session Analysis A / B** (start rate, playtime/session, sessions/user, revenue/eCPM per minigame) | "Minigame nào được chơi nhiều/bỏ nhiều? thời lượng session? doanh thu & eCPM từng minigame?" | định nghĩa session = cửa sổ giữa 2 `level_start`, cần **mọi event** có `current_screen = minigame_id` trong cửa sổ | tạo view `evt__all` (gộp `evt_level_start/level_end/checkpoint_reached/ad_impression/loading/enter_home/item_click` là đủ) |

**Tóm lại cần 2 thứ để mở khoá nhóm này:**
1. Thêm `ga_session_number` (STRING) — và tuỳ chọn `exp_variant` — vào danh sách cột chung trong `gen_layer2.py`.
2. Tạo view `obby1_layer2.evt__all` = `UNION ALL` cột chung + `event_name` của tất cả `evt_*`
   (thuần view, không tốn lưu trữ; query nó ≈ quét lại raw nhưng gọn hơn).

---

## 5. Cách chạy

```bash
cd "meta x - obby 1"
GUARD=C:/Users/Admin/.claude/scripts/bq_guard.py
CRED=suvival-master-obby-parkour-4265d3e9ea23.json

# chạy 1 query
python "$GUARD" layer2/sql/reusable/r3_funnel_monet_ltv.sql --creds "$CRED" --format json

# chỉnh input: sửa khối DECLARE ở đầu file trước khi chạy
```

Đối chiếu raw ↔ L2 (nếu cần verify lại): `_cmp_r3_raw_vs_l2.sql`, `_cmp_r8_raw_vs_l2.sql`.

## 6. Build thêm ngày cho L2 (để có số D1..D7)

```bash
python layer2/gen_layer2.py 20260902   # …tới 20260908
python "$GUARD" layer2/sql/_00_create_dataset.sql --creds "$CRED"
for f in layer2/sql/_[0-9][0-9]_evt_*.sql; do python "$GUARD" "$f" --creds "$CRED"; done
```
Bảng `PARTITION BY event_date` nên chạy ngày mới là ghi đè đúng partition, các query R3–R8
tự động có thêm dữ liệu, không cần sửa.
