#!/usr/bin/env python
"""
bq_guard.py — BigQuery cost guard (cross-project).

VENDORED COPY (2026-09-11) of ~/.claude/scripts/bq_guard.py for use inside the Airflow
container, which has no access to the user's ~/.claude/ folder. The original remains the
canonical version enforced by the Claude Code PreToolUse hook for ad-hoc queries — if that
guard's logic changes (e.g. the 100GB threshold), re-copy it here manually.

The ONLY sanctioned way to run a BigQuery query from any project in meta-project.
A user-level PreToolUse hook blocks direct client.query() / `bq query` calls.

What it does, every run:
  1. DRY-RUN first, print the byte estimate in GB.
  2. If estimate > 100 GB  -> REFUSE (exit 3). Stop and ask the user.
     Proceed only after approval:  --allow-gb <N> --reason "why"
  3. Real run always sets job_config.maximum_bytes_billed as a hard cap
     (BigQuery kills the job itself if it goes over).
  4. Append one JSON line per run to ~/.claude/logs/bq_usage.jsonl (audit trail).

Usage:
  python bq_guard.py QUERY.sql
  python bq_guard.py QUERY.sql --allow-gb 200 --reason "full-history isOrganic backfill, approved by user"
  cat query.sql | python bq_guard.py -  --reason "..."

Options:
  --project P        GCP project (else from creds / GOOGLE_APPLICATION_CREDENTIALS)
  --creds PATH       service-account json (sets GOOGLE_APPLICATION_CREDENTIALS)
  --location LOC     e.g. US / EU (default: library default)
  --allow-gb N       raise the refuse-threshold to N GB for THIS run (needs --reason)
  --reason TEXT      why the large scan is justified (logged)
  --max-rows N       max rows to print (default 500)
  --format tsv|json  output format (default tsv)
"""
import argparse, datetime, json, os, pathlib, sys, time

LIMIT_GB = 100.0
LOG_PATH = pathlib.Path.home() / ".claude" / "logs" / "bq_usage.jsonl"


def log(entry: dict) -> None:
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        entry = {"ts": datetime.datetime.now().isoformat(timespec="seconds"),
                 "cwd": os.getcwd(), **entry}
        with LOG_PATH.open("a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


def main() -> int:
    ap = argparse.ArgumentParser(description="BigQuery cost guard")
    ap.add_argument("sql", help="path to .sql file, or - for stdin")
    ap.add_argument("--project")
    ap.add_argument("--creds")
    ap.add_argument("--location")
    ap.add_argument("--allow-gb", type=float, default=None)
    ap.add_argument("--reason", default=None)
    ap.add_argument("--max-rows", type=int, default=500)
    ap.add_argument("--format", choices=["tsv", "json"], default="tsv")
    args = ap.parse_args()

    sql = sys.stdin.read() if args.sql == "-" else pathlib.Path(args.sql).read_text(encoding="utf-8")
    if not sql.strip():
        print("[bq_guard] empty query", file=sys.stderr)
        return 2

    if args.creds:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = args.creds

    from google.cloud import bigquery

    client = bigquery.Client(project=args.project) if args.project else bigquery.Client()

    # 1) dry run
    dry = client.query(
        sql,
        job_config=bigquery.QueryJobConfig(dry_run=True, use_query_cache=False),
        location=args.location,
    )
    gb = (dry.total_bytes_processed or 0) / 1e9
    threshold = args.allow_gb if args.allow_gb else LIMIT_GB
    print(f"[bq_guard] dry-run estimate: {gb:.2f} GB   (refuse above {threshold:.0f} GB)   "
          f"project={client.project}", file=sys.stderr)

    if gb > LIMIT_GB and not args.allow_gb:
        log({"action": "blocked", "est_gb": round(gb, 2), "sql_head": sql[:240]})
        print(
            f"\n*** BLOCKED: estimate {gb:.1f} GB exceeds the {LIMIT_GB:.0f} GB limit. ***\n"
            f"STOP. Ask the user to confirm before running a scan this large.\n"
            f"After they approve, re-run with:\n"
            f'   --allow-gb {int(gb) + 1} --reason "why this scan is necessary"\n',
            file=sys.stderr,
        )
        return 3

    if args.allow_gb and not args.reason:
        print("[bq_guard] --allow-gb requires --reason", file=sys.stderr)
        return 2

    if args.allow_gb and gb > args.allow_gb:
        print(f"[bq_guard] estimate {gb:.1f} GB still exceeds --allow-gb {args.allow_gb:.0f} GB",
              file=sys.stderr)
        return 3

    # 2) real run with a hard cap
    cap_bytes = int(max(threshold, gb + 1) * 1e9)
    job = client.query(
        sql,
        job_config=bigquery.QueryJobConfig(maximum_bytes_billed=cap_bytes, use_query_cache=True),
        location=args.location,
    )
    t0 = time.time()
    result = job.result(max_results=args.max_rows)
    secs = time.time() - t0
    billed = (job.total_bytes_billed or 0) / 1e9
    log({"action": "ran", "est_gb": round(gb, 2), "billed_gb": round(billed, 2),
         "allow_gb": args.allow_gb, "reason": args.reason, "secs": round(secs, 1),
         "cache_hit": bool(job.cache_hit), "sql_head": sql[:240]})
    print(f"[bq_guard] done: billed {billed:.2f} GB, {secs:.1f}s, cache_hit={job.cache_hit}",
          file=sys.stderr)

    fields = [f.name for f in result.schema]
    rows = list(result)
    if args.format == "json":
        print(json.dumps([{k: r[k] for k in fields} for r in rows], default=str, ensure_ascii=False, indent=2))
    else:
        print("\t".join(fields))
        for r in rows:
            print("\t".join("" if r[f] is None else str(r[f]) for f in fields))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa
        print(f"[bq_guard] ERROR: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
