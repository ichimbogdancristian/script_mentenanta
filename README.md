# Windows Maintenance Automation

An unattended Windows 10/11 maintenance tool. A single batch launcher (`script.bat`) downloads/extracts the project, elevates to admin, and runs a PowerShell 7 orchestrator that audits the system, applies fixes, generates an HTML report, and cleans up after itself.

> **Read this before running it on a machine you care about.** This tool changes registry values, services, scheduled tasks, installed applications (via winget/choco), Windows Update state, and security policy (`secedit`/`auditpol`/`net accounts`). It is designed to run unattended, and by default it **deletes its own project folder and can reboot the machine** at the end of a run.

## What it does

1. **`script.bat`** — self-elevates (UAC), downloads the latest version of this repo, extracts it to a working directory, and launches the PowerShell orchestrator. This is the only file meant to persist on a client machine; everything else is removed at the end of a run.
2. **`MaintenanceOrchestrator.ps1`** — runs five stages:
   - **Stage 1 — Audit (Type1 modules):** scans the system (bloatware, essential apps, security posture, telemetry, system optimization settings, Windows Updates, app versions, general inventory) and writes the results to `temp_files/`.
   - **Stage 2 — Diff:** compares each Type1 result against its baseline config in `config/lists/` and produces a diff list per module.
   - **Stage 3 — Act (Type2 modules):** for every module whose diff list is non-empty, applies the corresponding fix (remove bloatware, install missing apps, harden security settings, disable telemetry, optimize system settings, install updates, upgrade apps). A module with an empty diff list is skipped and logged as such.
   - **Stage 4 — Report:** generates a single self-contained HTML report summarizing every module's results.
   - **Stage 5 — Cleanup/Reboot:** copies the report out of the working directory, optionally reboots (only if a module flagged `RebootRequired`, or per config), then removes the project folder.

See [`docs/Comprehensive-Project-Analysis-2026-07-15.md`](docs/Comprehensive-Project-Analysis-2026-07-15.md) for a full, current technical audit of this codebase — known bugs, dead code, and design risks.

## Running it

```
script.bat                    REM interactive, with prompts/countdowns
script.bat -NonInteractive    REM fully unattended, e.g. for Task Scheduler
```

Requires PowerShell 7+ (`pwsh.exe`) to run the orchestrator; `script.bat` will attempt to detect/install it if missing. Must run elevated (admin) — `script.bat` handles the UAC prompt itself.

## Configuration

- `config/settings/main-config.json` — top-level toggles (which modules run, cleanup/reboot behavior, restore points).
- `config/lists/*/` — baseline data per module (bloatware list, essential apps, security baseline, telemetry targets, system-optimization preferences, Windows Update categories, app-upgrade exclusions). Editing these changes what Stage 1 audits against and what Stage 3 will do.

**Safety-relevant defaults worth knowing before your first run:**
- `cleanupOnTimeout` in `main-config.json` defaults to removing the project folder — this is intentional (see architecture above), but means running the orchestrator directly from a working copy during development will delete that copy too. Prefer running against a disposable copy while developing.
- Reboot only happens in Stage 5, and only when a module actually flags it as required (or per your `main-config.json` reboot policy) — you'll get an on-screen countdown you can abort in interactive mode.

## Project layout

```
script.bat                     Self-contained launcher (persists on client machines)
MaintenanceOrchestrator.ps1    Stage-based orchestrator
modules/core/                  Shared helpers, HTML report generator
modules/type1/                 Audit modules (read-only system scans)
modules/type2/                 Action modules (apply fixes, paired 1:1 with type1)
config/lists/                  Per-module baseline data
config/settings/               Global settings
docs/                          Analysis and design notes (not shipped to client machines)
archive/                       Retired/superseded code, kept locally for reference (not shipped)
```

## Known issues

This project has an actively-maintained, honest audit trail of bugs and design risks in [`docs/Comprehensive-Project-Analysis-2026-07-15.md`](docs/Comprehensive-Project-Analysis-2026-07-15.md). Notably, at time of writing: `winget`/`choco` invocations can deadlock under certain output conditions, and several native-command calls (`net accounts`, `auditpol`, `powercfg`) don't check exit codes before reporting success. Read that doc before relying on this tool unattended on production machines.
