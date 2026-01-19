# Changelog

## [1.1.0](https://github.com/flxbl-io/build-domain/compare/v1.0.0...v1.1.0) (2026-01-19)


### Features

* add domain and release-candidate outputs to build-domain ([c76243b](https://github.com/flxbl-io/build-domain/commit/c76243b649dc5a15666d2ada89526d158f1108ca))
* add serialization support and convert to Node.js action ([f4ddb48](https://github.com/flxbl-io/build-domain/commit/f4ddb484e8b7a9df585ba62398a90995fde26a95))
* add two-phase locking with global publish lock ([4781b84](https://github.com/flxbl-io/build-domain/commit/4781b84d11a2181ab394544a2d230813e9ef411c))
* fetch GitHub token from SFP Server ([43650ba](https://github.com/flxbl-io/build-domain/commit/43650ba77bd4486a01d23b663d4c91dce63d4e56))


### Bug Fixes

* make npm-scope optional in publish and release candidate ([246d7b8](https://github.com/flxbl-io/build-domain/commit/246d7b8ae4672798b50cdadb4d10fa33b8252c6e))

## 1.0.0 (2026-01-12)


### Features

* add local test runner script ([4ed0823](https://github.com/flxbl-io/build-domain/commit/4ed08238ceb736382b7cfe80b1b20cfaebf669ef))
* add npm input for external registry, fix scope handling, improve artifact check ([d406ac1](https://github.com/flxbl-io/build-domain/commit/d406ac121e380cc789ebb166c404f68c8656d734))
* add shared sfp stack detection with .env support ([b3915c1](https://github.com/flxbl-io/build-domain/commit/b3915c17718529b66e0d1ec2703acbe54a480680))
* add test scripts (local and act) ([5880766](https://github.com/flxbl-io/build-domain/commit/5880766fec3f9cdbce6bb417d4567f0390d7b391))
* auto-detect sfp workspace and image in test script ([694741f](https://github.com/flxbl-io/build-domain/commit/694741f1fa150d8552de37bbfb47f1e5658719c3))
* initial build action ([34f336e](https://github.com/flxbl-io/build-domain/commit/34f336e2d0dd75d5cac83d488d6b55c65530a79a))


### Bug Fixes

* add --pull=false to use local docker image ([c26239b](https://github.com/flxbl-io/build-domain/commit/c26239bb1c99b87a1d9567b59b682ede3a8be88d))
* make git fetch non-fatal for local testing ([434675b](https://github.com/flxbl-io/build-domain/commit/434675bfef3c1e46ad1700645d681c4f17cc4565))
