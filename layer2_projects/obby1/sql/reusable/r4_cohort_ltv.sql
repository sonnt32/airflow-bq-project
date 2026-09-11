-- ============================================================
-- [R4] New User Cohort LTV — D0 / D1 / D3 / D7   (chạy trên LAYER 2)
-- Nguồn raw: memory skills.md "Thống kê về LTV của dự án"
-- KHÁC raw: bỏ EXECUTE IMMEDIATE / _TABLE_SUFFIX; version lấy từ evt_first_open.
--   L2 hiện chỉ có 20260901 => chỉ cohort_day 0 => ltv_d1=d3=d7=ltv_d0.
-- ============================================================
DECLARE var_versions    ARRAY<STRING> DEFAULT [];          -- rỗng = mọi version
DECLARE var_exclude_geo ARRAY<STRING> DEFAULT ['China'];

WITH
user_identity AS (
  SELECT user_pseudo_id, app_version, MIN(event_date) AS join_date
  FROM `obby1_layer2.evt_first_open`
  WHERE (ARRAY_LENGTH(var_versions) = 0 OR app_version IN UNNEST(var_versions))
    AND geo_country NOT IN UNNEST(var_exclude_geo)
  GROUP BY 1, 2
),
cohort_size AS (
  SELECT app_version, join_date, COUNT(DISTINCT user_pseudo_id) AS new_users
  FROM user_identity GROUP BY 1, 2
),
daily_revenue AS (
  SELECT ai.user_pseudo_id, ai.event_date AS log_date, SUM(ai.value) AS daily_rev
  FROM `obby1_layer2.evt_ad_impression` ai
  INNER JOIN user_identity u USING (user_pseudo_id)
  GROUP BY 1, 2
),
user_cohort_day_rev AS (
  SELECT
    r.user_pseudo_id, u.app_version, u.join_date,
    DATE_DIFF(r.log_date, u.join_date, DAY) AS cohort_day,
    r.daily_rev
  FROM daily_revenue r
  INNER JOIN user_identity u USING (user_pseudo_id)
  WHERE DATE_DIFF(r.log_date, u.join_date, DAY) BETWEEN 0 AND 7
),
ltv_per_cohort AS (
  SELECT
    u.app_version,
    u.join_date AS cohort_date,
    SUM(IF(r.cohort_day = 0,             r.daily_rev, 0)) AS rev_d0,
    SUM(IF(r.cohort_day BETWEEN 0 AND 1, r.daily_rev, 0)) AS rev_d1,
    SUM(IF(r.cohort_day BETWEEN 0 AND 3, r.daily_rev, 0)) AS rev_d3,
    SUM(IF(r.cohort_day BETWEEN 0 AND 7, r.daily_rev, 0)) AS rev_d7
  FROM user_identity u
  LEFT JOIN user_cohort_day_rev r
    ON  u.user_pseudo_id = r.user_pseudo_id
    AND u.join_date      = r.join_date
    AND u.app_version    = r.app_version
  GROUP BY 1, 2
)
SELECT
  l.app_version AS version,
  l.cohort_date,
  c.new_users,
  ROUND(SAFE_DIVIDE(l.rev_d0, c.new_users), 6) AS ltv_d0,
  ROUND(SAFE_DIVIDE(l.rev_d1, c.new_users), 6) AS ltv_d1,
  ROUND(SAFE_DIVIDE(l.rev_d3, c.new_users), 6) AS ltv_d3,
  ROUND(SAFE_DIVIDE(l.rev_d7, c.new_users), 6) AS ltv_d7,
  DATE_DIFF(CURRENT_DATE(), l.cohort_date, DAY) >= 7 AS is_d7_mature
FROM ltv_per_cohort l
INNER JOIN cohort_size c
  ON l.cohort_date = c.join_date AND l.app_version = c.app_version
ORDER BY 1, 2;
