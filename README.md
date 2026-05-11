# benchmark-hugo-go

Public Hugo Go benchmark runner for BoringCache vs GitHub Actions cache.

This repo exists separately from [`boringcache/benchmarks`](https://github.com/boringcache/benchmarks) so the benchmark keeps:

- one pinned upstream source commit
- isolated GitHub Actions cache usage
- one per-repo BoringCache workspace name: `boringcache/benchmark-hugo-go`
- independent workflow history plus upstream-sync-driven benchmark runs and manual dispatches

## Source Model

- Upstream source lives in the pinned `upstream/` submodule.

Pinned upstream source:

- see committed `upstream/` submodule on `main`

## What It Measures

Fresh lane runs the same scenario set for each backend:

- `cold`
- `warm1`

Rolling lane records only the first build after upstream sync and intentionally skips `warm1`.

The story this benchmark is meant to show is:

- speed on fresh cold and warm paths
- first-build behavior after upstream sync in the rolling lane
- storage footprint in each backend
- cache reuse through BoringCache's native Go `GOCACHEPROG` proxy path

## Cache Shape

BoringCache uses `boringcache/one` with `mode: go` for the native Go build-cache path and archives only `go-mod-cache` so module downloads stay comparable on fresh runners.

GitHub Actions cache stores:

- `GOMODCACHE`
- `GOCACHE`

## Token Model

This repo uses split BoringCache tokens as the standard CI shape:

- `BORINGCACHE_RESTORE_TOKEN` for read-only restore and proxy access
- `BORINGCACHE_SAVE_TOKEN` for trusted write paths
- `BORINGCACHE_API_TOKEN` only where a single bearer variable is still required for compatibility
