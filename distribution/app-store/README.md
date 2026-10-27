# App Store review from GitHub

The [iOS TestFlight](https://github.com/iebb/mithka/actions/workflows/ios-testflight.yml)
and [macOS TestFlight](https://github.com/iebb/mithka/actions/workflows/macos-testflight.yml)
workflows build, sign and upload binaries. App Review is a separate manual step:

1. Open [App Store Review Submission](https://github.com/iebb/mithka/actions/workflows/app-store-submit.yml), select `master`, and click **Run workflow**.
2. Select `IOS` or `MAC_OS`, the listing version, exact binary version/build number and full source commit SHA.
3. For `github_actions`, provide the completed upload workflow run ID and the ASC build UUID. For `xcode_cloud`, provide the Xcode Cloud run UUID and leave the ASC build UUID empty. The existing release verifier checks the selected build's app, platform, version, source provenance, processing state and App Store eligibility.
4. Provide the path to a committed release-notes JSON under `distribution/app-store/`, containing exactly `en-US` and `zh-Hans` text. For example: `distribution/app-store/release-notes-1.7.11.json`. Use release notes appropriate to the selected version.
5. Run `validate` first. It plans the review submission without changing ASC. Select `submit` to create/update the listing, attach that exact build, copy the existing review details and metadata, and submit to App Review. The workflow verifies the resulting version and review-submission state. New versions use the existing release script's `AFTER_APPROVAL` behavior.

The workflow runs the required Quality gate before accessing ASC credentials.
It never selects a build merely because it is the latest upload.
Completed historical submissions whose items for the selected version were
removed are ignored. Multiple remaining submissions still block publication.

Required repository secrets are `APP_STORE_CONNECT_KEY_ID`,
`APP_STORE_CONNECT_ISSUER_ID` and `APP_STORE_CONNECT_PRIVATE_KEY` (raw `.p8`
contents). Existing build/signing workflows continue to use their Apple signing,
Telegram and Firebase secrets. Keys are written only to a temporary file on the
runner and deleted when the step exits.

Run [Store Workflow Checks](https://github.com/iebb/mithka/actions/workflows/store-checks.yml)
on `master` to test both store credentials. It performs an ASC app lookup and a
Play track lookup using a temporary edit that is deleted without committing.
Pull-request and push runs execute only offline tests and workflow validation.
