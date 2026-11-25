"""Summarize Locust's aggregate row and the server's CPU/RSS samples."""

import csv
import statistics
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
from matplotlib import pyplot as plt

SCENARIOS = [(5, 60), (20, 120), (50, 180), (100, 180)]


def summarize(directory, scenarios=SCENARIOS):
    runs = []
    for users, seconds in scenarios:
        with (directory / f"{users}_stats.csv").open(newline="") as stream:
            stats = next(row for row in csv.DictReader(stream) if row["Name"] == "Aggregated")
        with (directory / f"{users}_resources.csv").open(newline="") as stream:
            samples = list(csv.DictReader(stream))
        count = int(stats["Request Count"])
        failures = int(stats["Failure Count"])
        runs.append({
            "users": users, "seconds": seconds, "requests": count, "failures": failures,
            "error_pct": round(100 * failures / count, 2),
            "rps": round(float(stats["Requests/s"]), 2),
            "mean_ms": round(float(stats["Average Response Time"]), 2), "p95_ms": float(stats["95%"]),
            "cpu_mean_pct": round(statistics.mean(float(s["cpu_percent"]) for s in samples), 1),
            "rss_peak_mib": round(max(int(s["rss_bytes"]) for s in samples) / (1024 ** 2), 1),
        })
    with (directory / "summary.csv").open("w", newline="") as out:
        writer = csv.DictWriter(out, fieldnames=runs[0])
        writer.writeheader()
        writer.writerows(runs)

    users = [r["users"] for r in runs]
    fig, axes = plt.subplots(1, 2, figsize=(9, 3.6), layout="constrained")
    axes[0].plot(users, [r["mean_ms"] for r in runs], "o-", label="Среднее")
    axes[0].plot(users, [r["p95_ms"] for r in runs], "s--", label="p95")
    axes[0].set_ylabel("Время ответа, мс")
    axes[0].legend()
    axes[1].plot(users, [r["rps"] for r in runs], "o-", color="#20765c")
    axes[1].set_ylabel("Запросы в секунду")
    for axis in axes:
        axis.set(xticks=users, xlabel="Виртуальные пользователи", ylim=(0, None))
        axis.grid(axis="y", alpha=0.3)
    fig.savefig(directory / "load.png", dpi=160)
    plt.close(fig)


if __name__ == "__main__":
    summarize(Path(sys.argv[1]))
