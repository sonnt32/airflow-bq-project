-- L2 obby1_layer2.evt_ad_reward  <-  ad_reward  (20260901)
CREATE TABLE IF NOT EXISTS `obby1_layer2.evt_ad_reward`
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
    (SELECT COALESCE(p.value.double_value, p.value.float_value, CAST(p.value.int_value AS FLOAT64), SAFE_CAST(p.value.string_value AS FLOAT64)) FROM UNNEST(e.event_params) p WHERE p.key = 'reward_value' LIMIT 1) AS reward_value,
    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) FROM UNNEST(e.event_params) p WHERE p.key = 'ad_unit_code' LIMIT 1) AS ad_unit_code
FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901` AS e
WHERE e.event_name = 'ad_reward'
LIMIT 0;

DELETE FROM `obby1_layer2.evt_ad_reward`
WHERE event_date = DATE('2026-09-01');

INSERT INTO `obby1_layer2.evt_ad_reward`
SELECT
    e.user_pseudo_id,
    e.user_id,
    e.event_name,
    PARSE_DATE('%Y%m%d', e.event_date) AS event_date,
    e.event_timestamp,
    TIMESTAMP_MICROS(e.event_timestamp) AS event_ts,
    (SELECT CAST(p.value.int_value AS STRING) FROM UNNEST(e.event_params) p WHERE p.key = 'ga_session_id' LIMIT 1) AS ga_session_id,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'current_Screen' LIMIT 1) AS current_screen,
    (SELECT COALESCE(p.value.double_value, p.value.float_value, CAST(p.value.int_value AS FLOAT64), SAFE_CAST(p.value.string_value AS FLOAT64)) FROM UNNEST(e.event_params) p WHERE p.key = 'reward_value' LIMIT 1) AS reward_value,
    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) FROM UNNEST(e.event_params) p WHERE p.key = 'ad_unit_code' LIMIT 1) AS ad_unit_code
FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901` AS e
WHERE e.event_name = 'ad_reward';
