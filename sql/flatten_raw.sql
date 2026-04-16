CREATE TABLE IF NOT EXISTS `annoying-puzzle.stg.event_flatten_raw`
(
  event_date DATE,
  event_timestamp INT64,
  event_name STRING,
  user_pseudo_id STRING,
  platform STRING,
  app_version STRING,
  device_mobile_marketing_name STRING,
  device_mobile_model_name STRING,
  device_operating_system_version STRING,
  language STRING,
  country STRING,
  city STRING,
  continent STRING,
  current_level INT64,
  first_open_date DATE,
  campaign STRING,
  adset STRING,
  firebase_exp STRING,
  ga_session_id INT64,
  ga_session_number INT64,
  level INT64,
  start_type STRING,
  play_index INT64,
  play_duration INT64,
  lose_by STRING,
  action_sequence STRING,
  result_by STRING,
  ad_format STRING,
  ad_network STRING,
  ad_platform STRING,
  ad_source STRING, -- Thêm mới
  ad_duration INT64,
  value FLOAT64,
  currency STRING,
  event_value_in_usd FLOAT64,
  placement STRING,
  current_screen STRING,
  feature_placement STRING,
  feature_name STRING,
  feature_duration INT64,
  button_name STRING,
  button_placement STRING,
  ad_type STRING,
  ad_unit_name STRING, -- Đã có
  reason STRING,
  resource_type STRING,
  engagement_time_msec INT64,
  resource_amount INT64,
  event_params_json ARRAY<STRUCT<
    key STRING,
    string_value STRING,
    int_value INT64,
    float_value FLOAT64,
    double_value FLOAT64
  >>
)
PARTITION BY event_date
CLUSTER BY event_name, user_pseudo_id;


INSERT INTO `annoying-puzzle.stg.event_flatten_raw`
WITH flattened_params AS (
  SELECT
    *,
    (SELECT AS STRUCT
      MAX(IF(key = 'ga_session_id', value.int_value, NULL)) AS ga_session_id,
      MAX(IF(key = 'ga_session_number', value.int_value, NULL)) AS ga_session_number,
      SAFE_CAST(MAX(IF(key = 'level', value.string_value, NULL)) AS INT64) AS level,
      MAX(IF(key = 'play_type', value.string_value, NULL)) AS start_type,
      MAX(IF(key = 'play_index', value.int_value, NULL)) AS play_index,
      MAX(IF(key = 'play_duration', value.int_value, NULL)) AS play_duration,
      MAX(IF(key = 'lose_by', value.string_value, NULL)) AS lose_by,
      MAX(IF(key = 'result', value.string_value, NULL)) AS result_by,
      MAX(IF(key = 'ad_format', value.string_value, NULL)) AS ad_format,
      MAX(IF(key = 'ad_network', value.string_value, NULL)) AS ad_network,
      MAX(IF(key = 'ad_platform', value.string_value, NULL)) AS ad_platform,
      MAX(IF(key = 'ad_source', value.string_value, NULL)) AS ad_source, -- Bóc tách ad_source
      MAX(IF(key = 'ad_duration', value.int_value, NULL)) AS ad_duration,
      MAX(IF(key = 'value', value.double_value, NULL)) AS value,
      MAX(IF(key = 'currency', value.string_value, NULL)) AS currency,
      MAX(IF(key = 'placement', value.string_value, NULL)) AS placement,
      MAX(IF(key = 'feature_placement', value.string_value, NULL)) AS feature_placement,
      MAX(IF(key = 'feature_name', value.string_value, NULL)) AS feature_name,
      MAX(IF(key = 'feature_duration', value.int_value, NULL)) AS feature_duration,
      MAX(IF(key = 'button_name', value.string_value, NULL)) AS button_name,
      MAX(IF(key = 'button_placement', value.string_value, NULL)) AS button_placement,
      MAX(IF(key = 'ad_type', value.string_value, NULL)) AS ad_type,
      MAX(IF(key = 'ad_unit_name', value.string_value, NULL)) AS ad_unit_name, -- Đã có bóc tách
      MAX(IF(key = 'reason', value.string_value, NULL)) AS reason,
      MAX(IF(key = 'resource_type', value.string_value, NULL)) AS resource_type,
      MAX(IF(key = 'engagement_time_msec', value.int_value, NULL)) AS engagement_time_msec,
      MAX(IF(key = 'resource_amount', value.int_value, NULL)) AS resource_amount,
      ARRAY_TO_STRING([
        MAX(IF(key = 'action_seq_1', value.string_value, NULL)),
        MAX(IF(key = 'action_seq_2', value.string_value, NULL)),
        MAX(IF(key = 'action_seq_3', value.string_value, NULL)),
        MAX(IF(key = 'action_seq_4', value.string_value, NULL)),
        MAX(IF(key = 'action_seq_5', value.string_value, NULL))
      ], '|') AS action_sequence
    FROM UNNEST(event_params)) AS ep,
   
    (SELECT AS STRUCT
      SAFE_CAST(MAX(IF(key = 'current_level', value.string_value, NULL)) AS INT64) AS current_level,
      MAX(IF(key = 'first_open_time', value.int_value, NULL)) AS first_open_time,
      MAX(IF(key = 'campaign', value.string_value, NULL)) AS campaign,
      MAX(IF(key = 'current_screen', value.string_value, NULL)) AS current_screen,
      MAX(IF(key = 'adset', value.string_value, NULL)) AS adset,
      MAX(IF(key LIKE 'firebase_exp_%', value.string_value, NULL)) AS firebase_exp_raw
    FROM UNNEST(user_properties)) AS up
   
FROM `annoying-puzzle.analytics_485408210.events_intraday_*`
WHERE _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE("Asia/Ho_Chi_Minh"), INTERVAL 2 DAY))
  AND FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE("Asia/Ho_Chi_Minh"), INTERVAL 1 DAY))
)

SELECT
  DATE(TIMESTAMP_MICROS(event_timestamp),"Asia/Ho_Chi_Minh") AS event_date,
  event_timestamp,
  event_name,
  user_pseudo_id,
  platform,
  app_info.version,
  device.mobile_marketing_name,
  device.mobile_model_name,
  device.operating_system_version,
  device.language,
  geo.country,
  geo.city,
  geo.continent,
  up.current_level,
  DATE(TIMESTAMP_MILLIS(up.first_open_time), "Asia/Ho_Chi_Minh") AS first_open_date,
  up.campaign,
  up.adset,
  CASE
    WHEN LOWER(up.firebase_exp_raw) IN ('1','true','t') THEN 'B'
    WHEN LOWER(up.firebase_exp_raw) IN ('0','false','f') THEN 'A'
    WHEN LOWER(up.firebase_exp_raw) IN ('2') THEN 'C'
    WHEN LOWER(up.firebase_exp_raw) IN ('3') THEN 'D'
    ELSE up.firebase_exp_raw
  END AS firebase_exp,
  ep.ga_session_id,
  ep.ga_session_number,
  ep.level,
  ep.start_type,
  ep.play_index,
  ep.play_duration,
  ep.lose_by,
  ep.action_sequence,
  ep.result_by,
  ep.ad_format,
  ep.ad_network,
  ep.ad_platform,
  ep.ad_source, -- Đưa vào SELECT
  ep.ad_duration,
  ep.value,
  ep.currency,
  event_value_in_usd,
  ep.placement,
  up.current_screen,
  ep.feature_placement,
  ep.feature_name,
  ep.feature_duration,
  ep.button_name,
  ep.button_placement,
  ep.ad_type,
  ep.ad_unit_name,
  ep.reason,
  ep.resource_type,
  ep.engagement_time_msec,
  ep.resource_amount,
  ARRAY(SELECT AS STRUCT key, value.string_value, value.int_value, value.float_value, value.double_value FROM UNNEST(event_params)) AS event_params_json
FROM flattened_params
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY user_pseudo_id, event_name, event_timestamp
    ORDER BY event_timestamp
) = 1;