#!/usr/bin/env python3
"""Coordinate pinned store releases using the existing, gated GitHub workflows."""

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

REPO = "iebb/mithka"
SHA = re.compile(r"[0-9a-f]{40}")
SEMVER = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
APPLE_WORKFLOWS = {"IOS": "ios-testflight.yml", "MAC_OS": "macos-testflight.yml"}
SUBMITTED = {
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "PENDING_APPLE_RELEASE",
    "PENDING_DEVELOPER_RELEASE",
    "PROCESSING_FOR_DISTRIBUTION",
    "READY_FOR_SALE",
    "READY_FOR_DISTRIBUTION",
}


class Error(RuntimeError):
    pass


def command(*args, data=None):
    result = subprocess.run(args, input=data, text=True, capture_output=True)
    if result.returncode:
        # Never include a provider body, environment or credential-bearing URL.
        raise Error(f"{args[0]} failed (exit {result.returncode})")
    return result.stdout.strip()


def version_tuple(value):
    if not SEMVER.fullmatch(value):
        raise Error("expected a normal X.Y.Z version")
    return tuple(map(int, value.split(".")))


def choose_version(master, used):
    current = version_tuple(master)
    versions = [version_tuple(value) for value in used]
    if any(value[:2] > current[:2] for value in versions):
        raise Error("a newer store release train needs a maintainer decision")
    floor = max(
        (value[2] for value in versions if value[:2] == current[:2]), default=-1
    )
    patch = max(current[2], floor + 1, 1)
    return f"{current[0]}.{current[1]}.{patch}"


def next_android_code(values, now):
    code = max(int(now), *(int(value) + 1 for value in values))
    if not 1 <= code <= 2100000000:
        raise Error("next Android code is outside Play's accepted range")
    return code


def release_key(requested, tags, today):
    pending = sorted(
        tag.removeprefix("store-")
        for tag in tags
        if re.fullmatch(r"store-\d{4}-\d{2}-\d{2}", tag)
        and f"store-complete-{tag.removeprefix('store-')}" not in tags
    )
    if len(pending) > 1:
        raise Error("multiple unfinished store snapshots need reconciliation")
    if pending:
        if requested and requested != pending[0]:
            raise Error(
                f"resume unfinished release {pending[0]} before allocating another snapshot"
            )
        return pending[0]
    return requested or today


def assert_context(env):
    if (
        env.get("GITHUB_REPOSITORY") != REPO
        or env.get("GITHUB_REF") != "refs/heads/master"
        or env.get("GITHUB_EVENT_NAME") not in {"schedule", "workflow_dispatch"}
    ):
        raise Error("store coordinator must run on canonical master in GitHub Actions")


def api(path, payload=None):
    args = ["gh", "api", f"repos/{REPO}/{path}"]
    if payload is not None:
        args.extend(["--method", "POST", "--input", "-"])
    raw = command(*args, data=json.dumps(payload) if payload is not None else None)
    return json.loads(raw) if raw else None


def runs(workflow, sha=None):
    query = f"actions/workflows/{workflow}/runs?event=workflow_dispatch&per_page=100"
    if sha:
        query += f"&head_sha={sha}"
    result = api(query)
    # Refuse an incomplete search rather than redispatch an unknown attempt.
    if result["total_count"] > len(result["workflow_runs"]):
        raise Error("workflow attempt history needs manual reconciliation")
    return result["workflow_runs"]


def wait_run(run, sha, workflow, timeout=14400):
    deadline = time.monotonic() + timeout
    while True:
        current = api(f"actions/runs/{run['id']}")
        if (
            current["head_sha"] != sha
            or current["path"] != f".github/workflows/{workflow}"
            or current.get("event") != "workflow_dispatch"
        ):
            raise Error("workflow run identity changed")
        if current["status"] == "completed":
            if current["conclusion"] != "success":
                raise Error(
                    f"workflow {workflow} run {run['id']} needs attention ({current['conclusion']})"
                )
            return current
        if time.monotonic() >= deadline:
            raise Error(
                f"workflow {workflow} run {run['id']} timed out; reconcile it before retrying"
            )
        time.sleep(30)


def dispatch(workflow, ref, sha, inputs):
    started = dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=5)
    api(f"actions/workflows/{workflow}/dispatches", {"ref": ref, "inputs": inputs})
    for _ in range(24):
        matches = [
            run
            for run in runs(workflow, sha)
            if dt.datetime.fromisoformat(run["created_at"].replace("Z", "+00:00"))
            >= started
        ]
        if len(matches) > 1:
            raise Error("multiple matching dispatches; reconcile them before retrying")
        if matches:
            print(f"Started {workflow}: {matches[0]['html_url']}", flush=True)
            return matches[0]
        time.sleep(5)
    raise Error("dispatch result is unknown; do not submit a duplicate")


def build_run(workflow, plan):
    existing = runs(workflow, plan["source_sha"])
    if len(existing) > 1:
        raise Error(f"multiple {workflow} attempts need reconciliation")
    return (
        existing[0]
        if existing
        else dispatch(
            workflow,
            plan["tag"],
            plan["source_sha"],
            {
                "expected_source_commit": plan["source_sha"],
                "distribute_testflight": "false",
            },
        )
    )


def asc_state(build_number=None):
    args = ["ruby", "scripts/store_release_state.rb"]
    if build_number:
        args.append(str(build_number))
    return json.loads(command(*args))


def play_state(expected=None):
    # Its protected job shares the publication lock with every Play upload.
    sha = api("git/ref/heads/master")["object"]["sha"]
    run = dispatch(
        "store-checks.yml",
        "master",
        sha,
        {"expected_play_version_code": str(expected) if expected else ""},
    )
    wait_run(run, sha, "store-checks.yml")
    with tempfile.TemporaryDirectory() as directory:
        command(
            "gh",
            "run",
            "download",
            str(run["id"]),
            "--repo",
            REPO,
            "--name",
            "play-state",
            "--dir",
            directory,
        )
        state = json.loads((Path(directory) / "play-state.json").read_text())
    if expected is not None and int(expected) not in state["production_codes"]:
        raise Error("Play production does not contain the intended version code")
    return state


def validate_plan(plan, key):
    version_tuple(plan["version"])
    if not re.fullmatch(re.escape(plan["version"]) + r"\+\d+", plan["raw_version"]):
        raise Error("snapshot raw version does not preserve the normal patch")
    if not SHA.fullmatch(plan["source_sha"]) or not SHA.fullmatch(plan["base_sha"]):
        raise Error("snapshot has an invalid source commit")
    if (
        plan["schema_version"] != 1
        or plan["release_key"] != key
        or plan["tag"] != f"store-v{plan['version']}"
        or plan["day_tag"] != f"store-{key}"
        or plan["notes_path"]
        != f"distribution/app-store/release-notes-{plan['version']}.json"
        or version_tuple(plan["version"])[2] == 0
    ):
        raise Error("snapshot metadata does not match its immutable tags")
    if command("git", "rev-parse", f"{plan['tag']}^{{commit}}") != plan["source_sha"]:
        raise Error("snapshot version tag changed")
    raw = command("git", "show", f"{plan['source_sha']}:pubspec.yaml")
    if not re.search(rf"^version:\s*{re.escape(plan['raw_version'])}\s*$", raw, re.M):
        raise Error("snapshot source version changed")
    code = command("git", "show", f"{plan['source_sha']}:android/version-code.txt")
    if int(code) != plan["android_version_code"]:
        raise Error("snapshot Android code changed")
    height = command("git", "rev-list", "--count", plan["source_sha"])
    if height != plan["apple_build_number"]:
        raise Error("snapshot Apple build identity changed")
    command("git", "merge-base", "--is-ancestor", plan["source_sha"], "origin/master")
    return plan


def prepare(key, state, play, apply=False):
    if key is not None and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", key):
        raise Error("release key must be YYYY-MM-DD")
    if command("git", "branch", "--show-current") != "master" or command(
        "git", "status", "--porcelain"
    ):
        raise Error("snapshot preparation requires a clean master checkout")
    command("git", "fetch", "origin", "master", "nightly", "--tags")
    command("git", "merge", "--ff-only", "origin/master")
    if command("git", "rev-parse", "HEAD") != command(
        "git", "rev-parse", "origin/master"
    ):
        raise Error("local master contains unpublished work")
    tags = command("git", "tag", "--list").splitlines()
    today = dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).date().isoformat()
    key = release_key(key, tags, today)
    dt.date.fromisoformat(key)
    day_tag = f"store-{key}"
    if day_tag in tags:
        if command("git", "cat-file", "-t", f"refs/tags/{day_tag}") != "tag":
            raise Error("release marker must be an annotated immutable tag")
        plan = json.loads(
            command(
                "git", "for-each-ref", "--format=%(contents)", f"refs/tags/{day_tag}"
            )
        )
        if command("git", "rev-parse", f"{day_tag}^{{commit}}") != plan["source_sha"]:
            raise Error("release marker does not point to its source")
        return validate_plan(plan, key)
    active = [
        version
        for version in state["versions"]
        if version["state"] in SUBMITTED - {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}
    ]
    if active:
        raise Error(
            "an Apple version is already under review or awaiting release; preserve it"
        )
    pubspec = Path("pubspec.yaml").read_text()
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec, re.M)
    if not match:
        raise Error("master has no normal version and numeric build metadata")
    used = [item["version"] for item in state["versions"] + state["trains"]]
    nightly_raw = command("git", "show", "origin/nightly:pubspec.yaml")
    nightly_version = re.search(
        r"^version:[ \t]*(\d+\.\d+\.\d+)(?:\+\d+)?[ \t]*$", nightly_raw, re.M
    )
    if not nightly_version:
        raise Error("nightly has no normal version")
    used.append(nightly_version[1])
    version = choose_version(match[1], used)
    code_floor = [
        Path("android/version-code.txt").read_text().strip(),
        command("git", "show", "origin/nightly:android/version-code.txt"),
        play["highest_version_code"],
    ]
    code_floor.extend(
        tag.removeprefix("play-version-code-")
        for tag in tags
        if re.fullmatch(r"play-version-code-\d+", tag)
    )
    code = next_android_code(code_floor, time.time())
    plan = {
        "schema_version": 1,
        "release_key": key,
        "version": version,
        "raw_version": f"{version}+{int(match[2]) + 1}",
        "base_sha": command("git", "rev-parse", "HEAD"),
        "android_version_code": code,
        "notes_path": f"distribution/app-store/release-notes-{version}.json",
        "tag": f"store-v{version}",
        "day_tag": day_tag,
    }
    if plan["tag"] in tags:
        raise Error("selected version already has a release snapshot")
    if not apply:
        return plan
    Path("pubspec.yaml").write_text(
        pubspec[: match.start()]
        + f"version: {plan['raw_version']}\n"
        + pubspec[match.end() :]
    )
    Path("android/version-code.txt").write_text(f"{code}\n")
    notes = Path(plan["notes_path"])
    if not notes.exists():
        notes.write_text(
            json.dumps(
                {
                    "en-US": f"Mithka {version} includes the latest app updates and maintenance improvements.",
                    "zh-Hans": f"Mithka {version} 包含最新的应用更新与维护改进。",
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n"
        )
    command(
        "git",
        "add",
        "--",
        "pubspec.yaml",
        "android/version-code.txt",
        plan["notes_path"],
    )
    command("git", "diff", "--cached", "--check")
    changed = set(command("git", "diff", "--cached", "--name-only").splitlines())
    allowed = {"pubspec.yaml", "android/version-code.txt", plan["notes_path"]}
    if not {"pubspec.yaml", "android/version-code.txt"} <= changed <= allowed:
        raise Error("snapshot staged unexpected files")
    command("git", "commit", "-m", f"chore: prepare store release {version}")
    plan["source_sha"] = command("git", "rev-parse", "HEAD")
    plan["apple_build_number"] = command("git", "rev-list", "--count", "HEAD")
    for tag in (plan["tag"], day_tag):
        command("git", "tag", "-a", tag, "-m", json.dumps(plan, sort_keys=True))
    # Recheck immediately before one atomic, non-force publication.
    command("git", "fetch", "origin", "master")
    if command("git", "rev-parse", "origin/master") != plan["base_sha"]:
        raise Error(
            "master advanced during snapshot preparation; nothing was published"
        )
    command("git", "push", "--atomic", "origin", "master", plan["tag"], day_tag)
    return validate_plan(plan, key)


def exact_builds(state, plan):
    selected = {}
    for platform in APPLE_WORKFLOWS:
        matches = [
            build
            for build in state["builds"]
            if build["platform"] == platform
            and build["marketing_version"] == plan["version"]
            and build["version"] == plan["apple_build_number"]
        ]
        if len(matches) > 1:
            raise Error("multiple matching Apple builds need reconciliation")
        if not matches or matches[0]["processingState"] == "PROCESSING":
            return None
        build = matches[0]
        if (
            build["processingState"] != "VALID"
            or build.get("expired") is not False
            or build.get("buildAudienceType") != "APP_STORE_ELIGIBLE"
        ):
            raise Error("Apple build is not valid and App Store eligible")
        selected[platform] = build
    return selected


def submit(plan):
    uploads = {
        platform: build_run(workflow, plan)
        for platform, workflow in APPLE_WORKFLOWS.items()
    }
    for platform, run in uploads.items():
        wait_run(run, plan["source_sha"], APPLE_WORKFLOWS[platform])
    deadline = time.monotonic() + 1800
    while True:
        state = asc_state(plan["apple_build_number"])
        builds = exact_builds(state, plan)
        if builds:
            break
        if time.monotonic() >= deadline:
            raise Error("Apple processing is incomplete; resume this snapshot later")
        time.sleep(30)
    master = api("git/ref/heads/master")["object"]["sha"]
    # Validate both listings before any new production publication.
    for operation in ("validate", "submit"):
        if operation == "submit":
            previous = runs("google-play.yml", plan["source_sha"])
            if len(previous) > 1:
                raise Error("multiple Play publication attempts need reconciliation")
            run = (
                previous[0]
                if previous
                else dispatch(
                    "google-play.yml",
                    plan["tag"],
                    plan["source_sha"],
                    {"expected_source_commit": plan["source_sha"]},
                )
            )
            wait_run(run, plan["source_sha"], "google-play.yml")
            play_state(plan["android_version_code"])
        # Sequential: the reusable Quality gate is scoped to workflow + ref.
        for platform in APPLE_WORKFLOWS:
            state = asc_state(plan["apple_build_number"])
            existing = [
                version
                for version in state["versions"]
                if version["platform"] == platform
                and version["version"] == plan["version"]
            ]
            if existing and existing[0]["state"] in SUBMITTED:
                if existing[0]["build_id"] != builds[platform]["id"]:
                    raise Error("submitted version has a different build")
                continue
            if api("git/ref/heads/master")["object"]["sha"] != master:
                raise Error(
                    "store submission workflow changed during release; reconcile before continuing"
                )
            run = dispatch(
                "app-store-submit.yml",
                "master",
                master,
                {
                    "operation": operation,
                    "platform": platform,
                    "version": plan["version"],
                    "binary_version": plan["version"],
                    "build_number": plan["apple_build_number"],
                    "source_commit": plan["source_sha"],
                    "provenance": "github_actions",
                    "build_run_id": str(uploads[platform]["id"]),
                    "uploaded_build_id": builds[platform]["id"],
                    "release_notes_path": plan["notes_path"],
                },
            )
            wait_run(run, master, "app-store-submit.yml")
    state = asc_state(plan["apple_build_number"])
    for platform, build in builds.items():
        versions = [
            version
            for version in state["versions"]
            if version["platform"] == platform and version["version"] == plan["version"]
        ]
        if (
            len(versions) != 1
            or versions[0]["state"] not in SUBMITTED
            or versions[0]["build_id"] != build["id"]
        ):
            raise Error(
                "final App Store submission state did not match the release snapshot"
            )
    print(
        f"Verified {plan['version']}: Play production committed; iOS and macOS submitted.",
        flush=True,
    )


def record_completion(plan):
    # A later Friday must resume any snapshot lacking this verified marker.
    # This is written only after all actual store postconditions pass.
    command("git", "fetch", "origin", "--tags")
    tag = f"store-complete-{plan['release_key']}"
    if tag in command("git", "tag", "--list").splitlines():
        if command("git", "rev-parse", f"{tag}^{{commit}}") != plan["source_sha"]:
            raise Error("completion marker points to another snapshot")
        return
    message = json.dumps(
        {
            "schema_version": 1,
            "version": plan["version"],
            "source_sha": plan["source_sha"],
            "android_version_code": plan["android_version_code"],
            "apple_build_number": plan["apple_build_number"],
            "github_run_id": os.environ.get("GITHUB_RUN_ID"),
            "google_play_verified": True,
            "apple_platforms_verified": ["IOS", "MAC_OS"],
        },
        sort_keys=True,
    )
    command("git", "tag", "-a", tag, plan["source_sha"], "-m", message)
    command("git", "push", "origin", tag)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--operation", choices=["plan", "release"], default="plan")
    parser.add_argument(
        "--release-key",
        default=None,
    )
    args = parser.parse_args()
    assert_context(os.environ)
    play = play_state()
    plan = prepare(
        args.release_key, asc_state(), play, apply=args.operation == "release"
    )
    print(json.dumps(plan, indent=2), flush=True)
    if args.operation == "release":
        submit(plan)
        record_completion(plan)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write(
                f"Store {args.operation}: **{plan['version']}** ({plan.get('source_sha', 'not published')}).\n"
            )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (Error, ValueError, KeyError) as error:
        # Our Error messages contain public identities only. Parsing failures
        # can include raw response fragments, so report only their class.
        print(
            str(error) if isinstance(error, Error) else type(error).__name__, flush=True
        )
        raise SystemExit(1)
