-- R3 — New User Funnel Monetization + LTV D0/D3/D7
-- Xem PLAYBOOK.md (layer2_projects/obby1/sql/reusable/) cho định nghĩa/verify đầy đủ.
-- Input qua dbt vars: versions, exclude_geo
--   dbt run --select ob1_r3_funnel_monet_ltv --vars '{"versions": ["1.0.8","1.0.9"]}'

{{
  config(
    materialized = 'table',
    tags = ['obby1','monetization','ltv']
  )
}}

{%- set versions = var('versions', []) -%}
{%- set exclude_geo = var('exclude_geo', ['China']) -%}


WITH
-- L2-1: cohort user mới — version + join_date + country lấy từ bảng context evt_first_open
user_identity AS (
  SELECT
    user_pseudo_id,
    app_version,
    MIN(event_date) AS join_date
  FROM {{ source('obby1_layer2', 'evt_first_open') }}
  WHERE ({{ versions | length }} = 0 OR app_version IN UNNEST({{ bq_array(versions) }}))
    AND geo_country NOT IN UNNEST({{ bq_array(exclude_geo) }})
  GROUP BY 1, 2
),

-- L2-2: user active theo ngày = có dòng trong evt_session_start
daily_active AS (
  SELECT DISTINCT user_pseudo_id, app_version, event_date AS log_date
  FROM {{ source('obby1_layer2', 'evt_session_start') }}
  WHERE ({{ versions | length }} = 0 OR app_version IN UNNEST({{ bq_array(versions) }}))
),

-- L2-3: ad_impression chuẩn hoá ad_format (version thừa hưởng từ cohort)
ad_events_normalized AS (
  SELECT
    ai.user_pseudo_id,
    u.app_version,
    ai.event_date AS log_date,
    ai.value      AS imp_revenue,
    CASE
      WHEN STARTS_WITH(UPPER(ai.ad_format), 'BANNER')                                   THEN 'BANNER'
      WHEN STARTS_WITH(UPPER(ai.ad_format), 'MREC')
        OR STARTS_WITH(UPPER(ai.ad_format), 'MEDIUM_')                                  THEN 'MREC'
      WHEN STARTS_WITH(UPPER(ai.ad_format), 'INTER')                                    THEN 'INTER'
      WHEN STARTS_WITH(UPPER(ai.ad_format), 'REWARD')                                   THEN 'REWARDED'
      ELSE 'OTHER'
    END AS ad_format_group
  FROM {{ source('obby1_layer2', 'evt_ad_impression') }} ai
  INNER JOIN user_identity u USING (user_pseudo_id)
),

daily_ad_metrics AS (
  SELECT
    log_date, app_version, user_pseudo_id,
    COUNT(*)                                            AS total_imps,
    COUNTIF(ad_format_group = 'BANNER')                 AS b_imps,
    COUNTIF(ad_format_group = 'MREC')                   AS m_imps,
    COUNTIF(ad_format_group = 'INTER')                  AS i_imps,
    COUNTIF(ad_format_group = 'REWARDED')               AS r_imps,
    SUM(imp_revenue)                                    AS total_rev,
    SUM(IF(ad_format_group = 'BANNER',   imp_revenue, 0)) AS b_rev,
    SUM(IF(ad_format_group = 'MREC',     imp_revenue, 0)) AS m_rev,
    SUM(IF(ad_format_group = 'INTER',    imp_revenue, 0)) AS i_rev,
    SUM(IF(ad_format_group = 'REWARDED', imp_revenue, 0)) AS r_rev,
    MAX(1)                                              AS viewed_any,
    MAX(IF(ad_format_group = 'BANNER',   1, 0))         AS v_b,
    MAX(IF(ad_format_group = 'MREC',     1, 0))         AS v_m,
    MAX(IF(ad_format_group = 'INTER',    1, 0))         AS v_i,
    MAX(IF(ad_format_group = 'REWARDED', 1, 0))         AS v_r
  FROM ad_events_normalized
  GROUP BY 1, 2, 3
),

joined_data AS (
  SELECT
    da.log_date, da.app_version, da.user_pseudo_id, u.join_date,
    COALESCE(a.total_imps, 0) AS total_imps,
    COALESCE(a.b_imps, 0) AS b_imps, COALESCE(a.m_imps, 0) AS m_imps,
    COALESCE(a.i_imps, 0) AS i_imps, COALESCE(a.r_imps, 0) AS r_imps,
    COALESCE(a.total_rev, 0) AS total_rev,
    COALESCE(a.b_rev, 0) AS b_rev, COALESCE(a.m_rev, 0) AS m_rev,
    COALESCE(a.i_rev, 0) AS i_rev, COALESCE(a.r_rev, 0) AS r_rev,
    COALESCE(a.viewed_any, 0) AS viewed_any,
    COALESCE(a.v_b, 0) AS v_b, COALESCE(a.v_m, 0) AS v_m,
    COALESCE(a.v_i, 0) AS v_i, COALESCE(a.v_r, 0) AS v_r
  FROM daily_active da
  INNER JOIN user_identity u
    ON da.user_pseudo_id = u.user_pseudo_id AND da.app_version = u.app_version
  LEFT JOIN daily_ad_metrics a
    ON da.log_date = a.log_date AND da.app_version = a.app_version
   AND da.user_pseudo_id = a.user_pseudo_id
),

daily_agg AS (
  SELECT
    log_date, app_version,
    COUNT(DISTINCT user_pseudo_id)                                 AS dau,
    COUNT(DISTINCT IF(join_date = log_date, user_pseudo_id, NULL)) AS new_users,
    SUM(total_imps) AS total_imps, SUM(b_imps) AS b_imps, SUM(m_imps) AS m_imps,
    SUM(i_imps) AS i_imps, SUM(r_imps) AS r_imps,
    SUM(total_rev) AS total_rev, SUM(b_rev) AS b_rev, SUM(m_rev) AS m_rev,
    SUM(i_rev) AS i_rev, SUM(r_rev) AS r_rev,
    SUM(viewed_any) AS viewers_any, SUM(v_b) AS viewers_b, SUM(v_m) AS viewers_m,
    SUM(v_i) AS viewers_i, SUM(v_r) AS viewers_r
  FROM joined_data
  GROUP BY 1, 2
),

cohort_size AS (
  SELECT app_version, join_date, COUNT(DISTINCT user_pseudo_id) AS new_users
  FROM user_identity GROUP BY 1, 2
),

-- LTV: doanh thu ad theo user-ngày (L2 hiện chỉ có cohort_day = 0)
daily_revenue AS (
  SELECT ai.user_pseudo_id, ai.event_date AS log_date, SUM(ai.value) AS daily_rev
  FROM {{ source('obby1_layer2', 'evt_ad_impression') }} ai
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
    SAFE_DIVIDE(SUM(IF(r.cohort_day = 0,             r.daily_rev, 0)), c.new_users) AS ltv_d0,
    SAFE_DIVIDE(SUM(IF(r.cohort_day BETWEEN 0 AND 3, r.daily_rev, 0)), c.new_users) AS ltv_d3,
    SAFE_DIVIDE(SUM(IF(r.cohort_day BETWEEN 0 AND 7, r.daily_rev, 0)), c.new_users) AS ltv_d7
  FROM user_identity u
  INNER JOIN cohort_size c
    ON u.app_version = c.app_version AND u.join_date = c.join_date
  LEFT JOIN user_cohort_day_rev r
    ON u.user_pseudo_id = r.user_pseudo_id
   AND u.join_date      = r.join_date
   AND u.app_version    = r.app_version
  GROUP BY 1, 2, c.new_users
),

ltv_agg AS (
  SELECT
    app_version,
    ROUND(AVG(ltv_d0), 6) AS avg_ltv_d0,
    ROUND(AVG(ltv_d3), 6) AS avg_ltv_d3,
    ROUND(AVG(ltv_d7), 6) AS avg_ltv_d7
  FROM ltv_per_cohort
  GROUP BY 1
)

SELECT
  f.app_version                                                    AS version,
  MIN(f.log_date)                                                  AS date_from,
  MAX(f.log_date)                                                  AS date_to,
  COUNT(DISTINCT f.log_date)                                       AS num_days,
  ROUND(AVG(f.dau), 1)                                             AS avg_dau,
  ROUND(AVG(f.new_users), 1)                                       AS avg_new_users,

  ROUND(AVG(f.total_imps / NULLIF(f.dau, 0)), 2)                   AS total_imp_per_dau,
  ROUND(AVG(f.b_imps     / NULLIF(f.dau, 0)), 2)                   AS banner_imp_per_dau,
  ROUND(AVG(f.m_imps     / NULLIF(f.dau, 0)), 2)                   AS mrec_imp_per_dau,
  ROUND(AVG(f.i_imps     / NULLIF(f.dau, 0)), 2)                   AS inter_imp_per_dau,
  ROUND(AVG(f.r_imps     / NULLIF(f.dau, 0)), 3)                   AS reward_imp_per_dau,

  ROUND(AVG(f.viewers_any * 100.0 / NULLIF(f.dau, 0)), 2)          AS ad_viewer_rate,
  ROUND(AVG(f.viewers_b   * 100.0 / NULLIF(f.dau, 0)), 2)          AS banner_viewer_rate,
  ROUND(AVG(f.viewers_m   * 100.0 / NULLIF(f.dau, 0)), 2)          AS mrec_viewer_rate,
  ROUND(AVG(f.viewers_i   * 100.0 / NULLIF(f.dau, 0)), 2)          AS inter_viewer_rate,
  ROUND(AVG(f.viewers_r   * 100.0 / NULLIF(f.dau, 0)), 2)          AS reward_viewer_rate,

  ROUND(AVG(f.total_rev / NULLIF(f.dau, 0)), 6)                    AS arpdau,

  ROUND(SAFE_DIVIDE(SUM(f.total_rev), SUM(f.total_imps)) * 1000, 4) AS ecpm,
  ROUND(SAFE_DIVIDE(SUM(f.b_rev),     SUM(f.b_imps))     * 1000, 4) AS banner_ecpm,
  ROUND(SAFE_DIVIDE(SUM(f.m_rev),     SUM(f.m_imps))     * 1000, 4) AS mrec_ecpm,
  ROUND(SAFE_DIVIDE(SUM(f.i_rev),     SUM(f.i_imps))     * 1000, 4) AS inter_ecpm,
  ROUND(SAFE_DIVIDE(SUM(f.r_rev),     SUM(f.r_imps))     * 1000, 4) AS reward_ecpm,

  ANY_VALUE(l.avg_ltv_d0)                                          AS ltv_d0,
  ANY_VALUE(l.avg_ltv_d3)                                          AS ltv_d3,   -- = d0 khi L2 chỉ có 1 ngày
  ANY_VALUE(l.avg_ltv_d7)                                          AS ltv_d7    -- = d0 khi L2 chỉ có 1 ngày

FROM daily_agg f
LEFT JOIN ltv_agg l ON f.app_version = l.app_version
GROUP BY 1
ORDER BY 1
