import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[2] / "scripts/weekly_store_release.py"
SPEC = importlib.util.spec_from_file_location("weekly_store_release", SOURCE)
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


class WeeklyReleaseTest(unittest.TestCase):
    def test_a_later_friday_resumes_unfinished_snapshots_before_allocating(self):
        tags = ["store-2026-10-27", "store-v1.8.8"]
        self.assertEqual(RELEASE.release_key(None, tags, "2026-10-30"), "2026-10-27")
        with self.assertRaises(RELEASE.Error):
            RELEASE.release_key("2026-10-30", tags, "2026-10-30")
        tags.append("store-complete-2026-10-27")
        self.assertEqual(RELEASE.release_key(None, tags, "2026-10-30"), "2026-10-30")
        tags.extend(["store-2026-10-29", "store-2026-10-30"])
        with self.assertRaises(RELEASE.Error):
            RELEASE.release_key(None, tags, "2026-11-06")

    def test_normal_patch_is_preserved_or_advanced_above_used_versions(self):
        self.assertEqual(RELEASE.choose_version("1.8.6", ["1.7.11", "1.8.5"]), "1.8.6")
        self.assertEqual(RELEASE.choose_version("1.8.6", ["1.8.7", "1.8.4"]), "1.8.8")
        self.assertEqual(RELEASE.choose_version("1.8.0", []), "1.8.1")
        self.assertEqual(RELEASE.choose_version("1.8.11", ["1.8.9"]), "1.8.11")

    def test_new_major_or_minor_and_abnormal_versions_require_attention(self):
        for used in [["1.9.0"], ["2.0.1"], ["1.8"], ["1.8.01"]]:
            with self.subTest(used=used), self.assertRaises(RELEASE.Error):
                RELEASE.choose_version("1.8.6", used)

    def test_android_code_exceeds_live_and_nightly_even_if_clock_lags(self):
        self.assertEqual(RELEASE.next_android_code([100, 300, 200], 250), 301)
        self.assertEqual(RELEASE.next_android_code([100], 350), 350)
        with self.assertRaises(RELEASE.Error):
            RELEASE.next_android_code([2100000000], 100)

    def test_provider_and_branch_context_cannot_be_overridden(self):
        good = {
            "GITHUB_REPOSITORY": "iebb/mithka",
            "GITHUB_REF": "refs/heads/master",
            "GITHUB_EVENT_NAME": "schedule",
        }
        RELEASE.assert_context(good)
        for key, value in [
            ("GITHUB_REPOSITORY", "attacker/mithka"),
            ("GITHUB_REF", "refs/heads/nightly"),
            ("GITHUB_EVENT_NAME", "pull_request"),
        ]:
            with self.assertRaises(RELEASE.Error):
                RELEASE.assert_context(dict(good, **{key: value}))

    def test_failed_or_changed_native_run_is_never_treated_as_success(self):
        run = {"id": 10}
        state = {
            "head_sha": "a" * 40,
            "path": ".github/workflows/ios-testflight.yml",
            "event": "workflow_dispatch",
            "status": "completed",
            "conclusion": "failure",
        }
        with (
            patch.object(RELEASE, "api", return_value=state),
            self.assertRaises(RELEASE.Error),
        ):
            RELEASE.wait_run(run, "a" * 40, "ios-testflight.yml")
        state["conclusion"] = "success"
        with (
            patch.object(RELEASE, "api", return_value=state),
            self.assertRaises(RELEASE.Error),
        ):
            RELEASE.wait_run(run, "b" * 40, "ios-testflight.yml")

    def test_existing_upload_attempt_is_resumed_without_redispatch(self):
        with (
            patch.object(RELEASE, "runs", return_value=[{"id": 10}]),
            patch.object(RELEASE, "dispatch") as dispatch,
        ):
            self.assertEqual(
                RELEASE.build_run("ios-testflight.yml", {"source_sha": "a" * 40}),
                {"id": 10},
            )
            dispatch.assert_not_called()

    def test_ambiguous_upload_attempts_block(self):
        with (
            patch.object(RELEASE, "runs", return_value=[{"id": 10}, {"id": 11}]),
            patch.object(RELEASE, "dispatch") as dispatch,
        ):
            with self.assertRaises(RELEASE.Error):
                RELEASE.build_run("ios-testflight.yml", {"source_sha": "a" * 40})
            dispatch.assert_not_called()

    def test_exact_builds_require_both_platforms_and_app_store_eligibility(self):
        plan = {"version": "1.8.8", "apple_build_number": "1698"}
        builds = [
            {
                "id": platform,
                "platform": platform,
                "marketing_version": "1.8.8",
                "version": "1698",
                "processingState": "VALID",
                "expired": False,
                "buildAudienceType": "APP_STORE_ELIGIBLE",
            }
            for platform in ["IOS", "MAC_OS"]
        ]
        self.assertEqual(
            set(RELEASE.exact_builds({"builds": builds}, plan)), {"IOS", "MAC_OS"}
        )
        self.assertIsNone(RELEASE.exact_builds({"builds": builds[:1]}, plan))
        builds[1]["buildAudienceType"] = "INTERNAL_ONLY"
        with self.assertRaises(RELEASE.Error):
            RELEASE.exact_builds({"builds": builds}, plan)

    def test_store_submission_validates_both_apple_plans_before_play_and_verifies_poststate(
        self,
    ):
        plan = {
            "version": "1.8.8",
            "apple_build_number": "1698",
            "source_sha": "a" * 40,
            "tag": "store-v1.8.8",
            "android_version_code": 500,
            "notes_path": "distribution/app-store/release-notes-1.8.8.json",
        }
        state = {
            "versions": [],
            "builds": [
                {
                    "id": platform,
                    "platform": platform,
                    "marketing_version": "1.8.8",
                    "version": "1698",
                    "processingState": "VALID",
                    "expired": False,
                    "buildAudienceType": "APP_STORE_ELIGIBLE",
                }
                for platform in ["IOS", "MAC_OS"]
            ],
        }
        events = []

        def dispatch(workflow, ref, sha, inputs):
            events.append((workflow, inputs.get("operation"), inputs.get("platform")))
            if workflow == "app-store-submit.yml" and inputs["operation"] == "submit":
                state["versions"].append(
                    {
                        "platform": inputs["platform"],
                        "version": "1.8.8",
                        "build_id": inputs["uploaded_build_id"],
                        "state": "WAITING_FOR_REVIEW",
                    }
                )
            return {"id": len(events)}

        with (
            patch.object(RELEASE, "build_run", return_value={"id": 10}),
            patch.object(RELEASE, "wait_run"),
            patch.object(RELEASE, "asc_state", return_value=state),
            patch.object(RELEASE, "api", return_value={"object": {"sha": "b" * 40}}),
            patch.object(RELEASE, "runs", return_value=[]),
            patch.object(RELEASE, "dispatch", side_effect=dispatch),
            patch.object(RELEASE, "play_state") as play,
        ):
            RELEASE.submit(plan)
            play.assert_called_once_with(500)
        self.assertEqual(
            events,
            [
                ("app-store-submit.yml", "validate", "IOS"),
                ("app-store-submit.yml", "validate", "MAC_OS"),
                ("google-play.yml", None, None),
                ("app-store-submit.yml", "submit", "IOS"),
                ("app-store-submit.yml", "submit", "MAC_OS"),
            ],
        )

    def test_existing_failed_play_run_is_not_redispatched_or_followed_by_asc_submission(
        self,
    ):
        plan = {
            "version": "1.8.8",
            "apple_build_number": "1698",
            "source_sha": "a" * 40,
            "tag": "store-v1.8.8",
            "android_version_code": 500,
            "notes_path": "distribution/app-store/release-notes-1.8.8.json",
        }
        builds = {platform: {"id": platform} for platform in ["IOS", "MAC_OS"]}

        def wait(run, *_args):
            if run["id"] == 99:
                raise RELEASE.Error("failed publication")

        with (
            patch.object(RELEASE, "build_run", return_value={"id": 10}),
            patch.object(RELEASE, "wait_run", side_effect=wait),
            patch.object(RELEASE, "asc_state", return_value={"versions": []}),
            patch.object(RELEASE, "exact_builds", return_value=builds),
            patch.object(RELEASE, "api", return_value={"object": {"sha": "b" * 40}}),
            patch.object(RELEASE, "runs", return_value=[{"id": 99}]),
            patch.object(RELEASE, "dispatch", return_value={"id": 20}) as dispatch,
        ):
            with self.assertRaises(RELEASE.Error):
                RELEASE.submit(plan)
            self.assertEqual(dispatch.call_count, 2)
            self.assertTrue(
                all(
                    call.args[0] == "app-store-submit.yml"
                    and call.args[3]["operation"] == "validate"
                    for call in dispatch.call_args_list
                )
            )

    def test_snapshot_publication_and_resume_use_real_git_and_immutable_tags(self):
        # Exercise the production allocator against a local bare remote. No
        # signing keys, provider credentials or real repository writes.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            remote = root / "remote.git"
            repo = root / "repo"
            subprocess.run(
                ["git", "init", "--bare", "--initial-branch=master", str(remote)],
                check=True,
                capture_output=True,
            )
            subprocess.run(
                ["git", "clone", str(remote), str(repo)],
                check=True,
                capture_output=True,
            )
            previous = Path.cwd()
            os.chdir(repo)
            try:
                RELEASE.command("git", "config", "user.name", "Store test")
                RELEASE.command("git", "config", "user.email", "test@example.com")
                Path("pubspec.yaml").write_text(
                    "name: example\nversion: 1.8.6+295\n\ndependencies: {}\n"
                )
                Path("android").mkdir()
                Path("android/version-code.txt").write_text("100\n")
                Path("distribution/app-store").mkdir(parents=True)
                RELEASE.command("git", "add", ".")
                RELEASE.command("git", "commit", "-m", "Initial")
                RELEASE.command("git", "push", "origin", "master", "master:nightly")
                state = {"versions": [], "trains": [{"version": "1.8.7"}]}
                play = {"highest_version_code": 400}
                with patch.object(RELEASE.time, "time", return_value=200):
                    planned = RELEASE.prepare("2026-10-30", state, play)
                    self.assertEqual(planned["version"], "1.8.8")
                    self.assertEqual(planned["android_version_code"], 401)
                    self.assertEqual(
                        RELEASE.command("git", "status", "--porcelain"), ""
                    )
                    plan = RELEASE.prepare("2026-10-30", state, play, apply=True)
                self.assertEqual(plan["apple_build_number"], "2")
                self.assertEqual(
                    RELEASE.command(
                        "git", "ls-remote", "origin", "refs/heads/master"
                    ).split()[0],
                    plan["source_sha"],
                )
                self.assertIn("dependencies: {}", Path("pubspec.yaml").read_text())
                self.assertEqual(RELEASE.command("git", "status", "--porcelain"), "")
                # A retry must keep the same source/code despite a higher live
                # version or clock. It must not allocate a second release.
                resumed = RELEASE.prepare(
                    "2026-10-30",
                    {"versions": [], "trains": [{"version": "1.8.10"}]},
                    {"highest_version_code": 900},
                    apply=True,
                )
                self.assertEqual(resumed, plan)
                self.assertEqual(
                    RELEASE.command("git", "rev-list", "--count", "HEAD"), "2"
                )
                # The next date cannot conceal an unresolved publication.
                with self.assertRaises(RELEASE.Error):
                    RELEASE.prepare("2026-10-31", state, play, apply=True)
                RELEASE.record_completion(plan)
                self.assertEqual(
                    RELEASE.command(
                        "git",
                        "ls-remote",
                        "origin",
                        "refs/tags/store-complete-2026-10-30^{}",
                    ).split()[0],
                    plan["source_sha"],
                )
                with self.assertRaises(RELEASE.Error):
                    RELEASE.prepare(
                        "2026-10-31",
                        {"versions": [{"state": "WAITING_FOR_REVIEW"}], "trains": []},
                        play,
                        apply=True,
                    )
            finally:
                os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
