#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Layer 2 generator engine — GAME-AGNOSTIC.

Dùng chung cho mọi project game (Obby 1, Obby 2, Obby 3, ...). Logic tách 1
event GA4 export thành 1 bảng L2 (`<dst_dataset>.evt_<event_name>`) và pattern
SQL idempotent-partition-load nằm ở đây, KHÔNG lặp lại ở từng project.

Phần khác nhau giữa các game (GCP project, tên raw dataset, tên dataset L2,
danh sách event/param riêng) nằm trong 1 file `game_config.py` riêng của từng
project — xem README.md cùng thư mục này để biết cách onboard game mới.

Nguyên tắc bắt buộc: mỗi bảng build theo pattern
  CREATE TABLE IF NOT EXISTS ... PARTITION BY event_date AS ... LIMIT 0
  DELETE FROM ... WHERE event_date = DATE('<ngày đang chạy>')
  INSERT INTO ... SELECT ...
=> mỗi lần chạy chỉ đụng đúng 1 partition (ngày đang generate), KHÔNG bao giờ
   CREATE OR REPLACE TABLE (sẽ xoá sạch các ngày khác đã build trước đó).
"""
from __future__ import annotations

import dataclasses
import pathlib
from typing import Iterable


@dataclasses.dataclass
class L2Config:
    gcp_project: str                    # vd "suvival-master-obby-parkour"
    raw_dataset: str                    # vd "analytics_505759684" (GA4 export)
    dst_dataset: str                    # vd "obby1_layer2"
    events: dict                        # event_name -> [param, ...] (đã loại GA4 plumbing)
    context_events: set                 # events mang cột user/device/geo/app (thường: first_open, session_start)
    revenue_params: set = dataclasses.field(
        default_factory=lambda: {"value", "reward_value"})


def p_str(key: str) -> str:
    return (f"    (SELECT COALESCE(p.value.string_value, CAST(p.value.int_value AS STRING), "
            f"CAST(p.value.double_value AS STRING), CAST(p.value.float_value AS STRING)) "
            f"FROM UNNEST(e.event_params) p WHERE p.key = '{key}' LIMIT 1) AS {key}")


def p_num(key: str) -> str:
    return (f"    (SELECT COALESCE(p.value.double_value, p.value.float_value, "
            f"CAST(p.value.int_value AS FLOAT64), SAFE_CAST(p.value.string_value AS FLOAT64)) "
            f"FROM UNNEST(e.event_params) p WHERE p.key = '{key}' LIMIT 1) AS {key}")


def up_str(key: str, alias: str) -> str:
    return (f"    (SELECT COALESCE(up.value.string_value, CAST(up.value.int_value AS STRING)) "
            f"FROM UNNEST(e.user_properties) up WHERE up.key = '{key}' LIMIT 1) AS {alias}")


# Cột chuẩn GA4 export — giống nhau cho mọi game, không phụ thuộc event/param riêng.
BASE_COLS = [
    "    e.user_pseudo_id",
    "    e.user_id",
    "    e.event_name",
    "    PARSE_DATE('%Y%m%d', e.event_date) AS event_date",
    "    e.event_timestamp",
    "    TIMESTAMP_MICROS(e.event_timestamp) AS event_ts",
    "    (SELECT CAST(p.value.int_value AS STRING) FROM UNNEST(e.event_params) p "
    "WHERE p.key = 'ga_session_id' LIMIT 1) AS ga_session_id",
]

CONTEXT_COLS = [
    up_str("current_Screen", "current_screen"),
    "    e.geo.country            AS geo_country",
    "    e.geo.region             AS geo_region",
    "    e.geo.city               AS geo_city",
    "    e.device.category        AS device_category",
    "    e.device.operating_system         AS device_os",
    "    e.device.operating_system_version AS device_os_version",
    "    e.device.mobile_brand_name        AS device_brand",
    "    e.device.mobile_model_name        AS device_model",
    "    e.device.language        AS device_language",
    "    e.app_info.version       AS app_version",
    "    e.app_info.id            AS app_id",
    "    e.app_info.install_store AS install_store",
    "    e.app_info.install_source AS install_source",
    "    e.traffic_source.name    AS traffic_name",
    "    e.traffic_source.medium  AS traffic_medium",
    "    e.traffic_source.source  AS traffic_source",
    up_str("media_source", "up_media_source"),
    up_str("campaign", "up_campaign"),
    up_str("adset", "up_adset"),
    "    (SELECT CAST(p.value.int_value AS STRING) FROM UNNEST(e.event_params) p "
    "WHERE p.key = 'ga_session_number' LIMIT 1) AS ga_session_number",
]


def build_event_sql(cfg: L2Config, event: str, params: Iterable[str], date: str) -> str:
    raw = f"`{cfg.gcp_project}.{cfg.raw_dataset}.events_{date}`"
    cols = list(BASE_COLS)
    if event in cfg.context_events:
        cols += CONTEXT_COLS
    else:
        cols.append(up_str("current_Screen", "current_screen"))
    for k in params:
        cols.append(p_num(k) if k in cfg.revenue_params else p_str(k))
    sel = ",\n".join(cols)
    select_sql = f"""SELECT
{sel}
FROM {raw} AS e
WHERE e.event_name = '{event}'"""
    day_date = f"{date[0:4]}-{date[4:6]}-{date[6:8]}"
    return f"""-- L2 {cfg.dst_dataset}.evt_{event}  <-  {event}  ({date})
CREATE TABLE IF NOT EXISTS `{cfg.dst_dataset}.evt_{event}`
PARTITION BY event_date
AS
{select_sql}
LIMIT 0;

DELETE FROM `{cfg.dst_dataset}.evt_{event}`
WHERE event_date = DATE('{day_date}');

INSERT INTO `{cfg.dst_dataset}.evt_{event}`
{select_sql};
"""


def generate(cfg: L2Config, date: str, out_dir: pathlib.Path) -> int:
    """Sinh SQL cho 1 ngày vào out_dir. Trả về số bảng đã sinh."""
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "_00_create_dataset.sql").write_text(
        f"CREATE SCHEMA IF NOT EXISTS `{cfg.dst_dataset}` OPTIONS(location = 'US');\n",
        encoding="utf-8")
    for i, (ev, params) in enumerate(sorted(cfg.events.items()), start=1):
        (out_dir / f"_{i:02d}_evt_{ev}.sql").write_text(
            build_event_sql(cfg, ev, params, date), encoding="utf-8")
    return len(cfg.events)
