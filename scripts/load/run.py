"""Measure the warehouse API on loopback using a fresh, disposable database."""

import argparse
import csv
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.request import urlopen

import psutil

from summarize import SCENARIOS, summarize

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]


def wait_for_server(server, url, log_path):
    for _ in range(100):
        if server.poll() is not None:
            raise RuntimeError("Uvicorn exited during startup. See server.log.")
        # Another program could already be listening on the requested port.
        if f"Uvicorn running on {url}" not in log_path.read_text(errors="replace"):
            time.sleep(0.2)
            continue
        try:
            with urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return
        except OSError:
            time.sleep(0.2)
    raise RuntimeError("Local server did not become ready. See server.log.")


def run_scenario(url, server_pid, users, seconds, output):
    prefix = output / str(users)
    command = [
        sys.executable, "-m", "locust", "--headless", "-f", str(HERE / "locustfile.py"),
        "-H", url, "-u", str(users), "-r", str(users), "--run-time", f"{seconds}s",
        "--csv", str(prefix), "--only-summary",
    ]
    process = psutil.Process(server_pid)
    log_path = output / f"load-{users}.log"
    samples_path = output / f"{users}_resources.csv"
    with log_path.open("w") as log, samples_path.open("w", newline="") as resources:
        writer = csv.writer(resources)
        writer.writerow(["cpu_percent", "rss_bytes"])
        with subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT) as test:
            try:
                process.cpu_percent()
                while test.poll() is None:
                    time.sleep(1)
                    writer.writerow([process.cpu_percent(), process.memory_info().rss])
            finally:
                if test.poll() is None:
                    test.terminate()
    if test.returncode not in (0, 1):
        raise RuntimeError(f"Locust stopped unexpectedly. See {log_path}.")
    return test.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New directory for logs, CSV and chart")
    parser.add_argument("--port", type=int, default=18941)
    parser.add_argument("--users", type=int, choices=[n for n, _ in SCENARIOS],
                        help="Repeat a single stage using its original duration")
    args = parser.parse_args()
    scenarios = [(n, s) for n, s in SCENARIOS if args.users is None or args.users == n]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    url = f"http://127.0.0.1:{args.port}"
    # Running a copy places database.db in the temporary directory even if the
    # application uses a repository-relative SQLite path.
    with tempfile.TemporaryDirectory() as runtime:
        shutil.copytree(PROJECT / "app", Path(runtime) / "app",
                        ignore=shutil.ignore_patterns("__pycache__"))
        env = dict(os.environ, PYTHONPATH=runtime)
        subprocess.run([sys.executable, "-m", "app.database.seed"], cwd=runtime, env=env, check=True)
        with (output / "server.log").open("w") as log, subprocess.Popen(
            [sys.executable, "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1",
             "--port", str(args.port), "--no-access-log"],
            cwd=runtime, env=env, stdout=log, stderr=subprocess.STDOUT,
        ) as server:
            try:
                wait_for_server(server, url, output / "server.log")
                failed = False
                for users, seconds in scenarios:
                    print(f"{users} users, {seconds}s", flush=True)
                    status = run_scenario(url, server.pid, users, seconds, output)
                    failed = failed or status != 0
            finally:
                if server.poll() is None:
                    server.terminate()
    summarize(output, scenarios)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
