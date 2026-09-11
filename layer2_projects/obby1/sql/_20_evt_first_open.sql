-- L2 obby1_layer2.evt_first_open  <-  first_open  (20260901)
CREATE TABLE IF NOT EXISTS `obby1_layer2.evt_first_open`
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
    e.geo.country            AS geo_country,
    e.geo.region             AS geo_region,
    e.geo.city               AS geo_city,
    e.device.category        AS device_category,
    e.device.operating_system         AS device_os,
    e.device.operating_system_version AS device_os_version,
    e.device.mobile_brand_name        AS device_brand,
    e.device.mobile_model_name        AS device_model,
    e.device.language        AS device_language,
    e.app_info.version       AS app_version,
    e.app_info.id            AS app_id,
    e.app_info.install_store AS install_store,
    e.app_info.install_source AS install_source,
    e.traffic_source.name    AS traffic_name,
    e.traffic_source.medium  AS traffic_medium,
    e.traffic_source.source  AS traffic_source,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'media_source' LIMIT 1) AS up_media_source,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'campaign' LIMIT 1) AS up_campaign,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'adset' LIMIT 1) AS up_adset,
    (SELECT CAST(p.value.int_value AS STRING) FROM UNNEST(e.event_params) p WHERE p.key = 'ga_session_number' LIMIT 1) AS ga_session_number
FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901` AS e
WHERE e.event_name = 'first_open'
LIMIT 0;

DELETE FROM `obby1_layer2.evt_first_open`
WHERE event_date = DATE('2026-09-01');

INSERT INTO `obby1_layer2.evt_first_open`
SELECT
    e.user_pseudo_id,
    e.user_id,
    e.event_name,
    PARSE_DATE('%Y%m%d', e.event_date) AS event_date,
    e.event_timestamp,
    TIMESTAMP_MICROS(e.event_timestamp) AS event_ts,
    (SELECT CAST(p.value.int_value AS STRING) FROM UNNEST(e.event_params) p WHERE p.key = 'ga_session_id' LIMIT 1) AS ga_session_id,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'current_Screen' LIMIT 1) AS current_screen,
    e.geo.country            AS geo_country,
    e.geo.region             AS geo_region,
    e.geo.city               AS geo_city,
    e.device.category        AS device_category,
    e.device.operating_system         AS device_os,
    e.device.operating_system_version AS device_os_version,
    e.device.mobile_brand_name        AS device_brand,
    e.device.mobile_model_name        AS device_model,
    e.device.language        AS device_language,
    e.app_info.version       AS app_version,
    e.app_info.id            AS app_id,
    e.app_info.install_store AS install_store,
    e.app_info.install_source AS install_source,
    e.traffic_source.name    AS traffic_name,
    e.traffic_source.medium  AS traffic_medium,
    e.traffic_source.source  AS traffic_source,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'media_source' LIMIT 1) AS up_media_source,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'campaign' LIMIT 1) AS up_campaign,
    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) FROM UNNEST(e.user_properties) up WHERE up.key = 'adset' LIMIT 1) AS up_adset,
    (SELECT CAST(p.value.int_value AS STRING) FROM UNNEST(e.event_params) p WHERE p.key = 'ga_session_number' LIMIT 1) AS ga_session_number
FROM `suvival-master-obby-parkour.analytics_505759684.events_20260901` AS e
WHERE e.event_name = 'first_open';
