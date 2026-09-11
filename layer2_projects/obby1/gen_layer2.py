#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Layer 2 generator — Obby 1 (project suvival-master-obby-parkour).

Wrapper mỏng: logic build SQL nằm ở engine dùng chung
_shared/layer2_toolkit/python/l2_generator.py (tái sử dụng cho Obby 2, Obby 3,
...). File này chỉ trỏ tới config riêng của Obby 1 (game_config.py) và ghi
kết quả vào layer2/sql/. Xem _shared/layer2_toolkit/README.md để onboard game
mới.
"""
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
# Local host run (meta-project/<game>/layer2/): _shared là sibling của thư mục game, lên 2 cấp.
# Trong container (đường dẫn mount khác), set LAYER2_TOOLKIT_PYTHON_DIR để override — xem
# _shared/layer2_toolkit/README.md và docker-compose.yml của dbt_airflow_master.
TOOLKIT_DIR = os.environ.get(
    "LAYER2_TOOLKIT_PYTHON_DIR",
    str(HERE.parents[1] / "_shared" / "layer2_toolkit" / "python"),
)
sys.path.insert(0, TOOLKIT_DIR)

from game_config import CONFIG  # noqa: E402
from l2_generator import generate  # noqa: E402

OUT = pathlib.Path(__file__).parent / "sql"


def main():
    date = sys.argv[1] if len(sys.argv) > 1 else "20260901"
    n = generate(CONFIG, date, OUT)
    print(f"generated {n} event files + dataset ddl in {OUT}  (date={date})")


if __name__ == "__main__":
    main()
