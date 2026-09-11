-- L2 obby1_layer2.evt_ad_request_success  <-  ad_request_success  (20260901)
CREATE TABLE IF NOT EXISTS `obby1_layer2.evt_ad_request_success`
PARTITION BY event_date
AS
SELECT
    e.user_pseudo_id,
    e.user_id,
    e.event_name,
    PARSE_DATE('%Y%m%d', e.event_date) AS event_date,
    e.event_timestamp,
    TIMESTAMP_MICROS(e.event_timestamp) AS event_ts,
    (SELECT CAST(p.value.int_value AS STRING) FROM UNNEST(e.event_params) p WHERE p.key = 'ga_session_id' LIMIT 1) AS ga_session_id,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'current_Screen' LIMIT 1) AS current_screen,
    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) FROM UNNEST(e.event_params) p WHERE p.key = 'ad_format' LIMIT 1) AS ad_format,
    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) FROM UNNEST(e.event_params) p WHERE p.key = 'time' LIMIT 1) AS time,
    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) FROM UNNEST(e.event_params) p WHERE p.key = 'load_attempt_number' LIMIT 1) AS load_attempt_number
FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901` AS e
WHERE e.event_name = 'ad_request_success'
LIMIT 0;

DELETE FROM `obby1_layer2.evt_ad_request_success`
WHERE event_date = DATE('2026-09-01');

INSERT INTO `obby1_layer2.evt_ad_request_success`
SELECT
    e.user_pseudo_id,
    e.user_id,
    e.event_name,
    PARSE_DATE('%Y%m%d', e.event_date) AS event_date,
    e.event_timestamp,
    TIMESTAMP_MICROS(e.event_timestamp) AS event_ts,
    (SELECT CAST(p.value.int_value AS STRING) FROM UNNEST(e.event_params) p WHERE p.key = 'ga_session_id' LIMIT 1) AS ga_session_id,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'current_Screen' LIMIT 1) AS current_screen,
    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) FROM UNNEST(e.event_params) p WHERE p.key = 'ad_format' LIMIT 1) AS ad_format,
    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) FROM UNNEST(e.event_params) p WHERE p.key = 'time' LIMIT 1) AS time,
    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) FROM UNNEST(e.event_params) p WHERE p.key = 'load_attempt_number' LIMIT 1) AS load_attempt_number
FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901` AS e
WHERE e.event_name = 'ad_request_success';
