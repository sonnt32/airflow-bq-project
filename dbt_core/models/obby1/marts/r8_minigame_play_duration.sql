-- R8 — Minigame Play Duration & Result Rate (win/lose/quit) per minigame x version
-- Xem PLAYBOOK.md (layer2/sql/reusable/) cho định nghĩa/verify đầy đủ.
-- Input qua dbt vars: versions
--   dbt run --select r8_minigame_play_duration --vars '{"versions": ["1.0.8","1.0.9"]}'

{{
  config(
    materialized = 'table',
    tags = ['obby1','minigame']
  )
}}

{%- set versions = var('versions', []) -%}


WITH
cohort AS (
  SELECT user_pseudo_id, app_version
  FROM {{ source('obby1_layer2', 'evt_first_open') }}
  WHERE ({{ versions | length }} = 0 OR app_version IN UNNEST({{ bq_array(versions) }}))
  GROUP BY 1, 2
),
level_start AS (
  SELECT c.app_version, ls.user_pseudo_id, ls.minigame_id
  FROM {{ source('obby1_layer2', 'evt_level_start') }} ls
  INNER JOIN cohort c USING (user_pseudo_id)
  WHERE ls.minigame_id IS NOT NULL AND ls.minigame_id != 'Home'
),
level_end AS (
  SELECT
    c.app_version,
    le.user_pseudo_id,
    le.minigame_id,
    le.result_by AS result,
    SAFE_CAST(le.play_duration AS FLOAT64) AS play_duration
  FROM {{ source('obby1_layer2', 'evt_level_end') }} le
  INNER JOIN cohort c USING (user_pseudo_id)
  WHERE le.minigame_id IS NOT NULL AND le.minigame_id != 'Home'
),
agg_start AS (
  SELECT app_version, minigame_id, COUNT(DISTINCT user_pseudo_id) AS users_start
  FROM level_start GROUP BY 1, 2
),
agg_end AS (
  SELECT
    app_version, minigame_id,
    COUNT(DISTINCT user_pseudo_id)                                   AS users_end,
    COUNT(result)                                                    AS total_end_count,
    COUNTIF(result = 'win')                                          AS win_count,
    COUNTIF(result = 'lose')                                         AS lose_count,
    COUNTIF(result = 'quit')                                         AS quit_count,
    SAFE_DIVIDE(SUM(play_duration), COUNT(DISTINCT user_pseudo_id))                     AS avg_duration_per_user_s,
    SAFE_DIVIDE(SUM(IF(result = 'win',  play_duration, NULL)),
                COUNT(DISTINCT IF(result = 'win',  user_pseudo_id, NULL)))              AS avg_duration_win_s,
    SAFE_DIVIDE(SUM(IF(result = 'lose', play_duration, NULL)),
                COUNT(DISTINCT IF(result = 'lose', user_pseudo_id, NULL)))              AS avg_duration_lose_s,
    SAFE_DIVIDE(SUM(IF(result = 'quit', play_duration, NULL)),
                COUNT(DISTINCT IF(result = 'quit', user_pseudo_id, NULL)))              AS avg_duration_quit_s
  FROM level_end GROUP BY 1, 2
)
SELECT
  s.app_version AS version,
  s.minigame_id,
  s.users_start,
  e.users_end,
  ROUND(e.users_end   * 100.0 / NULLIF(s.users_start, 0), 2)     AS complete_rate_pct,
  ROUND(e.win_count   * 100.0 / NULLIF(e.total_end_count, 0), 2) AS win_rate_pct,
  ROUND(e.lose_count  * 100.0 / NULLIF(e.total_end_count, 0), 2) AS lose_rate_pct,
  ROUND(e.quit_count  * 100.0 / NULLIF(e.total_end_count, 0), 2) AS quit_rate_pct,
  ROUND(e.avg_duration_per_user_s, 2) AS avg_duration_per_user_s,
  ROUND(e.avg_duration_win_s,  2)     AS avg_duration_win_s,
  ROUND(e.avg_duration_lose_s, 2)     AS avg_duration_lose_s,
  ROUND(e.avg_duration_quit_s, 2)     AS avg_duration_quit_s
FROM agg_start s
LEFT JOIN agg_end e USING (app_version, minigame_id)
ORDER BY version, s.users_start DESC
