# EOSG 2.3.1 (vendored for IONFALL, decision 0005)

Source: https://github.com/3ddelano/epic-online-services-godot release 2.3.1
(MIT, see LICENSE.md). Bundles Epic's EOS SDK binaries, used under Epic's
EOS SDK terms.

Local changes:
- Only `eos.gd`, `dataclass.gd`, `base_class.gd`, `eosg.gdextension` and the
  release (not debug) wrapper libraries for the
  Linux x86_64, Windows x86_64 and Android are kept; `eosg.gdextension` maps
  debug builds to them too (saves ~60 MB of LFS). The `heos/`
  helpers, runtime autoload and editor plugin are removed; IONFALL calls the
  EOS interfaces directly from `net/online/eos_backend.gd` and registers its
  own `EOSGRuntime` (`net/online/eos_runtime.gd`).
- `eos.gd`: one default reading `HAuth.product_user_id` now reads
  `EOSGRuntime.local_product_user_id`; inner `class Platform` renamed `PlatformSdk` (clashed with the
  game's `Platform` autoload).
- `bin/linux/*`: rebuilt from the 2.3.1 source on Ubuntu 22.04 (g++ 11)
  against EOS SDK 1.19.2.1, so they need glibc ≤ 2.34 (the release build
  needs 2.38). The patched SConstruct only replaces a Python 3.12 f-string.
  Windows and Android libraries are the release's (EOS SDK 1.19.1.2).
