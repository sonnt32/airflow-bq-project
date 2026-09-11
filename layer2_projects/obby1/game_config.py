#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Cấu hình riêng của Obby 1 cho generator L2 dùng chung
(_shared/layer2_toolkit/python/l2_generator.py).

Quy ước đã chốt với user (xem layer2/README.md):
  - Moi bang: user_pseudo_id, user_id, event_name, event_date, event_timestamp,
    event_ts, ga_session_id, current_screen  + cac param rieng cua event (moi param 1 cot).
  - Khong surrogate key. Join giua cac bang qua user_pseudo_id (+ ga_session_id).
  - Chi 2 bang context (first_open, session_start) mang thong tin user/device/geo/app.
  - Param so/enum/thoi gian -> STRING ; param doanh thu (value, reward_value) -> FLOAT64
    (theo Data Foundation v1.1). Param GA4 plumbing bi loai.
  - Param ngoai danh sach -> bo (chot voi user).
"""
import os
import sys
import pathlib

# Xem gen_layer2.py — cùng quy ước override qua LAYER2_TOOLKIT_PYTHON_DIR (dùng trong container).
_HERE = pathlib.Path(__file__).resolve().parent
_TOOLKIT_DIR = os.environ.get(
    "LAYER2_TOOLKIT_PYTHON_DIR",
    str(_HERE.parents[1] / "_shared" / "layer2_toolkit" / "python"),
)
sys.path.insert(0, _TOOLKIT_DIR)
from l2_generator import L2Config  # noqa: E402

EVENTS = {
    "first_open":                 [],
    "session_start":              [],
    "user_engagement":            ["engagement_time_msec"],
    "loading":                    [],
    "enter_home":                 [],
    "level_start":                ["minigame_id", "attempt"],
    "level_end":                  ["minigame_id", "attempt", "deaths", "result_by",
                                   "play_duration", "revive_Total"],
    "checkpoint_reached":         ["minigame_id", "checkpoint_index", "revives_per_cp"],
    "item_click":                 ["item_id", "item_category"],
    "click_change_outfit_button": [],
    "click_shop_button":          [],
    "click_quest_button":         [],
    "mode_clicked":               ["mode_id"],
    "enter_survival_mode_lobby":  [],
    "exit_survival_mode_lobby":   [],
    "survial_session_start":      [],
    "survial_session_end":        ["result"],
    "ad_impression":              ["value", "currency", "ad_format", "ad_unit_name",
                                   "ad_platform", "ad_source"],
    "app_request_show_ad":        ["ad_context", "feature", "ad_format", "placement"],
    "ad_start_show":              ["ad_context", "feature", "ad_format", "placement"],
    "ad_show_complete":           ["ad_unit_id", "value", "feature", "time", "ad_network",
                                   "ad_platform", "ad_context", "ad_format", "placement"],
    "ad_show_failed":             ["ad_format", "placement", "feature", "ad_context",
                                   "fail_detail", "fail_reason"],
    "ad_request_success":         ["ad_format", "time", "load_attempt_number"],
    "ad_request_failed":          ["fail_reason", "ad_format", "time"],
    "ad_reward":                  ["reward_value", "ad_unit_code"],
    "app_remove":                 [],
    "os_update":                  ["previous_os_version"],
    "app_update":                 ["previous_app_version"],
    "app_exception":              ["fatal", "timestamp", "engagement_time_msec"],
    "firebase_campaign":          ["campaign_info_source", "medium", "source", "gclid",
                                   "gad_source", "click_timestamp", "gad_campaignid"],
}

CONFIG = L2Config(
    gcp_project="suvival-master-obby-parkour",
    raw_dataset="analytics_505759684",
    dst_dataset="obby1_layer2",
    context_events={"first_open", "session_start"},
    events=EVENTS,
)
