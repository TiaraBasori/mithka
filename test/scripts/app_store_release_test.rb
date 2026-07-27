# frozen_string_literal: true

require "minitest/autorun"
require "stringio"

require_relative "../../scripts/app_store_release"

class AppStoreReleaseTest < Minitest::Test
  RUN_ID = "1d4fc66c-e159-4054-9510-53cec367ed30"
  SOURCE_SHA = "054ff93ff892b4779596f3c602a8d8795d447e3c"
  BUILD_ID = "2f98db03-3385-4fba-b0e2-f685f6ae1bda"
  APP_ID = "6783830742"
  SOURCE_VERSION_ID = "e7ed3f48-e93d-4f33-ba99-0feb84454462"
  TARGET_VERSION_ID = "3a297302-6ebd-499b-86aa-e57ae6da4766"
  SUBMISSION_ID = "51460acf-3238-49cc-bf75-1f4687bb73cd"

  class FakeClient
    attr_reader :writes

    def initialize(routes)
      @routes = routes
      @writes = []
    end

    def get(path, params = {})
      value = @routes.fetch([path, params]) { @routes.fetch(path) }
      Marshal.load(Marshal.dump(value))
    end

    def post(path, body)
      @writes << [:post, path, body]
      raise "unexpected POST #{path}"
    end

    def patch(path, body)
      @writes << [:patch, path, body]
      raise "unexpected PATCH #{path}"
    end
  end

  class SubmissionClient
    attr_reader :writes

    def initialize(version_state: "PREPARE_FOR_SUBMISSION", has_item: false)
      @version_string = "0.7.41"
      @version_state = version_state
      @has_item = has_item
      @submission_state = "READY_FOR_REVIEW"
      @writes = []
    end

    def get(path, params = {})
      case [path, params]
      when ["/appStoreVersions/#{TARGET_VERSION_ID}", {}]
        { "data" => { "id" => TARGET_VERSION_ID, "attributes" => { "appStoreState" => @version_state, "versionString" => @version_string } } }
      when ["/apps/#{APP_ID}/reviewSubmissions", { "filter[platform]" => "IOS", "limit" => "200" }]
        { "data" => [{ "id" => SUBMISSION_ID, "attributes" => { "state" => @submission_state } }] }
      when ["/reviewSubmissions/#{SUBMISSION_ID}/items", { "limit" => "200" }]
        items = if @has_item
                  [{
                    "id" => "item",
                    "attributes" => { "state" => "READY_FOR_REVIEW" },
                    "relationships" => {
                      "appStoreVersion" => { "data" => { "type" => "appStoreVersions", "id" => TARGET_VERSION_ID } }
                    }
                  }]
                else
                  []
                end
        { "data" => items }
      when ["/apps/#{APP_ID}/appStoreVersions", { "filter[platform]" => "IOS", "filter[versionString]" => "0.7.0", "limit" => "50" }]
        { "data" => [] }
      when ["/reviewSubmissions/#{SUBMISSION_ID}", {}]
        { "data" => { "id" => SUBMISSION_ID, "attributes" => { "state" => @submission_state } } }
      else
        raise "unexpected GET #{path} #{params}"
      end
    end

    def post(path, body)
      @writes << [:post, path, body]
      raise "unexpected POST #{path}" unless path == "/reviewSubmissionItems"

      { "data" => { "id" => "item", "attributes" => { "state" => "READY_FOR_REVIEW" } } }
    end

    def patch(path, body)
      @writes << [:patch, path, body]
      if path == "/appStoreVersions/#{TARGET_VERSION_ID}"
        @version_string = body.dig("data", "attributes", "versionString")
        return { "data" => { "id" => TARGET_VERSION_ID, "attributes" => { "versionString" => @version_string } } }
      end
      if path == "/reviewSubmissions/#{SUBMISSION_ID}"
        @submission_state = "WAITING_FOR_REVIEW"
        return { "data" => { "id" => SUBMISSION_ID, "attributes" => { "state" => @submission_state } } }
      end

      raise "unexpected PATCH #{path}"
    end
  end

  def test_dry_run_resolves_binary_version_separately_from_listing_version
    client = FakeClient.new(base_routes)
    output = StringIO.new

    runner = build_runner(client, output)
    runner.run

    assert_equal BUILD_ID, runner.resolved_build_id
    assert_empty client.writes
    assert_includes output.string, "binary 0.7.0 (345)"
    assert_includes output.string, "listing version 0.7.41"
    assert_includes output.string, "PLAN submit through reviewSubmissions"
    assert_includes output.string, "no App Store Connect state was changed"
  end

  def test_source_commit_must_match_exactly
    routes = base_routes
    routes["/ciBuildRuns/#{RUN_ID}"]["data"]["attributes"]["sourceCommit"]["commitSha"] = "a" * 40
    client = FakeClient.new(routes)

    error = assert_raises(MithkaAppStoreRelease::Error) do
      build_runner(client, StringIO.new).run
    end
    assert_includes error.message, "expected #{SOURCE_SHA}"
    assert_empty client.writes
  end

  def test_binary_marketing_version_must_match
    routes = base_routes
    routes["/builds/#{BUILD_ID}/preReleaseVersion"]["data"]["attributes"]["version"] = "0.7.1"
    client = FakeClient.new(routes)

    error = assert_raises(MithkaAppStoreRelease::Error) do
      build_runner(client, StringIO.new).run
    end
    assert_includes error.message, "binary marketing version 0.7.1, expected 0.7.0"
    assert_empty client.writes
  end

  def test_mismatched_binary_is_submitted_without_renaming_listing
    client = SubmissionClient.new
    runner = build_runner(client, StringIO.new, apply: true)

    submission = runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_equal "WAITING_FOR_REVIEW", submission.dig("attributes", "state")
    mutations = client.writes.map do |method, path, body|
      if path == "/appStoreVersions/#{TARGET_VERSION_ID}"
        [method, path, body.dig("data", "attributes", "versionString")]
      else
        [method, path]
      end
    end
    assert_equal [
      [:post, "/reviewSubmissionItems"],
      [:patch, "/reviewSubmissions/#{SUBMISSION_ID}"]
    ], mutations
  end

  def test_dry_run_with_active_submission_never_writes
    client = SubmissionClient.new
    output = StringIO.new
    runner = build_runner(client, output, apply: false)

    submission = runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_equal "READY_FOR_REVIEW", submission.dig("attributes", "state")
    assert_empty client.writes
    assert_includes output.string, "PLAN add version 0.7.41"
    assert_includes output.string, "PLAN submit review submission"
  end

  def test_ready_for_review_version_is_resumable
    client = SubmissionClient.new(version_state: "READY_FOR_REVIEW", has_item: true)
    runner = build_runner(client, StringIO.new, apply: true)

    version =
      { "id" => TARGET_VERSION_ID, "attributes" => { "appStoreState" => "READY_FOR_REVIEW" } }
    runner.send(
      :ensure_version_can_be_used!,
      version
    )
    submission = runner.send(:ensure_submission, TARGET_VERSION_ID)

    assert_equal "WAITING_FOR_REVIEW", submission.dig("attributes", "state")
    assert_equal [[:patch, "/reviewSubmissions/#{SUBMISSION_ID}"]], client.writes.map { |method, path, _body| [method, path] }
  end

  def test_dry_run_with_existing_partial_version_plans_without_strict_verification
    routes = base_routes.merge(
      ["/apps/#{APP_ID}/appStoreVersions", {
        "filter[platform]" => "IOS",
        "filter[versionString]" => "0.7.41",
        "limit" => "50"
      }] => {
        "data" => [{ "id" => TARGET_VERSION_ID, "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION", "versionString" => "0.7.41" } }]
      },
      ["/appStoreVersions/#{TARGET_VERSION_ID}", { "include" => "build" }] => {
        "data" => {
          "id" => TARGET_VERSION_ID,
          "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION", "versionString" => "0.7.41" },
          "relationships" => { "build" => { "data" => nil } }
        }
      },
      ["/appStoreVersions/#{TARGET_VERSION_ID}/appStoreVersionLocalizations", { "limit" => "200" }] => {
        "data" => %w[en-US zh-Hans].map do |locale|
          {
            "id" => "target-localization-#{locale}",
            "attributes" => {
              "locale" => locale,
              "description" => "Description",
              "keywords" => "chat,messaging",
              "supportUrl" => "https://example.com/support",
              "whatsNew" => "Old notes"
            }
          }
        end
      },
      "/appStoreVersions/#{TARGET_VERSION_ID}/appStoreReviewDetail" => {
        "data" => base_routes.fetch("/appStoreVersions/#{SOURCE_VERSION_ID}/appStoreReviewDetail").fetch("data")
      },
      "/appStoreVersions/#{TARGET_VERSION_ID}" => {
        "data" => { "id" => TARGET_VERSION_ID, "attributes" => { "appStoreState" => "PREPARE_FOR_SUBMISSION", "versionString" => "0.7.41" } }
      },
      ["/apps/#{APP_ID}/reviewSubmissions", { "filter[platform]" => "IOS", "limit" => "200" }] => {
        "data" => [{ "id" => SUBMISSION_ID, "attributes" => { "state" => "READY_FOR_REVIEW" } }]
      },
      ["/reviewSubmissions/#{SUBMISSION_ID}/items", { "limit" => "200" }] => { "data" => [] }
    )
    client = FakeClient.new(routes)
    output = StringIO.new

    build_runner(client, output).run

    assert_empty client.writes
    assert_includes output.string, "PLAN attach build 345"
    assert_includes output.string, "PLAN update en-US release notes"
    assert_includes output.string, "DRY RUN complete"
  end

  private

  def build_runner(client, output, apply: false)
    MithkaAppStoreRelease::Runner.new(
      client: client,
      app_id: APP_ID,
      version: "0.7.41",
      binary_version: "0.7.0",
      build_number: "345",
      ci_build_run_id: RUN_ID,
      source_commit: SOURCE_SHA,
      release_notes: MithkaAppStoreRelease::DEFAULT_RELEASE_NOTES,
      apply: apply,
      submit: true,
      out: output
    )
  end

  def base_routes
    {
      "/ciBuildRuns/#{RUN_ID}" => {
        "data" => {
          "id" => RUN_ID,
          "attributes" => {
            "executionProgress" => "COMPLETE",
            "completionStatus" => "SUCCEEDED",
            "sourceCommit" => { "commitSha" => SOURCE_SHA }
          }
        }
      },
      ["/ciBuildRuns/#{RUN_ID}/builds", { "limit" => "200" }] => {
        "data" => [
          {
            "id" => BUILD_ID,
            "attributes" => {
              "version" => "345",
              "processingState" => "VALID",
              "expired" => false,
              "buildAudienceType" => "APP_STORE_ELIGIBLE"
            }
          }
        ]
      },
      "/builds/#{BUILD_ID}/app" => {
        "data" => { "type" => "apps", "id" => APP_ID }
      },
      "/builds/#{BUILD_ID}/preReleaseVersion" => {
        "data" => {
          "type" => "preReleaseVersions",
          "id" => "prerelease",
          "attributes" => { "version" => "0.7.0" }
        }
      },
      ["/apps/#{APP_ID}/appStoreVersions", {
        "filter[platform]" => "IOS",
        "filter[versionString]" => "0.7.41",
        "limit" => "50"
      }] => { "data" => [] },
      ["/apps/#{APP_ID}/appStoreVersions", {
        "filter[platform]" => "IOS",
        "filter[appStoreState]" => "READY_FOR_SALE",
        "limit" => "50"
      }] => {
        "data" => [{ "id" => SOURCE_VERSION_ID, "attributes" => { "appStoreState" => "READY_FOR_SALE", "createdDate" => "2026-07-14T00:00:00Z" } }]
      },
      ["/appStoreVersions/#{SOURCE_VERSION_ID}/appStoreVersionLocalizations", { "limit" => "200" }] => {
        "data" => %w[en-US zh-Hans].map do |locale|
          {
            "id" => "localization-#{locale}",
            "attributes" => {
              "locale" => locale,
              "description" => "Description",
              "keywords" => "chat,messaging",
              "supportUrl" => "https://example.com/support"
            }
          }
        end
      },
      "/appStoreVersions/#{SOURCE_VERSION_ID}/appStoreReviewDetail" => {
        "data" => {
          "id" => "review-detail",
          "attributes" => {
            "contactEmail" => "review@example.com",
            "contactFirstName" => "App",
            "contactLastName" => "Review",
            "contactPhone" => "+10000000000",
            "demoAccountRequired" => true,
            "demoAccountName" => "reviewer",
            "demoAccountPassword" => "secret",
            "notes" => "Sign in with the review account."
          }
        }
      }
    }
  end

end
