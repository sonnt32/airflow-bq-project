-- ============================================================
-- [R6] Retention Curve D1–D7 theo từng Cohort Date   (chạy trên LAYER 2)
-- Nguồn raw: memory skills.md "Thống kê về Retention Cohort Analysis"
-- KHÁC raw: bỏ EXECUTE IMMEDIATE / _TABLE_SUFFIX; version từ evt_first_open.
--   >>> L2 hiện chỉ có 20260901 => D1..D7 đều 0 (chưa có ngày sau).
--       Build L2 cho 20260901..20260908 để ra số thật.
-- ============================================================
DECLARE var_versions ARRAY<STRING> DEFAULT [];   -- rỗng = mọi version

WITH
user_identity AS (
  SELECT user_pseudo_id, app_version, MIN(event_date) AS join_date
  FROM `obby1_layer2.evt_first_open`
  WHERE (ARRAY_LENGTH(var_versions) = 0 OR app_version IN UNNEST(var_versions))
  GROUP BY 1, 2
),
cohort_size AS (
  SELECT app_version, join_date, COUNT(DISTINCT user_pseudo_id) AS new_users
  FROM user_identity GROUP BY 1, 2
),
daily_activity AS (
  SELECT DISTINCT user_pseudo_id, event_date AS active_date
  FROM `obby1_layer2.evt_session_start`
),
user_cohort_activity AS (
  SELECT
    u.app_version, u.join_date, a.user_pseudo_id,
    DATE_DIFF(a.active_date, u.join_date, DAY) AS cohort_day
  FROM user_identity u
  INNER JOIN daily_activity a USING (user_pseudo_id)
  WHERE DATE_DIFF(a.active_date, u.join_date, DAY) BETWEEN 1 AND 7
),
retention_pivot AS (
  SELECT
    app_version, join_date,
    COUNT(DISTINCT IF(cohort_day = 1, user_pseudo_id, NULL)) AS d1_active,
    COUNT(DISTINCT IF(cohort_day = 2, user_pseudo_id, NULL)) AS d2_active,
    COUNT(DISTINCT IF(cohort_day = 3, user_pseudo_id, NULL)) AS d3_active,
    COUNT(DISTINCT IF(cohort_day = 4, user_pseudo_id, NULL)) AS d4_active,
    COUNT(DISTINCT IF(cohort_day = 5, user_pseudo_id, NULL)) AS d5_active,
    COUNT(DISTINCT IF(cohort_day = 6, user_pseudo_id, NULL)) AS d6_active,
    COUNT(DISTINCT IF(cohort_day = 7, user_pseudo_id, NULL)) AS d7_active
  FROM user_cohort_activity
  GROUP BY 1, 2
)
SELECT
  c.app_version AS version,
  c.join_date   AS cohort_date,
  c.new_users,
  ROUND(SAFE_DIVIDE(r.d1_active, c.new_users) * 100, 2) AS d1_retention,
  ROUND(SAFE_DIVIDE(r.d2_active, c.new_users) * 100, 2) AS d2_retention,
  ROUND(SAFE_DIVIDE(r.d3_active, c.new_users) * 100, 2) AS d3_retention,
  ROUND(SAFE_DIVIDE(r.d4_active, c.new_users) * 100, 2) AS d4_retention,
  ROUND(SAFE_DIVIDE(r.d5_active, c.new_users) * 100, 2) AS d5_retention,
  ROUND(SAFE_DIVIDE(r.d6_active, c.new_users) * 100, 2) AS d6_retention,
  ROUND(SAFE_DIVIDE(r.d7_active, c.new_users) * 100, 2) AS d7_retention,
  DATE_DIFF(CURRENT_DATE(), c.join_date, DAY) >= 7 AS is_d7_mature
FROM cohort_size c
LEFT JOIN retention_pivot r
  ON c.join_date = r.join_date AND c.app_version = r.app_version
ORDER BY 1, 2;
