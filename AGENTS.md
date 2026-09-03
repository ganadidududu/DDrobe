# COORDIT workspace instructions

## iOS Simulator workflow

- Use SimSlim (`simslim`) for iOS Simulator discovery, boot, shutdown, cloning, and slimming.
- Before building or running on a simulator, run `simslim list --json`, then apply `config/simslim/coordit-dev.json` with `simslim on <udid> --profile config/simslim/coordit-dev.json`.
- Verify the applied profile with `simslim verify <udid> --profile config/simslim/coordit-dev.json`.
- Before testing authentication, purchases, links, or photo import, run `simslim doctor <udid> --requires push,storekit,universal-links,keychain-sync,photos`.
- Use `xcodebuild` or Xcode tooling for compilation, installation, launch, UI automation, and logs after SimSlim has prepared the simulator.
- Do not run `simslim erase`, `simslim delete`, or `simslim disk-clean` without explicit user authorization.
