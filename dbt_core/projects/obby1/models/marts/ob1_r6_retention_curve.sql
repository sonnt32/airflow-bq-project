-- R6 — Retention Curve D1-D7 theo cohort_date
-- Xem PLAYBOOK.md (layer2_projects/obby1/sql/reusable/) cho định nghĩa/verify đầy đủ.
-- Input qua dbt vars: versions
--   dbt run --select ob1_r6_retention_curve --vars '{"versions": ["1.0.8","1.0.9"]}'

{{
  config(
    materialized = 'table',
    tags = ['obby1','retention']
  )
}}

{%- set versions = var('versions', []) -%}


WITH
user_identity AS (
  SELECT user_pseudo_id, app_version, MIN(event_date) AS join_date
  FROM {{ source('obby1_layer2', 'evt_first_open') }}
  WHERE ({{ versions | length }} = 0 OR app_version IN UNNEST({{ bq_array(versions) }}))
  GROUP BY 1, 2
),
cohort_size AS (
  SELECT app_version, join_date, COUNT(DISTINCT user_pseudo_id) AS new_users
  FROM user_identity GROUP BY 1, 2
),
daily_activity AS (
  SELECT DISTINCT user_pseudo_id, event_date AS active_date
  FROM {{ source('obby1_layer2', 'evt_session_start') }}
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
ORDER BY 1, 2
