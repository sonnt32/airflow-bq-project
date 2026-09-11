-- R5 — Daily Ad Monetization Dashboard
-- Xem PLAYBOOK.md (layer2/sql/reusable/) cho định nghĩa/verify đầy đủ.
-- Input qua dbt vars: versions, cohort_event
--   dbt run --select r5_daily_ad_monetization --vars '{"versions": ["1.0.8","1.0.9"]}'

{{
  config(
    materialized = 'table',
    tags = ['obby1','monetization']
  )
}}

{%- set versions = var('versions', []) -%}
{%- set cohort_event = var('cohort_event', 'first_open') -%}


WITH
-- version ổn định theo user (từ first_open)
user_version AS (
  SELECT user_pseudo_id, ANY_VALUE(app_version) AS app_version
  FROM {{ source('obby1_layer2', 'evt_first_open') }}
  GROUP BY 1
),
-- join_date của cohort
user_identity AS (
  SELECT user_pseudo_id, MIN(join_date) AS join_date
  FROM (
    SELECT user_pseudo_id, event_date AS join_date, app_version
    FROM {{ source('obby1_layer2', 'evt_first_open') }}    WHERE '{{ cohort_event }}' = 'first_open'
    UNION ALL
    SELECT user_pseudo_id, event_date AS join_date, app_version
    FROM {{ source('obby1_layer2', 'evt_session_start') }} WHERE '{{ cohort_event }}' = 'session_start'
  )
  WHERE ({{ versions | length }} = 0 OR app_version IN UNNEST({{ bq_array(versions) }}))
  GROUP BY 1
),
-- 1 dòng / user-ngày: cờ active + pivot ad theo format
daily_metrics AS (
  SELECT
    m.user_pseudo_id,
    m.log_date,
    MAX(m.is_active_today) AS is_active_today,
    COUNTIF(m.grp IS NOT NULL)                        AS total_imps,
    COUNTIF(m.grp = 'BANNER')                         AS b_imps,
    COUNTIF(m.grp = 'MREC')                           AS m_imps,
    COUNTIF(m.grp = 'INTER')                          AS i_imps,
    COUNTIF(m.grp = 'REWARDED')                       AS r_imps,
    SUM(IFNULL(m.rev, 0))                             AS total_rev,
    SUM(IF(m.grp = 'BANNER',   IFNULL(m.rev, 0), 0))  AS b_rev,
    SUM(IF(m.grp = 'MREC',     IFNULL(m.rev, 0), 0))  AS m_rev,
    SUM(IF(m.grp = 'INTER',    IFNULL(m.rev, 0), 0))  AS i_rev,
    SUM(IF(m.grp = 'REWARDED', IFNULL(m.rev, 0), 0))  AS r_rev,
    MAX(IF(m.grp IS NOT NULL,  1, 0))                 AS viewed_any,
    MAX(IF(m.grp = 'BANNER',   1, 0))                 AS v_b,
    MAX(IF(m.grp = 'MREC',     1, 0))                 AS v_m,
    MAX(IF(m.grp = 'INTER',    1, 0))                 AS v_i,
    MAX(IF(m.grp = 'REWARDED', 1, 0))                 AS v_r
  FROM (
    SELECT user_pseudo_id, event_date AS log_date, 1 AS is_active_today,
           CAST(NULL AS STRING) AS grp, CAST(NULL AS FLOAT64) AS rev
    FROM {{ source('obby1_layer2', 'evt_session_start') }}
    UNION ALL
    SELECT user_pseudo_id, event_date AS log_date, 0 AS is_active_today,
      CASE
        WHEN STARTS_WITH(UPPER(ad_format), 'BANNER')                                 THEN 'BANNER'
        WHEN STARTS_WITH(UPPER(ad_format), 'MREC') OR STARTS_WITH(UPPER(ad_format), 'MEDIUM_') THEN 'MREC'
        WHEN STARTS_WITH(UPPER(ad_format), 'INTER')                                  THEN 'INTER'
        WHEN STARTS_WITH(UPPER(ad_format), 'REWARD')                                 THEN 'REWARDED'
        ELSE 'OTHER'
      END AS grp,
      value AS rev
    FROM {{ source('obby1_layer2', 'evt_ad_impression') }}
  ) m
  GROUP BY 1, 2
),
joined_data AS (
  SELECT d.*, u.join_date
  FROM daily_metrics d
  INNER JOIN user_version  uv ON d.user_pseudo_id = uv.user_pseudo_id
  INNER JOIN user_identity u  ON d.user_pseudo_id = u.user_pseudo_id
  WHERE d.is_active_today = 1
    AND ({{ versions | length }} = 0 OR uv.app_version IN UNNEST({{ bq_array(versions) }}))
)
SELECT
  log_date AS date,
  COUNT(DISTINCT user_pseudo_id) AS active_user,
  ROUND(SUM(b_imps)     / COUNT(DISTINCT user_pseudo_id), 2) AS banner_imp_per_dau,
  ROUND(SUM(m_imps)     / COUNT(DISTINCT user_pseudo_id), 2) AS mrec_imp_per_dau,
  ROUND(SUM(i_imps)     / COUNT(DISTINCT user_pseudo_id), 2) AS inter_imp_per_dau,
  ROUND(SUM(r_imps)     / COUNT(DISTINCT user_pseudo_id), 3) AS reward_imp_per_dau,
  ROUND(SUM(total_imps) / COUNT(DISTINCT user_pseudo_id), 2) AS total_imp_per_dau,
  ROUND(SUM(v_b)        * 100.0 / COUNT(DISTINCT user_pseudo_id), 2) AS banner_viewer_rate,
  ROUND(SUM(v_m)        * 100.0 / COUNT(DISTINCT user_pseudo_id), 2) AS mrec_viewer_rate,
  ROUND(SUM(v_i)        * 100.0 / COUNT(DISTINCT user_pseudo_id), 2) AS inter_viewer_rate,
  ROUND(SUM(v_r)        * 100.0 / COUNT(DISTINCT user_pseudo_id), 2) AS reward_viewer_rate,
  ROUND(SUM(viewed_any) * 100.0 / COUNT(DISTINCT user_pseudo_id), 2) AS total_ad_viewer_rate,
  ROUND(SAFE_DIVIDE(SUM(b_rev), SUM(b_imps)) * 1000, 4) AS banner_ecpm,
  ROUND(SAFE_DIVIDE(SUM(m_rev), SUM(m_imps)) * 1000, 4) AS mrec_ecpm,
  ROUND(SAFE_DIVIDE(SUM(i_rev), SUM(i_imps)) * 1000, 4) AS inter_ecpm,
  ROUND(SAFE_DIVIDE(SUM(r_rev), SUM(r_imps)) * 1000, 4) AS reward_ecpm,
  ROUND(SUM(total_rev) / COUNT(DISTINCT user_pseudo_id), 6) AS arpdau,
  ROUND(
    COUNT(DISTINCT IF(DATE_DIFF(log_date, join_date, DAY) = 1, user_pseudo_id, NULL)) * 100.0 /
    NULLIF((SELECT COUNT(DISTINCT user_pseudo_id) FROM joined_data
            WHERE log_date = DATE_SUB(d.log_date, INTERVAL 1 DAY)
              AND DATE_DIFF(log_date, join_date, DAY) = 0), 0),
  2) AS cohort_rr_d1
FROM joined_data d
GROUP BY 1
ORDER BY date DESC
