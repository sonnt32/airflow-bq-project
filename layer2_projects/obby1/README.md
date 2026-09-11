# Layer 2 — Obby 1 (per-event tables)

Project `suvival-master-obby-parkour` · dataset `obby1_layer2` · location US

## Kiến trúc 3 lớp

| Lớp | Vị trí | Trạng thái |
|---|---|---|
| L1 raw | `analytics_505759684.events_*` (GA4 export) | có sẵn |
| **L2 per-event** | **`obby1_layer2.evt_<event_name>`** | **file này** |
| L3 view Looker | *(chưa làm)* | sau |

## Quyết định thiết kế

- **1 event = 1 bảng**, data-driven: tách theo event **thực tế có trong data**, không theo
  tracking plan JSON (file `event tracking metax minigame.json` là spec của game ClimbJump,
  không khớp game này).
- **Không surrogate key.** Join giữa các bảng qua `user_pseudo_id` (+ `ga_session_id` khi
  cần đúng context theo session).
- **Không lặp cột user/device/geo/app.** Chỉ 2 bảng context `evt_first_open` và
  `evt_session_start` mang các cột đó. Bảng event khác join ngược về đây.
- Cột chung mọi bảng: `user_pseudo_id`, `user_id`, `event_name`, `event_date`,
  `event_timestamp` (micros), `event_ts` (TIMESTAMP), `ga_session_id`, `current_screen`.
  - `user_id` hiện **NULL 100%** (game chưa set) — giữ cột để tương thích sau.
  - `current_screen` lấy từ user_property `current_Screen`.
- **Param**: mỗi param riêng của event → 1 cột, value đã ép kiểu.
  - param số / enum / thời gian → `STRING` (Data Foundation v1.1)
  - param doanh thu (`value`, `reward_value`) → `FLOAT64`
  - param GA4 plumbing (`firebase_*`, `engaged_session_event`, `ga_session_number`,
    `debug_event`, `session_engaged`) → **loại** (trừ `ga_session_number` giữ ở bảng context)
  - param ngoài danh sách → **bỏ**
- Bảng `PARTITION BY event_date` để chạy thêm ngày là append được.

## 30 bảng (ngày 20260901)

context: `evt_first_open`, `evt_session_start`
gameplay: `evt_level_start`, `evt_level_end`, `evt_checkpoint_reached`, `evt_loading`,
  `evt_enter_home`, `evt_mode_clicked`, `evt_enter_survival_mode_lobby`,
  `evt_exit_survival_mode_lobby`, `evt_survial_session_start`, `evt_survial_session_end`
ui: `evt_item_click`, `evt_click_change_outfit_button`, `evt_click_shop_button`,
  `evt_click_quest_button`
ad funnel: `evt_app_request_show_ad`, `evt_ad_start_show`, `evt_ad_show_complete`,
  `evt_ad_show_failed`, `evt_ad_request_success`, `evt_ad_request_failed`, `evt_ad_reward`,
  `evt_ad_impression`
lifecycle/auto: `evt_user_engagement`, `evt_app_remove`, `evt_firebase_campaign`,
  `evt_app_exception`, `evt_os_update`, `evt_app_update`

## Chạy lại / chạy ngày khác

```bash
cd "meta x - obby 1"
python layer2/gen_layer2.py 20260902          # sinh lại layer2/sql/
GUARD=C:/Users/Admin/.claude/scripts/bq_guard.py
CRED=suvival-master-obby-parkour-4265d3e9ea23.json
python "$GUARD" layer2/sql/_00_create_dataset.sql --creds "$CRED"
for f in layer2/sql/_[0-9][0-9]_evt_*.sql; do python "$GUARD" "$f" --creds "$CRED"; done
```

Sửa danh sách event / param trong `layer2/gen_layer2.py` (dict `EVENTS`).

## Query mẫu tái sử dụng (transform từ `memory skills.md`)

`layer2/sql/reusable/reusable_LAYER2.sql` — 4 khối, mỗi khối chạy riêng:

| Khối | Nội dung | Verify |
|---|---|---|
| R4 | New User Cohort LTV D0/D1/D3/D7 | ✅ khớp RAW |
| R5 | Daily Ad Monetization (imp/DAU, viewer rate, eCPM, ARPDAU) | ✅ eCPM khớp RAW; active = `session_start` |
| R6 | Retention Curve D1–D7 | cấu trúc OK (cần build thêm ngày mới ra số) |
| R8 | Minigame Play Duration & Result Rate (theo `minigame_id`) | ✅ khớp RAW |

Chưa chuyển được (cần đổi schema L2): A/B Test (thiếu cột experiment variant), Sankey / Event Reach Session-1 và Minigame Session Analysis (cần `ga_session_number` mọi bảng + 1 view gộp event `evt__all`).

## Ví dụ query (join context)

```sql
SELECT le.*, ss.geo_country, ss.device_os, ss.app_version
FROM `obby1_layer2.evt_level_end` le
LEFT JOIN `obby1_layer2.evt_session_start` ss
  USING (user_pseudo_id, ga_session_id);
```
