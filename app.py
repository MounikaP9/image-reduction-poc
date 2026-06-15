# app.py - Image Factory Control Plane API Engine
from datetime import datetime, timezone
from pathlib import Path
import os
import subprocess
import time

from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.responses import PlainTextResponse
from prometheus_client import Counter, Gauge, Info, make_asgi_app

app = FastAPI(title="Image Factory Control Plane Framework")

BASE_DIR = Path(os.getenv("OL9_FACTORY_BASE_DIR", "/home/opc/ol9-prod-factory"))
LOG_DIR = BASE_DIR / "logs"
DIST_DIR = BASE_DIR / "dist"
REPORT_DIR = BASE_DIR / "reports"
IMAGE_FILE = BASE_DIR / "ol9-monolithic-prod.img"
MERGED_ROOT = BASE_DIR / "deploy_target" / "merged_root"
MERGED_ID_FILE = BASE_DIR / "deploy_target" / "merged-root-id.txt"

SCRIPT_MAPPING = {
    "simulate-image": BASE_DIR / "01-build-prod-image.sh",
    "split-layers": BASE_DIR / "02-split-prod-image.sh",
    "combine-layers": BASE_DIR / "03-deploy-and-update.sh",
    "validate-image": BASE_DIR / "04-validate-integrity.sh",
}

COMMAND_MAPPING = {
    "build": "simulate-image",
    "split": "split-layers",
    "deploy": "combine-layers",
    "validate": "validate-image",
}

STEP_ORDER = {
    "simulate-image": 1,
    "split-layers": 2,
    "combine-layers": 3,
    "validate-image": 4,
}

PIPELINE_STATUS = Gauge(
    "image_factory_step_status",
    "Status of each pipeline step (1=Success, 0=Fail, 0.5=Running, -1=Idle)",
    ["step"],
)
PIPELINE_DURATION = Gauge(
    "image_factory_step_duration_seconds",
    "Time taken for each sequential orchestration step",
    ["step"],
)
PIPELINE_STARTED = Gauge(
    "image_factory_step_started_timestamp_seconds",
    "Unix timestamp when a lifecycle step started",
    ["step"],
)
PIPELINE_FINISHED = Gauge(
    "image_factory_step_finished_timestamp_seconds",
    "Unix timestamp when a lifecycle step finished",
    ["step"],
)
PIPELINE_RUNS = Counter(
    "image_factory_pipeline_runs_total",
    "Total aggregated executed pipeline operational runs",
    ["step", "result"],
)
CURRENT_STEP = Gauge(
    "image_factory_current_step",
    "Current lifecycle step number (-1=Not Run, 0=Completed, 1=Simulate, 2=Split, 3=Deploy, 4=Validate)",
)
ARTIFACT_SIZE = Gauge(
    "image_factory_artifact_size_bytes",
    "Artifact size in bytes for the monolithic image, SquashFS layers, and merged output",
    ["artifact"],
)
ARTIFACT_INFO = Info(
    "image_factory_artifact",
    "Artifact identity metadata including short SHA256 IDs and paths",
    ["artifact"],
)
VALIDATION_STATUS = Gauge(
    "image_factory_validation_success",
    "Latest validation result (-1=Not Run, 0=Failed, 1=Passed)",
)
LOG_LINES = Gauge(
    "image_factory_log_lines_total",
    "Number of lines in the latest lifecycle log",
    ["step"],
)

RUN_STATE = {
    step: {"status": "idle", "log_file": None, "started_at": None, "finished_at": None, "returncode": None}
    for step in SCRIPT_MAPPING
}

for lifecycle_step in SCRIPT_MAPPING:
    PIPELINE_STATUS.labels(step=lifecycle_step).set(-1)
CURRENT_STEP.set(-1)
VALIDATION_STATUS.set(-1)

metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def unix_now():
    return time.time()


def log_path_for(step_name):
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return LOG_DIR / f"{step_name}-{stamp}.log"


def file_count(path):
    if path.is_file():
        return 1
    return 0


def fast_mounted_output_size():
    base_layer = DIST_DIR / "layer-base.squashfs"
    platform_layer = DIST_DIR / "layer-platform.squashfs"
    return sum(layer.stat().st_size for layer in [base_layer, platform_layer] if layer.exists())


def safe_short_id(path):
    if not path.exists():
        return "missing"
    if path.is_file():
        stat = path.stat()
        return f"{stat.st_size:x}{int(stat.st_mtime):x}"[-16:]
    return "mounted"


def latest_report_status():
    reports = sorted(REPORT_DIR.glob("integrity-report-*.txt")) if REPORT_DIR.exists() else []
    if not reports:
        return -1
    text = reports[-1].read_text(encoding="utf-8", errors="replace")
    return 1 if "VALIDATION STATUS: SUCCESS" in text else 0


def refresh_artifact_metrics():
    artifacts = {
        "original-simulated-image": IMAGE_FILE,
        "layer-base": DIST_DIR / "layer-base.squashfs",
        "layer-platform": DIST_DIR / "layer-platform.squashfs",
        "mounted-output-image": MERGED_ROOT,
    }

    for artifact, path in artifacts.items():
        if artifact == "mounted-output-image":
            size = fast_mounted_output_size()
        elif path.is_file():
            size = path.stat().st_size
        else:
            size = 0

        artifact_id = safe_short_id(path)
        if artifact == "mounted-output-image" and MERGED_ID_FILE.exists():
            artifact_id = MERGED_ID_FILE.read_text(encoding="utf-8", errors="replace").strip()[:16] or "mounted"

        ARTIFACT_SIZE.labels(artifact=artifact).set(size)
        ARTIFACT_INFO.labels(artifact=artifact).info(
            {
                "artifact_id": artifact_id,
                "path": str(path),
                "file_count": str(file_count(path)),
            }
        )

    VALIDATION_STATUS.set(latest_report_status())


def update_log_metric(step_name, log_file):
    try:
        lines = sum(1 for _ in Path(log_file).open("r", encoding="utf-8", errors="replace"))
    except OSError:
        lines = 0
    LOG_LINES.labels(step=step_name).set(lines)


def run_script(script_path, step_name):
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_file = log_path_for(step_name)

    PIPELINE_STATUS.labels(step=step_name).set(0.5)
    PIPELINE_STARTED.labels(step=step_name).set(unix_now())
    CURRENT_STEP.set(STEP_ORDER[step_name])
    RUN_STATE[step_name] = {
        "status": "running",
        "log_file": str(log_file),
        "started_at": utc_now(),
        "finished_at": None,
        "returncode": None,
    }

    start_time = time.time()
    with log_file.open("w", encoding="utf-8") as output:
        output.write(f"[{utc_now()}] Starting {step_name}: {script_path}\n")
        output.flush()
        result = subprocess.run(
            ["sudo", "-n", str(script_path)],
            stdout=output,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        output.write(f"\n[{utc_now()}] Finished {step_name} with return code {result.returncode}\n")

    duration = time.time() - start_time
    PIPELINE_DURATION.labels(step=step_name).set(duration)
    PIPELINE_FINISHED.labels(step=step_name).set(unix_now())
    update_log_metric(step_name, log_file)

    if result.returncode == 0:
        PIPELINE_STATUS.labels(step=step_name).set(1)
        PIPELINE_RUNS.labels(step=step_name, result="success").inc()
        status = "success"
    else:
        PIPELINE_STATUS.labels(step=step_name).set(0)
        PIPELINE_RUNS.labels(step=step_name, result="failed").inc()
        status = "failed"

    refresh_artifact_metrics()
    CURRENT_STEP.set(0)
    RUN_STATE[step_name].update(
        {
            "status": status,
            "finished_at": utc_now(),
            "returncode": result.returncode,
            "duration_seconds": round(duration, 3),
        }
    )


@app.get("/api/status")
def get_status():
    refresh_artifact_metrics()
    return RUN_STATE


@app.get("/api/logs/{step}", response_class=PlainTextResponse)
def get_latest_log(step: str):
    step = COMMAND_MAPPING.get(step, step)
    if step not in SCRIPT_MAPPING:
        raise HTTPException(status_code=404, detail="Unknown lifecycle action")

    log_file = RUN_STATE.get(step, {}).get("log_file")
    if not log_file:
        candidates = sorted(LOG_DIR.glob(f"{step}-*.log")) if LOG_DIR.exists() else []
        log_file = str(candidates[-1]) if candidates else None

    if not log_file or not Path(log_file).exists():
        raise HTTPException(status_code=404, detail="No log found for this action yet")

    update_log_metric(step, log_file)
    return Path(log_file).read_text(encoding="utf-8", errors="replace")


@app.get("/api/artifacts")
def get_artifacts():
    refresh_artifact_metrics()
    return {
        "original_simulated_image": str(IMAGE_FILE),
        "base_layer": str(DIST_DIR / "layer-base.squashfs"),
        "platform_layer": str(DIST_DIR / "layer-platform.squashfs"),
        "mounted_output_image": str(MERGED_ROOT),
        "mounted_output_id_file": str(MERGED_ID_FILE),
        "reports": str(REPORT_DIR),
    }


@app.post("/api/action/{step}")
def trigger_step(step: str, background_tasks: BackgroundTasks):
    step = COMMAND_MAPPING.get(step, step)
    if step not in SCRIPT_MAPPING:
        raise HTTPException(status_code=400, detail="Invalid lifecycle action mapping executed")

    script_path = SCRIPT_MAPPING[step]
    if not script_path.exists():
        raise HTTPException(status_code=500, detail=f"Script not found on OCI instance: {script_path}")

    if RUN_STATE[step].get("status") == "running":
        return {"status": "already-running", "step": step, "log_file": RUN_STATE[step].get("log_file")}

    PIPELINE_STATUS.labels(step=step).set(0.5)
    CURRENT_STEP.set(STEP_ORDER[step])
    background_tasks.add_task(run_script, script_path, step)
    return {"status": "queued", "step": step}
