# Benchmark Methodology

Qem benchmark results are only useful if the workload and measurement conditions
are explicit. This file defines the baseline methodology for `0.5.x`
performance work.

## Principles

- Prefer reproducible local engineering numbers over marketing-sized claims.
- Always separate clean mmap paths from edited piece-table paths.
- Treat cold-cache and warm-cache numbers as different workloads.
- Include worst-case search paths such as `no-match`, not just first-match wins.
- Report the command that was run, the machine, and the storage class.

## Workload Matrix

The current benchmark families in `benches/document_perf.rs` cover:

- clean large-file open and incremental indexing
- viewport reads on clean mmap documents
- viewport reads after piece-table edits
- session-layer overhead relative to raw `Document`
- typed bounded reads through `read_text(...)` and `read_selection(...)`
- literal search on `mmap`, `piece_table`, and fragmented `piece_table`
- literal search variants:
  - `find_next`
  - `find_prev`
  - reusable query search
  - reusable query iterators (`find_all_query*`)
  - middle-anchor search
  - `no-match`
  - dense-match iterator throughput over the first `512` matches
  - bounded dense-match iterators over a representative window, also capped to the
    first `512` matches so local Criterion runs stay practical while still
    exercising the hot iterator path
- piece-table compaction
- full text materialization
- typed edit commands
- streaming save paths

## Measurement Rules

When publishing results, record:

- commit SHA
- Rust toolchain version
- OS and filesystem
- CPU model
- RAM size
- storage type
- whether Windows Defender / other AV was active
- whether the run was cold or warm

For search and read workloads, publish both:

- clean mmap numbers
- edited piece-table numbers

For search specifically, include at least:

- exact match from start
- exact match from a middle anchor
- `find_prev` from end or a middle anchor
- `no-match`
- dense-match

## Recommended Commands

Run the full benchmark suite:

```powershell
cargo bench --bench document_perf
```

Focus on literal search:

```powershell
cargo bench --bench document_perf -- literal_search
```

Compile the benchmark binary without running it:

```powershell
cargo bench --bench document_perf --no-run
```

Focus on session-layer overhead:

```powershell
cargo bench --bench document_perf -- session_layer
```

Focus on maintenance snapshot overhead for fragmented piece-table documents:

```powershell
cargo bench --bench document_perf -- maintenance_status
```

Probe a real file outside the synthetic Criterion fixtures:

```powershell
cargo run --example perf_probe -- .\huge.log --needle ERROR --seed-edit "[probe]\n" --save .\copy.log
```

Probe capped `find_all` iterator throughput without waiting on full Criterion dense-match runs:

```powershell
cargo run --example perf_probe -- .\huge.log --needle 00 --find-all-limit 512 --find-all-range-lines 2048
```

For machine-readable output:

```powershell
cargo run --example perf_probe -- .\huge.log --needle ERROR --json
```

Use `perf_probe` when you want a manual matrix for `1GB / 10GB / 50GB` files:

- run once after a reboot or cache flush for a cold-ish data point
- run again immediately for a warm-cache data point
- repeat with and without `--seed-edit` to separate clean mmap from edited paths
- keep the exact command line and machine/storage notes next to the numbers

If you want a repeatable JSONL export instead of running those commands by
hand, use the helper script:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\collect_perf_matrix.ps1 `
  .\huge-1gb.log, .\huge-10gb.log `
  -Needle ERROR `
  -FindAllLimit 128 `
  -FindAllRangeLines 2048 `
  -Repeats 3 `
  -MatrixLabel warm `
  -OutputJsonl .\target\perf-matrix.jsonl
```

The script records `clean` and `edited` runs separately by default, annotates
each JSON row with matrix metadata, and keeps the raw `perf_probe` numbers
machine-readable for later spreadsheets or notebooks. It does not fake cold
cache: if you need a true cold-cache row, reboot or flush caches first and then
run the script for that labeled pass.

To turn that JSONL into one quick markdown table with medians/min/max:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\summarize_perf_matrix.ps1 `
  -InputJsonl .\target\perf-matrix.jsonl `
  -OutputMarkdown .\target\perf-matrix-summary.md
```

## Publishing Guidance

When sharing numbers publicly:

- keep Criterion confidence intervals, not just a single median
- avoid mixing cold and warm results in one table
- call out fragmented vs non-fragmented edited documents explicitly
- avoid comparing runs from different machines without saying so
- prefer a small honest matrix over a single oversized headline number
