CREATE TABLE IF NOT EXISTS `annoying-puzzle.stg.event_base`
(
  event_name STRING,
  event_timestamp INT64,
  event_date DATE,
  user_pseudo_id STRING,

  ga_session_number INT64,
  ga_session_id INT64,

  app_version STRING,
  device_mobile_marketing_name STRING,
  device_mobile_model_name STRING,
  device_operating_system_version STRING,
  language STRING,
  country STRING,
  city STRING,
  continent STRING,

  first_open_date DATE,
  current_level INT64,
  campaign STRING,
  adset STRING,
  current_screen STRING,
  firebase_exp STRING
)
PARTITION BY event_date
CLUSTER BY event_name, user_pseudo_id;


INSERT INTO `annoying-puzzle.stg.event_base` (
    event_name,
    event_timestamp,
    event_date,
    user_pseudo_id,
    ga_session_number,
    ga_session_id,

    app_version,
    device_mobile_marketing_name,
    device_mobile_model_name,
    device_operating_system_version,
    language,
    country,
    city,
    continent,

    first_open_date,
    current_level,
    campaign,
    adset,
    current_screen,
    firebase_exp
)
SELECT
    event_name,
    event_timestamp,
    event_date,
    user_pseudo_id,
    ga_session_number,
    ga_session_id,

    app_version,
    device_mobile_marketing_name,
    device_mobile_model_name,
    device_operating_system_version,
    language,
    country,
    city,
    continent,

    first_open_date,
    current_level,
    campaign,
    adset,
    current_screen,
    firebase_exp

FROM `annoying-puzzle.stg.event_flatten_raw`
--WHERE event_date = (
--    SELECT MAX(event_date)
--    FROM `annoying-puzzle.stg.event_flatten_raw`
--);
