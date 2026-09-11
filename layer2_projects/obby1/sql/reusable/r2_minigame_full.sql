-- ============================================================
-- [R2] Minigame Analysis — bảng đầy đủ per-minigame × version   (chạy trên LAYER 2)
--   Start User | Start Rate % | Unique Users | Total Sessions | Avg Playtime/User | Avg Playtime/Session
--   | Total Ad Impressions | Total Revenue ($) | Avg Revenue/User ($) | eCPM
-- Nguồn raw: memory skills.md "Minigame Analysis — Query B".
--
-- KHÁC raw:
--   - Bỏ EXECUTE IMMEDIATE / _TABLE_SUFFIX / var_dataset_path.
--   - L2 không có bảng event gộp => `base` = UNION ALL 29 bảng evt_* (trừ evt_app_remove),
--     proj về (user_pseudo_id, event_name, event_timestamp, current_screen, minigame_id, imp_value).
--   - `version` không nằm trên bảng event => lấy per-user từ evt_session_start (ANY_VALUE).
--     ⚠️ user có level_start nhưng KHÔNG có session_start trong ngày sẽ bị loại
--        (20260901: 47/11055 user ≈ 0.4%). Raw lấy app_info.version từng dòng nên giữ hết
--        + tách được user đổi version giữa ngày.
--     ==> VERIFY (version 1.0.8, 20260901): mọi cột L2 thấp hơn raw ~0.4–0.8%, cùng chiều,
--         đúng bằng phần 47 user bị rớt. Muốn khớp tuyệt đối: thêm cột app_version vào
--         mọi bảng trong gen_layer2.py.
--   - `imp_value` = cột `value` FLOAT64 sẵn của evt_ad_impression (khỏi bóc event_params).
--   - `value.string_value 'current_Screen'` -> cột `current_screen` (mọi bảng đã có).
--   - Nếu chạy nhóm session-analysis nhiều lần: cân nhắc tạo VIEW `obby1_layer2.evt__all`
--     = đúng khối UNION này, rồi `FROM evt__all` cho gọn.
-- L2 hiện chỉ có 20260901 => "kỳ" = 1 ngày.
-- ============================================================
DECLARE var_versions        ARRAY<STRING> DEFAULT [];   -- rỗng = mọi version
DECLARE var_max_session_min FLOAT64       DEFAULT 20;    -- ngưỡng loại session bất thường (phút)

WITH
user_version AS (
  SELECT user_pseudo_id, ANY_VALUE(app_version) AS version
  FROM `obby1_layer2.evt_session_start`
  GROUP BY 1
),
base_raw AS (
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, value AS imp_value FROM `obby1_layer2.evt_ad_impression`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_ad_request_failed`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_ad_request_success`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_ad_reward`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_ad_show_complete`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_ad_show_failed`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_ad_start_show`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_app_exception`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_app_request_show_ad`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_app_update`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_checkpoint_reached`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_click_change_outfit_button`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_click_quest_button`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_click_shop_button`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_enter_home`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_enter_survival_mode_lobby`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_exit_survival_mode_lobby`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_firebase_campaign`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_first_open`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_item_click`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_level_end`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_level_start`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_loading`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_mode_clicked`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_os_update`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_session_start`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_survial_session_end`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_survial_session_start`
  UNION ALL
  SELECT user_pseudo_id, event_name, event_timestamp, current_screen, CAST(NULL AS STRING) AS minigame_id, CAST(NULL AS FLOAT64) AS imp_value FROM `obby1_layer2.evt_user_engagement`
),
base AS (
  SELECT
    b.user_pseudo_id,
    uv.version,
    b.event_name,
    b.event_timestamp,
    b.minigame_id,
    b.current_screen,
    b.imp_value
  FROM base_raw b
  INNER JOIN user_version uv USING (user_pseudo_id)
  WHERE (ARRAY_LENGTH(var_versions) = 0 OR uv.version IN UNNEST(var_versions))
),
starts_raw AS (   -- mọi level_start (giữ 'Home' để tính total_user)
  SELECT version, user_pseudo_id, minigame_id
  FROM base
  WHERE event_name = 'level_start' AND minigame_id IS NOT NULL
),
total_user AS (
  SELECT version, COUNT(DISTINCT user_pseudo_id) AS total_user
  FROM starts_raw GROUP BY version
),
mg_start_users AS (
  SELECT version, minigame_id, COUNT(DISTINCT user_pseudo_id) AS start_user
  FROM starts_raw WHERE minigame_id != 'Home'
  GROUP BY version, minigame_id
),
level_starts AS (
  SELECT version, user_pseudo_id, minigame_id, event_timestamp AS start_ts,
    ROW_NUMBER() OVER (PARTITION BY version, user_pseudo_id, minigame_id ORDER BY event_timestamp) AS si
  FROM base
  WHERE event_name = 'level_start' AND minigame_id IS NOT NULL AND minigame_id != 'Home'
),
ls_next AS (
  SELECT *, LEAD(start_ts) OVER (PARTITION BY version, user_pseudo_id, minigame_id ORDER BY start_ts) AS next_start_ts
  FROM level_starts
),
sess_events AS (
  SELECT ls.version, ls.user_pseudo_id, ls.minigame_id, ls.si, ls.start_ts,
    b.event_name, b.event_timestamp AS event_ts, b.imp_value
  FROM ls_next ls
  JOIN base b
    ON  b.version         = ls.version
    AND b.user_pseudo_id  = ls.user_pseudo_id
    AND b.current_screen  = ls.minigame_id
    AND b.event_timestamp >= ls.start_ts
    AND b.event_timestamp <  COALESCE(ls.next_start_ts, b.event_timestamp + 1)
),
sess_end AS (
  SELECT version, user_pseudo_id, minigame_id, si, start_ts, MAX(event_ts) AS last_ts
  FROM sess_events
  GROUP BY version, user_pseudo_id, minigame_id, si, start_ts
),
sess_valid AS (
  SELECT version, user_pseudo_id, minigame_id, si,
    ROUND((last_ts - start_ts) / 1e6 / 60, 4) AS duration_min
  FROM sess_end
  WHERE (last_ts - start_ts) / 1e6 / 60 <= var_max_session_min
),
play_agg AS (
  SELECT version, minigame_id,
    COUNT(DISTINCT user_pseudo_id) AS unique_users,
    COUNT(*)                       AS total_sessions,
    SUM(duration_min)              AS total_playtime_min
  FROM sess_valid
  GROUP BY version, minigame_id
),
ad_agg AS (
  SELECT se.version, se.minigame_id,
    COUNTIF(se.event_name = 'ad_impression')                              AS total_impressions,
    SUM(IF(se.event_name = 'ad_impression', IFNULL(se.imp_value, 0), 0))  AS total_revenue
  FROM sess_events se
  JOIN sess_valid v USING (version, user_pseudo_id, minigame_id, si)
  GROUP BY se.version, se.minigame_id
)
SELECT
  s.version,
  s.minigame_id,
  s.start_user,
  ROUND(SAFE_DIVIDE(s.start_user, t.total_user) * 100, 2)      AS start_rate_pct,
  p.unique_users,
  p.total_sessions,
  ROUND(SAFE_DIVIDE(p.total_playtime_min, p.unique_users),   2) AS avg_playtime_per_user_min,
  ROUND(SAFE_DIVIDE(p.total_playtime_min, p.total_sessions), 2) AS avg_playtime_per_session_min,
  IFNULL(a.total_impressions, 0)                               AS total_ad_impressions,
  ROUND(IFNULL(a.total_revenue, 0), 2)                         AS total_revenue_usd,
  ROUND(SAFE_DIVIDE(IFNULL(a.total_revenue, 0), p.unique_users), 4)             AS avg_revenue_per_user_usd,
  ROUND(SAFE_DIVIDE(IFNULL(a.total_revenue, 0), a.total_impressions) * 1000, 2) AS ecpm
FROM mg_start_users s
JOIN      total_user t ON t.version = s.version
LEFT JOIN play_agg   p ON p.version = s.version AND p.minigame_id = s.minigame_id
LEFT JOIN ad_agg     a ON a.version = s.version AND a.minigame_id = s.minigame_id
ORDER BY s.version, s.start_user DESC;
