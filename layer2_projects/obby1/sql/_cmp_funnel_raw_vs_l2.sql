-- So sánh RAW vs LAYER 2 cho cohort first_open ngày 20260901 (loại China)
-- Muc dich: chung minh L2 cho ket qua tuong duong raw (cot funnel/monet + ltv_d0)
DECLARE d STRING DEFAULT '20260901';

WITH
-- ---------- RAW ----------
raw_cohort AS (
  SELECT user_pseudo_id, app_info.version AS v
  FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901`
  WHERE event_name = 'first_open' AND geo.country NOT IN ('China')
  GROUP BY 1, 2
),
raw_ss AS (
  SELECT DISTINCT user_pseudo_id, app_info.version AS v
  FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901`
  WHERE event_name = 'session_start'
),
raw_ai AS (
  SELECT user_pseudo_id,
         COUNT(*) AS imps,
         SUM((SELECT value.double_value FROM UNNEST(event_params) WHERE key = 'value')) AS rev
  FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901`
  WHERE event_name = 'ad_impression'
  GROUP BY 1
),
raw_out AS (
  SELECT
    'RAW' AS src, c.v AS version,
    COUNT(DISTINCT c.user_pseudo_id)                               AS new_users,
    COUNT(DISTINCT s.user_pseudo_id)                               AS dau,
    SUM(COALESCE(a.imps, 0))                                       AS total_imps,
    ROUND(SUM(COALESCE(a.rev, 0)), 6)                              AS total_rev,
    ROUND(SAFE_DIVIDE(SUM(a.rev), SUM(a.imps)) * 1000, 4)          AS ecpm,
    ROUND(SAFE_DIVIDE(SUM(COALESCE(a.rev, 0)),
                      COUNT(DISTINCT c.user_pseudo_id)), 6)        AS ltv_d0
  FROM raw_cohort c
  LEFT JOIN raw_ss s ON c.user_pseudo_id = s.user_pseudo_id AND c.v = s.v
  LEFT JOIN raw_ai a ON c.user_pseudo_id = a.user_pseudo_id
  GROUP BY 1, 2
),

-- ---------- LAYER 2 ----------
l2_cohort AS (
  SELECT user_pseudo_id, app_version AS v
  FROM `obby1_layer2.evt_first_open`
  WHERE geo_country NOT IN ('China')
  GROUP BY 1, 2
),
l2_ss AS (
  SELECT DISTINCT user_pseudo_id, app_version AS v
  FROM `obby1_layer2.evt_session_start`
),
l2_ai AS (
  SELECT user_pseudo_id, COUNT(*) AS imps, SUM(value) AS rev
  FROM `obby1_layer2.evt_ad_impression`
  GROUP BY 1
),
l2_out AS (
  SELECT
    'L2' AS src, c.v AS version,
    COUNT(DISTINCT c.user_pseudo_id)                               AS new_users,
    COUNT(DISTINCT s.user_pseudo_id)                               AS dau,
    SUM(COALESCE(a.imps, 0))                                       AS total_imps,
    ROUND(SUM(COALESCE(a.rev, 0)), 6)                              AS total_rev,
    ROUND(SAFE_DIVIDE(SUM(a.rev), SUM(a.imps)) * 1000, 4)          AS ecpm,
    ROUND(SAFE_DIVIDE(SUM(COALESCE(a.rev, 0)),
                      COUNT(DISTINCT c.user_pseudo_id)), 6)        AS ltv_d0
  FROM l2_cohort c
  LEFT JOIN l2_ss s ON c.user_pseudo_id = s.user_pseudo_id AND c.v = s.v
  LEFT JOIN l2_ai a ON c.user_pseudo_id = a.user_pseudo_id
  GROUP BY 1, 2
)

SELECT * FROM raw_out
UNION ALL
SELECT * FROM l2_out
ORDER BY version, src;
