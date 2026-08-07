# Sysinternals Suite — Reference and Integration Guide for `script_mentenanta`

**Researched:** 7 August 2026, against the official Microsoft Learn Sysinternals documentation.
**Scope:** what the Sysinternals Suite is, which of its ~75 tools can do real work for *this*
project, exactly how to invoke them unattended, and — just as importantly — which ones look
useful and are not.

This is a companion to [CLAUDE.md](CLAUDE.md). Everything here is written against **the operating
contract** in that file: the run must complete start-to-finish, unattended, as `NT AUTHORITY\SYSTEM`,
on a machine nobody is watching, leaving only `script.bat` and the HTML report behind. A tool that
cannot satisfy that contract is not a candidate, however good it is.

The project already ships one Sysinternals tool — **Sysmon** — installed by
[SystemConfiguration.psm1](modules/type2/SystemConfiguration.psm1) (`Install-SysmonWithConfig`,
around [line 124](modules/type2/SystemConfiguration.psm1#L124)). The scar tissue from that
integration is the best guide to the rest of the suite, and Section 3 generalises it.

---

## Table of contents

1. [What Sysinternals actually is](#1-what-sysinternals-actually-is)
2. [How to get the binaries onto the machine](#2-how-to-get-the-binaries-onto-the-machine)
3. [The unattended-execution rules](#3-the-unattended-execution-rules-read-before-adding-any-tool)
4. [Full tool inventory, rated for this project](#4-full-tool-inventory-rated-for-this-project)
5. [Tier 1 — tools that solve a problem this project has](#5-tier-1--tools-that-solve-a-problem-this-project-actually-has)
6. [Tier 2 — useful but optional](#6-tier-2--useful-but-optional)
7. [Tier 3 — do not add these](#7-tier-3--do-not-add-these)
8. [Sysmon: what we already run, and the traps around it](#8-sysmon-what-we-already-run-and-the-traps-around-it)
9. [Recommended integration plan, in priority order](#9-recommended-integration-plan-in-priority-order)
10. [Sources](#10-sources)

---

## 1. What Sysinternals actually is

Sysinternals is a set of standalone Windows troubleshooting utilities written by Mark Russinovich,
now owned by Microsoft and documented on Microsoft Learn. Relevant properties for us:

- **No installer, no dependencies.** Each tool is a single self-contained `.exe`. You copy it
  somewhere and run it. There is no MSI, no service to register (except Sysmon, which is a service
  by design), and no runtime to install. This is the single reason the suite is a good fit for a
  project whose working tree is deleted every month.
- **Most are console programs with parseable output.** The ones that matter to us
  (`autorunsc`, `sigcheck`, `handle`, `du`, `pendmoves`, `accesschk`, `streams`, `listdlls`)
  emit CSV or tab-delimited text on stdout.
- **Signed by Microsoft.** Every binary carries a valid Microsoft Authenticode signature, which
  means we can verify a runtime-downloaded tool with `Get-AuthenticodeSignature` before executing
  it (see §2.4).
- **They are "as-is" and unsupported.** The licence says so explicitly. Do not build a hard
  dependency: every Sysinternals call must degrade to `Warning`, never fail the run.

### 1.1 Licensing — the part that affects us

The [Sysinternals Software License Terms](https://learn.microsoft.com/en-us/sysinternals/license-terms)
grant: *"You may install and use any number of copies of the software on your devices."*

Running them on machines you administer is unambiguously fine. Two clauses matter for how we
distribute them:

> You may not … **publish the software for others to copy**; rent, lease or lend the software;
> **transfer the software or this agreement to any third party**; or use the software for
> commercial software hosting services.

**Practical consequence: do not commit the Sysinternals `.exe` files into this public GitHub
repository.** The repo's whole delivery mechanism is "anyone downloads `master.zip`", which is
exactly "publish the software for others to copy". Download the tools at runtime from
`download.sysinternals.com` instead (§2.2) — every machine then acquires its own copy directly
from Microsoft under its own acceptance of the terms. This costs nothing: the tools we want total
well under 10 MB.

The licence also warns that saved output *"may include personally identifiable or other sensitive
information (such as usernames, passwords, paths to files accessed, and paths to registry
accessed)"*. Since Stage 4 embeds data into an HTML report that gets copied to
`$env:ORIGINAL_SCRIPT_DIR` and survives the run, be deliberate about what tool output lands in the
report. `autorunsc` output contains full paths and per-user autostart entries; that is fine for a
personal machine, less fine if the report is ever shared.

---

## 2. How to get the binaries onto the machine

This is the first design decision and the easiest one to get wrong. There are four distribution
channels and **only one of them is appropriate for this project.**

### 2.1 ❌ winget / the Microsoft Store — the trap

`winget install Microsoft.Sysinternals.Suite` resolves to the **Microsoft Store MSIX bundle**.
Per the [Microsoft Store page](https://learn.microsoft.com/en-us/sysinternals/downloads/microsoft-store):

> Like most other MSIX packages, Sysinternals Suite is installed **per user** … All executables
> are available from the path via Windows **app execution aliases** … They are stored in a
> directory in the user profile: `%LOCALAPPDATA%\Microsoft\WindowsApps`

Three independent failures for us, all of them fatal:

1. **Per-user MSIX registration.** `winget` is officially unsupported under `NT AUTHORITY\SYSTEM`
   (already documented in CLAUDE.md for the bloatware path) precisely because MSIX registers
   per-user and SYSTEM has no such registration. The monthly scheduled task runs as SYSTEM.
2. **App execution aliases are reparse points, not executables.** They live in the *user's*
   `%LOCALAPPDATA%`, so a SYSTEM process cannot see them at all.
3. **Aliases crash under redirected stdio.** This project has already been burned by exactly this:
   the winget `Links\sysmon.exe` shim fail-fast crashes with `0xC0000409` (`-1073740791`) when
   launched with redirected standard IO — which is what `Invoke-ExternalPackageCommand` always
   does. `Install-SysmonWithConfig` contains a dedicated workaround
   ([SystemConfiguration.psm1:151-180](modules/type2/SystemConfiguration.psm1#L151)) that resolves
   the *real* `Sysmon64.exe` out of `%windir%` or the winget `Packages` folder specifically to
   avoid the shim.

Individual winget packages do exist (`Microsoft.Sysinternals.Autoruns`, `.Handle`, `.Sigcheck`,
`.ProcessMonitor`, `.SDelete`, `.PendMoves`, `.MoveFile`, `.RAMMap`, `.Strings`, `.PsTools`,
`.Sysmon`, and others), but they carry the same alias/per-user problems. **Sysmon is the exception
that proves the rule**: it works via winget only because installing it produces a *service* whose
binary is copied into `%windir%`, at a fixed path SYSTEM can find — and even then the module has to
go hunting for that path.

> **Do not extend the winget-for-Sysinternals pattern beyond Sysmon.** It works for Sysmon by
> accident of Sysmon being a service.

### 2.2 ✅ Direct zip download — recommended

Every tool has a stable, permanent download URL:

```
https://download.sysinternals.com/files/<Name>.zip
```

| Tool | URL | Size |
|---|---|---|
| Handle | `.../files/Handle.zip` | 729 KB |
| Sigcheck | `.../files/Sigcheck.zip` | 645 KB |
| PendMoves + MoveFile | `.../files/pendmoves.zip` | 988 KB |
| Autoruns + Autorunsc | `.../files/Autoruns.zip` | 3 MB |
| Disk Usage (du) | `.../files/DU.zip` | 1.62 MB |
| AccessChk | `.../files/AccessChk.zip` | 1 MB |
| Streams | `.../files/Streams.zip` | 499 KB |
| ListDLLs | `.../files/ListDlls.zip` | 307 KB |
| SDelete | `.../files/SDelete.zip` | 328 KB |
| Contig | `.../files/Contig.zip` | 366 KB |
| PsTools (all Ps\* tools) | `.../files/PSTools.zip` | 5 MB |
| **Full Suite** | `.../files/SysinternalsSuite.zip` | **184.6 MB** |
| Suite (ARM64) | `.../files/SysinternalsSuite-ARM64.zip` | 21.1 MB |
| Suite (Nano Server) | `.../files/SysinternalsSuite-Nano.zip` | 9.9 MB |

**Download only the individual tools you use, never the 184 MB Suite.** The five Tier-1 tools
(§5) total about 6.5 MB — comparable to the repo zip the launcher already pulls from GitHub, and
downloaded through the same mechanism. This also fits the contract cleanly: unpack into
`temp_files/tools/`, which lives under `$env:MAINT_ROOT` and is therefore already inside the
Defender exclusion Stage 5 manages, and gets deleted with the rest of the tree.

Note the x64 naming convention on the unpackaged downloads: `handle64.exe`, `sigcheck64.exe`,
`accesschk64.exe`, `Autoruns64.exe`, `procdump64.exe`, `Sysmon64.exe`. Some tools ship only one
architecture-neutral binary (`autorunsc.exe` ships as both `autorunsc.exe` and `autorunsc64.exe`;
`du.exe`/`du64.exe`; `pendmoves.exe`/`pendmoves64.exe`; `streams.exe`/`streams64.exe`). Resolve
with a `64`-first fallback, the same shape as the existing Sysmon resolution:

```powershell
function Resolve-SysinternalsTool {
    param([Parameter(Mandatory)][string]$BaseName, [Parameter(Mandatory)][string]$ToolDir)
    foreach ($n in "$BaseName`64.exe", "$BaseName.exe") {
        $p = Join-Path $ToolDir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}
```

### 2.3 ❌ Sysinternals Live

`\\live.sysinternals.com\tools\<tool>.exe` (or `https://live.sysinternals.com/<tool>.exe`) runs a
tool straight off Microsoft's share. Tempting — zero local footprint. Rejected because it needs
the **WebClient (WebDAV) service** running, is blocked on most managed networks, adds a
per-invocation network round trip inside an already network-dependent run, and executing a binary
directly from a remote UNC path as SYSTEM is fragile and looks exactly like an attack technique to
any EDR on the box. Use it for interactive debugging on your own machine, never in the pipeline.

### 2.4 Verify before executing

Since the binary arrives over the network at runtime, verify it before running it. This is
PowerShell-native, so there is no bootstrapping problem:

```powershell
function Test-SysinternalsBinary {
    param([Parameter(Mandatory)][string]$Path)
    $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($sig.Status -ne 'Valid') {
        Write-Log -Level WARN -Component TOOLS -Message "Unsigned/invalid: $Path ($($sig.Status))"
        return $false
    }
    if ($sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        Write-Log -Level WARN -Component TOOLS -Message "Not Microsoft-signed: $Path"
        return $false
    }
    return $true
}
```

If verification fails, log a `WARN` and skip the feature. Never fail the run over a tool download.

---

## 3. The unattended-execution rules (read before adding *any* tool)

### 3.1 The EULA will block you if you let it

On first run, a Sysinternals tool pops a **modal GUI licence dialog**. Under the SYSTEM scheduled
task there is no desktop to show it on — the process just sits there until
`Invoke-ExternalPackageCommand`'s timeout kills it. This is precisely the class of failure the
operating contract calls a bug, not a UX choice.

Two mitigations, and you want **both**:

**(a) Pass the switch on every invocation.** Most tools accept `-accepteula`; Procmon uses
`/AcceptEula`. Note that the Learn parameter tables are inconsistent about listing it —
`sigcheck`, `psexec`, `procdump` and `sysmon` document it explicitly; `autorunsc`, `handle`,
`du` and `streams` accept it but do not list it in their tables. Pass it regardless; unknown
switches on these tools are ignored rather than fatal.

**(b) Pre-seed the registry, for the tools that ignore the switch.** Acceptance is recorded at:

```
HKCU\Software\Sysinternals\<ToolName>\EulaAccepted = 1   (REG_DWORD)
HKCU\Software\Sysinternals\EulaAccepted            = 1   (REG_DWORD)  # reported blanket accept
```

**The SYSTEM subtlety:** when a process runs as `NT AUTHORITY\SYSTEM`, its `HKCU` is
`HKEY_USERS\S-1-5-18` — and `HKEY_USERS\.DEFAULT` is an alias for that same hive. So the
orchestrator, which runs as SYSTEM under the monthly task, writing plain `HKCU:` already lands in
the right place. But during an **interactive** admin run, `HKCU:` is the logged-on user's hive and
the SYSTEM hive stays unseeded. Write both explicitly so behaviour is identical in both modes:

```powershell
foreach ($root in 'HKCU:\Software\Sysinternals',
                  'Registry::HKEY_USERS\S-1-5-18\Software\Sysinternals') {
    if (-not (Test-Path $root)) { New-Item -Path $root -Force | Out-Null }
    Set-ItemProperty -Path $root -Name 'EulaAccepted' -Value 1 -Type DWord -Force
}
```

> **Heads-up:** writing `…\Sysinternals\*\EulaAccepted` is a *monitored* behaviour — there are
> published Sigma detection rules for it (they target renamed Sysinternals binaries used by
> attackers). Ours is benign and under our own filename, but expect it to be visible in EDR
> telemetry, and note that our own Sysmon config logs registry value sets. Not a reason to avoid
> it; a reason not to be surprised by it.

### 3.2 Route everything through `Invoke-ExternalPackageCommand`

Non-negotiable, per the conventions in CLAUDE.md. It is the only call path that drains both stdio
pipes before waiting (deadlock-safe), enforces a timeout, kills the process *tree* on expiry, and
logs the child's stderr on non-zero exit — which is the only place a failure reason is ever
captured. See [Maintenance.psm1:1755](modules/core/Maintenance.psm1#L1755).

Its signature is `-FilePath`, `-ArgumentList` (`string[]`), `-TimeoutSeconds` (default 600), and
it **returns an `int` exit code, not output**. Sysinternals tools are read-output tools, so for
these you need a sibling helper that captures stdout. Add one rather than sprinkling
`Start-Process`/`&` calls around:

```powershell
function Invoke-SysinternalsCommand {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [int]$TimeoutSeconds = 180
    )
    # Same stdio-drain-then-wait shape as Invoke-ExternalPackageCommand, but returns
    # @{ ExitCode = <int>; StdOut = <string>; StdErr = <string> }.
    # Always prepend -accepteula and -nobanner where the tool supports them.
}
```

Keep the timeouts short. These are audit tools, not installers: 60–180 s is generous for everything
except a full-volume `du` or a recursive `sigcheck`, which should be scoped so they never need
more. Note that `Invoke-ExternalPackageCommand` joins `-ArgumentList` with a plain space, so any
path containing spaces must already be quoted by the caller (as `Install-SysmonWithConfig` does
with `$quotedConfig`).

### 3.3 Suppress banners, and parse defensively

Most tools print a multi-line copyright banner to stdout before the data. Pass `-nobanner`
(documented for `sigcheck`, `accesschk`, `du`, `psexec`; accepted but undocumented on several
others). Even with it, **never assume the first line is the CSV header** — find the header row and
validate column counts against it, exactly the way `ConvertFrom-WingetListTable` already does for
`winget list`. Sysinternals CSV is genuine RFC-ish CSV with quoting, so `ConvertFrom-Csv` handles
it once you have trimmed any banner.

### 3.4 Some of these tools are AV-flagged, on purpose

The PsExec documentation says it outright:

> some anti-virus scanners report that one or more of the tools are infected with a "remote admin"
> virus. None of the PsTools contain viruses, but they have been used by viruses, which is why they
> trigger virus notifications.

The project already adds Defender exclusions for `$ProjectRoot` and `$env:ORIGINAL_SCRIPT_DIR`, so
tools unpacked into `temp_files/tools/` are covered — but third-party AV is not, and a maintenance
script that downloads `PsExec.exe` as SYSTEM is a textbook detection signature. This is a strong
argument for the Tier-1 shortlist: `handle`, `sigcheck`, `autorunsc`, `du`, `pendmoves` are
audit-shaped tools that attract far less attention than the PsTools remote-execution family.

### 3.5 No GUI tools, ever

Process Explorer, the Autoruns GUI, TCPView, VMMap, RAMMap, DiskView, WinObj, AdExplorer, BgInfo,
ZoomIt, Desktops, Disk2vhd are Win32 GUI applications. Under the SYSTEM task they run in **session 0**,
which has no interactive desktop. They will either fail to start or start invisibly and hang until
timeout. Every one of them either has a console sibling (`Autoruns`→`autorunsc`,
`TCPView`→`tcpvcon`, `Process Explorer`→`handle`/`listdlls`) or has no place in the pipeline.

### 3.6 Nothing survives to next month

`script.bat`'s self-update `RMDIR /S /Q`s the extracted tree before every run, so
`temp_files/tools/` is re-downloaded each month. That is ~6.5 MB on top of the repo zip — acceptable,
and it means you always run the current tool version. Do **not** try to cache tools in
`$env:ORIGINAL_SCRIPT_DIR` to save the download: that folder is the "only `script.bat` and the
report" surface, and polluting it breaks the contract.

---

## 4. Full tool inventory, rated for this project

Versions as published on Microsoft Learn at the time of writing. Ratings are *for this project's
unattended monthly maintenance run*, not general merit.

| Tool | Ver. | Console? | What it does | Rating for us |
|---|---|:--:|---|---|
| **Autoruns / autorunsc** | 14.3 | ✅ `autorunsc` | Every autostart location on Windows | ⭐⭐⭐ **Tier 1** |
| **Handle** | 5.0 | ✅ | Which process holds a file/dir open | ⭐⭐⭐ **Tier 1** |
| **PendMoves / MoveFile** | 1.3 / 1.02 | ✅ | Read/schedule boot-time renames & deletes | ⭐⭐⭐ **Tier 1** |
| **Sigcheck** | 2.91 | ✅ | Signature/version check + VirusTotal hash lookup | ⭐⭐⭐ **Tier 1** |
| **Disk Usage (du)** | 1.62 | ✅ | Directory-tree size, CSV | ⭐⭐ **Tier 1** |
| **AccessChk** | 6.15 | ✅ | Effective permissions on files/keys/services | ⭐⭐ Tier 2 |
| **Streams** | 1.6 | ✅ | List/delete NTFS alternate data streams | ⭐⭐ Tier 2 |
| **ListDLLs** | 3.2 | ✅ | Loaded DLLs; `-u` finds unsigned ones | ⭐⭐ Tier 2 |
| **Sysmon** | 15.21 | ✅ | Kernel-level activity logging service | ✅ **Already integrated** |
| **ProcDump** | 12.01 | ✅ | Capture process dumps on hang/CPU/exception | ⭐ Tier 2 (debug only) |
| **Coreinfo** | 4.01 | ✅ | CPU topology, cache, virtualization features | ⭐ Tier 2 (inventory) |
| **NTFSInfo** | 1.2 | ✅ | MFT size/zone, NTFS metadata sizes | ⭐ Tier 2 (report) |
| **Registry Usage (ru)** | 1.2 | ✅ | Registry key space usage | ⭐ Tier 2 (report) |
| **LogonSessions** | 1.41 | ✅ | Active logon sessions, `-p` for processes | ⭐ Tier 2 |
| **SDelete** | 2.06 | ✅ | Secure delete / free-space wipe | ⚠️ Opt-in only |
| **Contig** | 1.83 | ✅ | Single-file / metadata defrag | ⚠️ Opt-in only |
| **RAMMap** | 1.63 | GUI (+undoc. CLI) | Physical memory analysis; `-Et` empties standby | ❌ **Tier 3** |
| **PsExec** | 2.43 | ✅ | Run processes remotely / as SYSTEM | ❌ Tier 3 |
| **Process Monitor** | 4.04 | GUI + CLI | Real-time FS/registry/process tracing | ❌ Tier 3 (dev only) |
| **Process Explorer** | 17.12 | GUI | Interactive process browser | ❌ GUI |
| **PsService** | 2.26 | ✅ | View/control services | ❌ `Set-Service`/`sc.exe` cover it |
| **PsInfo** | 1.79 | ✅ | System summary via Remote Registry API | ❌ CIM covers it |
| **PsLogList** | 2.82 | ✅ | Dump event log records | ❌ `Get-WinEvent` is better |
| **PsList / PsKill / PsSuspend** | — | ✅ | Process list/kill/suspend | ❌ PS cmdlets cover it |
| **PsShutdown** | 2.6 | ✅ | Shutdown/reboot/hibernate/lock | ❌ `shutdown.exe` covers it |
| **PsPing** | 2.12 | ✅ | ICMP/TCP ping, latency, bandwidth | ❌ `Test-NetConnection` covers it |
| **PsGetSid / PsFile / PsPasswd / PsLoggedOn** | — | ✅ | SIDs / remote opens / passwords / users | ❌ Not needed |
| **TCPView / tcpvcon** | 4.19 | GUI + `tcpvcon` | Active sockets | ❌ `Get-NetTCPConnection` covers it |
| **VMMap** | 3.4 | GUI | Process virtual memory analysis | ❌ GUI, dev tool |
| **Strings** | 2.54 | ✅ | Extract ANSI/Unicode strings from binaries | ❌ Malware-analysis tool |
| **AccessEnum** | 1.35 | GUI | Permission holes across a tree | ❌ GUI (use AccessChk) |
| **Junction / FindLinks** | — | ✅ | NTFS junctions / hard links | ❌ `New-Item -ItemType` covers it |
| **DiskExt / DiskView / DiskMon / LDMDump** | — | mixed | Volume mapping / sector view / disk I/O | ❌ Not needed |
| **RegDelNull / RegJump / RegHide** | — | mixed | Null-char keys / regedit navigation | ❌ Niche |
| **Sync** | 2.2 | ✅ | Flush cached data to disk | ❌ Shutdown already flushes |
| **EFSDump / Disk2vhd / Autologon / ShareEnum / ShellRunas** | — | mixed | EFS info / P2V / autologon / shares / runas | ❌ Out of scope |
| **AdExplorer / AdInsight / AdRestore / RDCMan** | — | GUI | Active Directory / RDP management | ❌ Domain tools; this targets standalone PCs |
| **DebugView / LiveKd / PortMon / PipeList / LoadOrder / WinObj / ClockRes / Hex2dec / VolumeId / Whois / CacheSet / Desktops / BgInfo / ZoomIt / Ctrl2Cap / jcd / listent** | — | mixed | Assorted diagnostics & utilities | ❌ No role here |
| **NotMyFault / BlueScreen / CPUSTRES / Testlimit** | — | — | Deliberately crash/hang/stress the system | 🚫 **Never** |

---

## 5. Tier 1 — tools that solve a problem this project *actually has*

Each entry below states the problem in the current codebase, the tool's exact invocation, and where
it belongs in the Type1/Type2 model.

---

### 5.1 PendMoves + MoveFile — the best fit in the entire suite

**Download:** `https://download.sysinternals.com/files/pendmoves.zip` (988 KB, contains both)

#### What they do

Windows exposes `MoveFileEx(…, MOVEFILE_DELAY_UNTIL_REBOOT)` so that installers can replace or
delete files that are currently in use. Session Manager executes the queued operations at next boot,
before anything references the files. The queue lives in:

```
HKLM\System\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations
```

- **`pendmoves`** dumps that queue in readable `Source:` / `Target:` pairs, *and reports an error
  when the source file is not accessible*.
- **`movefile <source> <dest>`** adds an entry. **An empty destination deletes the source at boot:**
  ```cmd
  movefile "C:\stuck\file.tmp" ""
  ```

Usage is that simple — `pendmoves` takes no arguments; `movefile` takes exactly two.

#### Why this project needs it — two separate wins

**(a) DiskCleanup can finally finish the job it starts.**
[DiskCleanup.psm1](modules/type2/DiskCleanup.psm1) deletes temp files, browser caches and cookies.
A predictable fraction of those are locked by a running process and simply cannot be deleted — the
module logs a failure and moves on, and the same files fail again next month, forever. `movefile`
converts every one of those into a delete that *will* happen. And the timing is perfect: **Stage 5
reboots the machine anyway.** A file queued in Stage 3 is gone within minutes, in the very same run.

```powershell
# In DiskCleanup, where a delete currently fails:
try {
    Remove-Item -LiteralPath $file -Force -ErrorAction Stop
    $deleted++
}
catch {
    if ($moveFileExe) {
        $r = Invoke-ExternalPackageCommand -FilePath $moveFileExe `
                 -ArgumentList @('-accepteula', "`"$file`"", '""') -TimeoutSeconds 30
        if ($r -eq 0) {
            Write-Log -Level INFO -Component CLEANUP -Message "Queued for boot-time delete: $file"
            $result.RebootRequired = $true   # the queued delete only happens on reboot
            $queuedForBoot++
        }
    }
}
```

Two things to get right, both flowing from the operating contract:

- **Set `RebootRequired = $true` on the module result** whenever you queue something. Otherwise
  `rebootOnlyWhenRequired` may skip the reboot and the queued deletes sit there for a month.
  This is the same class of bug as the `3010` exit-code fix already documented for
  `SoftwareManagement`.
- **Never queue anything outside a temp/cache path.** `PendingFileRenameOperations` executes as
  Session Manager with nothing watching and no undo. Restrict it to the exact path list DiskCleanup
  already validated, and never to a path that resolves inside `%windir%\System32` or a program
  directory.

**(b) A far better reboot-pending signal than the one we have.**
[`Test-CbsRebootPending`](modules/core/Maintenance.psm1#L1449) checks five indicators, one of which
is *"does `PendingFileRenameOperations` exist"* — a bare boolean. `pendmoves` tells you **what** is
queued and whether the sources are still valid. For the Stage 4 report and the Stage 5 reboot
decision that is the difference between "a reboot is pending" and "a reboot is pending because
these 7 files are waiting to be replaced." Cheap to add, purely read-only, and it makes the report
genuinely more useful.

---

### 5.2 Handle — diagnose the failure that silently kills the monthly task

**Download:** `https://download.sysinternals.com/files/Handle.zip` (729 KB) → `handle64.exe`

```
handle [[-a [-l]] [-v|-vt] [-u] | [-c <handle> [-y]] | [-s]] [-p <process>|<pid>] [name]
```

| Switch | Meaning |
|---|---|
| `-a` | All handle types, not just files |
| `-u` | Show the owning **user** name |
| `-v` | CSV output (comma) — `-vt` for tab |
| `-p` | Restrict to processes whose name starts with the given string |
| `-s` | Print a count of each handle type |
| `-c <handle> [-y]` | **Close a handle.** Docs: *"WARNING: Closing handles can cause application or system instability."* |
| `name` | Search mode: report every process holding an object whose path contains this fragment |

Requires administrator privilege — we always have it.

#### The problem it solves

Straight from the operating contract in CLAUDE.md, describing what one stray `-NoExit` does:

> …because that host's CWD is the extracted folder, the *next* run's `RMDIR /S /Q` of that folder
> fails and the launcher aborts with `EXIT /B 3`. One stray `-NoExit` therefore degrades into
> **"the monthly task silently stops working forever"**.

Today when that happens you get an exit code and nothing else. The machine stops maintaining itself
and nobody finds out for months. With `handle` in search mode you get the culprit by name:

```powershell
$h = Invoke-SysinternalsCommand -FilePath $handleExe `
        -ArgumentList @('-accepteula', '-nobanner', '-a', '-u', $ProjectRoot) -TimeoutSeconds 60
# Search-mode output: "<process>  pid: <pid>  <user>  <handle>: File  (…)  <path>"
```

Two placements, both worth doing:

1. **Early in the orchestrator**, log every process holding a handle under `$env:MAINT_ROOT` or
   `$env:ORIGINAL_SCRIPT_DIR`. One `WARN` line naming an orphaned `pwsh` in session 0 turns a
   permanently dead scheduled task into a five-second diagnosis.
2. **In DiskCleanup**, when a delete fails with a sharing violation, log which process holds the
   file before falling back to `movefile` (§5.1). The report then explains *why* files were
   deferred instead of just listing them.

> 🚫 **Never use `-c` to force-close handles.** The docs warn it causes instability, and the owning
> process is not told its handle vanished. On an unattended run with nobody watching, corrupting a
> live application's state to reclaim a few MB of temp files is an unambiguously bad trade. Report
> the holder; queue the file with `movefile`; reboot. That path is safe and already in the design.

---

### 5.3 Autorunsc — the single biggest capability gap this project has

**Download:** `https://download.sysinternals.com/files/Autoruns.zip` (3 MB) → `autorunsc.exe` / `autorunsc64.exe`

```
autorunsc [-a <*|bdeghiklmoprstw>] [-c|-ct|-x] [-h] [-m] [-s] [-t] [-u] [-v[rs]] [-vt] [[-z <systemroot>] | [user]]
```

| Switch | Meaning |
|---|---|
| `-a <cats>` | Categories (see below); `*` = all. Default is `l` (logon) only |
| `-c` / `-ct` / `-x` | CSV / tab-delimited / XML output |
| `-h` | Show file hashes |
| `-s` | **Verify digital signatures** |
| `-m` | Hide Microsoft entries (signed entries when combined with `-s`) |
| `-t` | Timestamps as normalized UTC (`YYYYMMDD-hhmmss`) |
| `-u` | Show only unsigned files (or, with VT enabled, unknown/non-zero-detection files) |
| `-v[rs]` | VirusTotal lookup by hash; `r` opens reports; `s` **uploads unknown files** |
| `-vt` | Accept the VirusTotal terms of service non-interactively |
| `-z <dir>` | Scan an **offline** Windows installation |
| `user` | Scan a specific user's autostarts; `*` for all profiles |

**Category letters for `-a`:** `b` boot execute · `d` AppInit DLLs · `e` Explorer add-ons ·
`g` sidebar gadgets · `h` image hijacks · `i` Internet Explorer add-ons · `k` known DLLs ·
`l` logon startups *(default)* · `m` WMI entries · `n` Winsock protocol & network providers ·
`o` codecs · `p` printer monitor DLLs · `r` LSA security providers · `s` autostart services and
non-disabled drivers · `t` scheduled tasks · `w` Winlogon entries.

#### The gap

`SystemConfigurationAudit`'s startup check reads **exactly two registry keys**
([SystemConfigurationAudit.psm1:813-816](modules/type1/SystemConfigurationAudit.psm1#L813)):

```powershell
$runPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
)
```

That is two of roughly two hundred autostart locations Windows supports, and it is the shallowest
two. Not covered today: `RunOnce`, both Startup folders, **scheduled tasks**, services and drivers,
Winlogon `Shell`/`Userinit` hijacks, AppInit_DLLs, **image file execution options (debugger)
hijacks**, WMI event-consumer persistence, LSA security packages, Winsock LSPs, Explorer shell
extensions, codecs, print monitors, and every other per-user profile on the machine. Several of
those are *the* classic malware persistence mechanisms — the reason `Autoruns` is the centrepiece
of Russinovich's "Malware Hunting with the Sysinternals Tools" talk.

Since the project already installs Sysmon and enforces a CIS security baseline, the security
posture ambition is clearly there. This is the cheapest large step forward available.

#### Recommended integration

**Type1 (`SystemConfigurationAudit`, Phase B — report-only):**

```powershell
$args = @('-accepteula', '-nobanner', '-a', '*', '-c', '-h', '-s', '-t', '*')
# -a *  every category      -c  CSV
# -h    file hashes         -s  verify signatures
# -t    UTC timestamps      *   all user profiles
```

This is the slow part of the suite — allow 60–180 s and run it in Phase B, **after**
`Save-DiffList`, so a slow or failed scan can never cost the run the Phase A diff. That is exactly
the reason Phase B exists; the existing 30-day `Get-WinEvent` health sweep lives there for the same
reason. Persist to `temp_files/data/autoruns-audit.json` and render a report section keyed on that
file's presence, matching how `system-inventory.json` / `system-health-report.json` are already
gated in [ReportGenerator.psm1](modules/core/ReportGenerator.psm1).

Add `-m` if you want only third-party entries (much shorter list, far more signal). Keep the
unfiltered scan for the report and derive the `-m`-equivalent view by filtering the CSV in
PowerShell — one process invocation, two views.

**Type2 (`SystemConfiguration`, `ConfigType = 'optimization'`) — be conservative.** `autorunsc`
itself is read-only; it has no disable switch (only the GUI can uncheck entries). Disabling means
writing `StartupApproved` registry values or deleting entries yourself. If you extend the existing
startup-disable logic to autoruns-discovered entries, keep the current safety model:
`safeToDisablePatterns` allowlist + `neverDisable` blocklist, both already in the optimization
baseline. **Never disable an entry merely because it is unsigned or non-Microsoft** — on a real
machine that is a description of most of the software the user chose to install.

#### On the VirusTotal switches

`-v -vt` submits **file hashes only** and returns detection counts; `-vs` additionally **uploads
the file itself**. Considerations before enabling either:

- **Never use `-vs` here.** Uploading files off a user's machine unattended, with no consent
  prompt, is not a decision a maintenance script gets to make on its own.
- Even hash-only lookups tell VirusTotal what is installed on the machine, and results are visible
  to VT's customer base. Make it opt-in via `main-config.json`, default off.
- The public VirusTotal API is rate-limited (a few requests per minute). A full `-a *` scan
  produces hundreds of hashes. Expect long runs or throttling; scope it to `-m -u` (non-Microsoft,
  unsigned) if you enable it at all.
- It needs internet at a moment when the run may already be doing Windows Update work.

**Recommendation: ship `-a * -c -h -s -t` without VirusTotal.** Signature verification alone
answers "is anything unsigned persisting on this box", which is the high-value question, with no
network dependency and no data leaving the machine.

---

### 5.4 Sigcheck — signature and reputation verification

**Download:** `https://download.sysinternals.com/files/Sigcheck.zip` (645 KB) → `sigcheck64.exe`

```
sigcheck [-a][-h][-i][-e][-l][-n][[-s]|[-c|-ct]|[-m]][-q][-r][-u][-vt][-v[r][s]][-f catalog] <file or directory>
sigcheck -d [-c|-ct] <catalog file>
sigcheck -t[u][v] [-i] [-c|-ct] <certificate store name|*>
```

| Switch | Meaning |
|---|---|
| `-e` | Scan **executable images only, regardless of extension** |
| `-s` | Recurse subdirectories |
| `-u` | Show only unsigned files (or, with VT on, unknown / non-zero detections) |
| `-h` | File hashes |
| `-i` | Catalog name and signing chain |
| `-a` | Extended version info, including **entropy** (bits/byte) |
| `-c` / `-ct` | CSV / tab-delimited output |
| `-r` | Disable certificate revocation checking |
| `-f <catalog>` | Look for the signature in a specific catalog file |
| `-t[u][v]` | Dump a certificate store; `-tv` downloads the trusted MS root list and shows only certs **not** rooted to it |
| `-v[rs]` / `-vt` | VirusTotal lookup / accept VT terms (same cautions as §5.3) |
| `-o` | VT lookups from a CSV of hashes captured earlier with `-h` — for offline systems |
| `-nobanner` | Suppress banner |
| `-accepteula` | Accept EULA silently (explicitly documented for this tool) |

The canonical example from the docs is the one worth stealing:

```cmd
sigcheck -u -e c:\windows\system32
```
> *"You should investigate the purpose of any files that are not signed."*

#### Where it earns its place

PowerShell has `Get-AuthenticodeSignature`, so be honest about the delta. Sigcheck adds four things
that cmdlet does not have:

1. **`-e` — content-based executable detection.** Finds PE files regardless of extension. A `.tmp`
   or `.log` in a temp directory that is actually a PE image is a genuine finding;
   `Get-ChildItem -Filter *.exe` never sees it.
2. **`-i` — catalog signing chains.** Most Windows system binaries are *catalog*-signed rather than
   embedded-signed. `Get-AuthenticodeSignature` handles catalogs, but sigcheck reports the catalog
   name and full chain, which is what you need to tell "legitimately catalog-signed" from
   "unsigned" in a report.
3. **One process for a whole tree.** `-s -c -e` walks a directory and emits CSV in a single
   invocation. The equivalent PowerShell loop is one `Get-AuthenticodeSignature` call per file.
4. **`-tv` — root-store hygiene.** Downloads Microsoft's trusted root list and shows certificates
   in the machine store *not* rooted to it. Rogue/injected root CAs are a real compromise indicator
   and nothing else in this project looks for them. Small output, cheap, and a great report section.

#### Suggested usage

Add to `SystemConfigurationAudit` Phase B, scoped tightly so it stays fast:

```powershell
# Unsigned PEs in the high-risk directories only — not the whole disk.
@('C:\Windows\System32', 'C:\Windows\Temp', $env:TEMP, 'C:\ProgramData') | ForEach-Object {
    Invoke-SysinternalsCommand -FilePath $sigcheckExe -ArgumentList @(
        '-accepteula', '-nobanner', '-u', '-e', '-s', '-c', "`"$_`""
    ) -TimeoutSeconds 240
}

# Root certificate store hygiene — cheap and high signal.
Invoke-SysinternalsCommand -FilePath $sigcheckExe `
    -ArgumentList @('-accepteula', '-nobanner', '-tv', '-c') -TimeoutSeconds 120
```

Do **not** point `-s` at `C:\` — a full-disk scan on a spinning disk will blow past any sane
timeout, and the run has other work to do.

---

### 5.5 Disk Usage (du) — measurement for DiskCleanup

**Download:** `https://download.sysinternals.com/files/DU.zip` (1.62 MB) → `du64.exe`

```
du [-c[t]] [-l <levels> | -n | -v] [-u] [-q] [-nobanner] <directory>
```

| Switch | Meaning |
|---|---|
| `-c` / `-ct` | CSV / tab-delimited output |
| `-l <n>` | Report to *n* levels of subdirectory depth (default 0) |
| `-n` | Do not recurse |
| `-v` | Show size (KB) of intermediate directories |
| `-u` | Count each instance of a hard-linked file |
| `-q` | Quiet |

CSV columns are fixed and documented:

```
Path, CurrentFileCount, CurrentFileSize, FileCount, DirectoryCount, DirectorySize, DirectorySizeOnDisk
```

#### Why bother, given `Get-ChildItem`?

Three concrete reasons, none of them dramatic but all real:

- **Speed.** `Get-ChildItem -Recurse | Measure-Object -Sum Length` over `C:\Windows\Temp`,
  `C:\ProgramData`, `WinSxS` or a browser cache constructs a full `FileInfo` object per file in
  PowerShell. `du` walks the tree in native code and emits one CSV row per directory. On the trees
  DiskCleanup cares about this is the difference between seconds and minutes, on every run.
- **`DirectorySizeOnDisk`.** Actual allocated size, accounting for NTFS compression and cluster
  slack. This is what actually gets freed. `Length` is the logical size and overstates the win —
  sometimes by a lot in `WinSxS`, which is heavily hard-linked and compressed.
- **`-u` / hard-link honesty.** `WinSxS` and the component store are hard-link farms. `du` counts
  each link only once by default (correct for "how much space is really used") and `-u` gives the
  naive count. PowerShell gives you the naive count with no way to ask for the other one.

Fits [DiskCleanupAudit.psm1](modules/type1/DiskCleanupAudit.psm1) for the "how much can we reclaim"
estimate, and Stage 4 for a genuine before/after figure in the report. Purely read-only, so the
risk is nil and the fallback is trivial: if the tool is missing, use the existing PowerShell path.

---

## 6. Tier 2 — useful but optional

### 6.1 AccessChk — permission checks the CIS baseline can't reach

```
accesschk [-s][-e][-u][-r][-w][-n][-v][-f <account>,…] [[-a]|[-k]|[-p]|[-h]|[-o]|[-c]|[-d]] [[-l [-i]]|[username]] <target>
```

Key switches: `-c` service · `-k` registry key · `-d` directories/top-level keys only ·
`-p` process · `-h` share · `-a` account right · `-o` object-manager namespace ·
`-s` recurse · `-w` write access only · `-r` read access only · `-n` no access only ·
`-u` suppress errors · `-v` verbose (specific rights + integrity level) · `-l` full security
descriptor (`-i` ignores inherited ACEs) · `-e` explicitly-set integrity levels · `-nobanner`.

The project's `security-baseline.json` covers three mechanisms — registry (300 entries),
`securityPolicy` via `secedit`, `auditPolicy` via `auditpol`. **Object ACLs are a fourth mechanism
it does not cover at all**, and weak ACLs are a classic local-privilege-escalation path that no
registry value describes. The two checks worth adding, both read-only:

```powershell
# Services a non-admin can reconfigure = trivial SYSTEM escalation.
accesschk64 -accepteula -nobanner -uwcqv "Authenticated Users" *
accesschk64 -accepteula -nobanner -uwcqv "Users" *

# World-writable directories that sit on the system PATH = DLL/binary planting.
accesschk64 -accepteula -nobanner -uwdqs "Authenticated Users" "C:\Program Files"
```

**Audit-only. Do not auto-remediate ACLs unattended.** A wrong `icacls` on a service or program
directory can break an application or lock out the user, is not covered by a restore point in any
convenient way, and there is nobody watching. Report the findings; let a human act.

### 6.2 Streams — NTFS alternate data streams

```
streams [-s] [-d] [-nobanner] <file or directory>
```
`-s` recurse · `-d` **delete** the streams found. Accepts wildcards.

The most common ADS is `Zone.Identifier`, the Mark of the Web that Windows attaches to downloaded
files. Two possible uses here, both modest:

- **Diagnostic.** The launcher downloads `master.zip` from GitHub and extracts it. If a future
  change ever switches extraction to the `Shell.Application` COM object (which propagates MOTW to
  extracted files, unlike `Expand-Archive` / .NET `ZipFile`), every extracted `.psm1` inherits MOTW
  and PowerShell may refuse to import them. `streams -s` over the extracted tree makes that failure
  mode visible in one line instead of being a mystifying import error.
- **Report signal.** Non-`Zone.Identifier` streams on executables in temp directories are unusual
  and occasionally interesting.

Note PowerShell already has `Unblock-File` (removes `Zone.Identifier`) and
`Get-Item -Stream *`, so streams' marginal value is recursive discovery and bulk deletion of
*arbitrary* streams. **If you use `-d`, scope it precisely** — it deletes every alternate stream it
finds, and some are load-bearing (e.g. `Wof` compression data, `$DATA` sub-streams used by some
applications).

### 6.3 ListDLLs — unsigned code loaded in live processes

```
listdlls [-r] [-v | -u] [processname|pid]
listdlls [-r] [-v] [-d <dllname>]
```
`-u` only unsigned DLLs · `-v` version info · `-r` flag relocated DLLs · `-d` which processes
loaded a given DLL.

`listdlls64 -accepteula -u` is a one-line, whole-system answer to *"is any unsigned code currently
loaded into any running process?"* — a strong complement to autorunsc (persistence) and sigcheck
(files on disk), covering the third axis: what is running right now. Cheap, read-only, and the
output is short on a clean machine. Good report material.

### 6.4 ProcDump — optional diagnostics for hung external commands

```
procdump [-ma|-mp|-mt|-mm] [-h] [-e [1]] [-c <cpu%>] [-m <MB>] [-n <count>] [-s <secs>]
         [-t] [-w] [-o] [-accepteula] <process name|PID|service> [dumpfile|folder]
```

`Invoke-ExternalPackageCommand` already kills a hung process tree after `-TimeoutSeconds` and logs
the timeout — but the evidence dies with the process. A `debug`-mode option could capture a dump
first:

```powershell
# Before $proc.Kill($true), when a debug flag is set:
procdump64 -accepteula -ma -o $proc.Id "$env:MAINT_TEMP\hang-$($proc.Id).dmp"
```

Worth it only if you are actively chasing a reproducible hang (LibreOffice installs and winget
operations are the historical suspects). Dumps are large and land in the tree that Stage 5 deletes,
so they need to be copied out deliberately. **Off by default.**

### 6.5 Coreinfo / NTFSInfo / Registry Usage — report garnish

- `coreinfo64 -accepteula -nobanner` — CPU topology, cache hierarchy, NUMA, and virtualization
  feature support. Some of this (VBS/HVCI prerequisites) is not conveniently available from CIM.
- `ntfsinfo64 -accepteula C:` — MFT size and MFT-zone, NTFS metadata file sizes. Interesting
  alongside DiskCleanup's numbers.
- `ru -accepteula -c -l 1 HKLM\SOFTWARE` — registry space usage. A bloated registry is a real
  (if minor) performance factor.

All three are single-shot, fast, read-only, and produce a couple of lines each. Add them if you
want a richer inventory section; skip them without regret.

### 6.6 SDelete and Contig — opt-in, and probably "no"

**SDelete** (`sdelete [-p passes] [-r] [-s] [-q] [-f] <files>` / `sdelete [-p passes] [-q] [-z|-c] <drive:>`)
implements DoD 5220.22-M secure deletion. `-c` cleans free space, `-z` **zeroes** free space.

- `-z` is genuinely useful for **virtual machines and thin-provisioned disks** — zeroed free space
  compacts. That is a real win in a VM fleet.
- On **SSDs it is actively harmful**: wear-levelling means an overwrite lands on different physical
  cells, so it does not securely erase anything, while writing the entire free space burns write
  endurance every month. Use TRIM (`Optimize-Volume -ReTrim`) instead.
- It is **slow** — it fills the entire free space of the volume, twice over on NTFS (files, then
  the MFT).
- Note the SDelete↔Sysmon interaction in §8.

**Verdict: gate behind an explicit `main-config.json` flag, default `false`,** and document that
it is for virtual machines. Do not enable it on a general Windows 10/11 endpoint.

**Contig** (`contig [-a] [-s] [-q] [-v] <file>` / `contig [-f] [-q] [-v] <drive:>`) defragments
individual files, and uniquely can defragment NTFS metadata files (`$Mft`, `$LogFile`, `$Bitmap`,
`$Secure`, …). On HDDs, `contig -a $Mft` as an analysis-only report line is mildly interesting.
On SSDs defragmentation is pointless-to-harmful, and Windows' own scheduled Optimize Drives task
already does the right thing per media type. **Analysis (`-a`) only, if at all.**

---

## 7. Tier 3 — do not add these

### 7.1 RAMMap `-Et` — the "free up RAM" antipattern

RAMMap's undocumented CLI switches (`-Et` empty standby list, `-Ew` empty working sets, `-E0`…`-E4`
empty standby by priority) circulate widely as a "speed up Windows" trick. Three reasons this does
not belong here:

1. **They are undocumented.** The Learn page describes only the GUI. Undocumented switches can
   change or vanish between versions — and RAMMap is a GUI application, so under session 0 the
   behaviour is untested at best.
2. **It makes the machine slower.** The standby list *is* the file cache. Emptying it discards
   data Windows deliberately kept, and every subsequent access re-reads from disk. You trade a
   nicer number in Task Manager for measurably worse performance.
3. **Stage 5 reboots the machine.** A reboot clears memory completely and correctly. Anything
   RAMMap could achieve happens minutes later for free.

### 7.2 PsExec

The orchestrator already runs as SYSTEM under the monthly task, so `-s` buys nothing. Meanwhile
PsExec is the single most AV-flagged tool in the suite — Microsoft's own page warns about it — and
a maintenance script that manages Defender exclusions *and* drops `PsExec.exe` as SYSTEM is a
combination that will get flagged and, on some third-party AV, quarantined mid-run.

The one legitimate niche: `psexec -sid cmd` to reach Sysmon's `ArchiveDirectory`, which carries a
System ACL. We do not enable archiving (§8), so the niche does not apply.

### 7.3 Process Monitor

Scriptable in principle (`/Quiet /Minimized /BackingFile <f>.pml /Runtime <n> /Terminate` —
note these live in the bundled `procmon.chm` help file, **not** on the Learn page, so treat them as
less stable than documented switches). Rejected because a trace generates hundreds of MB to GB in
minutes, boot logging requires a reboot cycle to retrieve, and `.pml` is a binary format only
Procmon reads — useless in an HTML report. It is a superb interactive debugging tool for you on
your dev machine. It is not a pipeline component.

### 7.4 Tools that PowerShell 7 already does better

`PsService` (`Get-Service`/`Set-Service`/`sc.exe`), `PsInfo` (CIM, and it needs the Remote Registry
service), `PsLogList` (`Get-WinEvent` — strictly more capable and already used by the Phase B health
audit), `PsList`/`PsKill`/`PsSuspend` (`Get-Process`/`Stop-Process`), `PsShutdown`
(`shutdown.exe`, already used), `PsPing` (`Test-NetConnection`), `tcpvcon`
(`Get-NetTCPConnection`), `Junction`/`FindLinks` (`New-Item -ItemType SymbolicLink`/`HardLink`).

Adding a download, an EULA, and a text-parser to replace a native cmdlet is pure cost. Don't.

### 7.5 Never

`NotMyFault` (deliberately bluescreens the machine), `BlueScreen` (BSOD screensaver — not in the
Suite zip for this reason), `CPUSTRES`, `Testlimit`. These exist to break systems for testing.
There is no scenario in which an unattended monthly maintenance run should carry them.

---

## 8. Sysmon: what we already run, and the traps around it

Sysmon 15.21 is installed by `Install-SysmonWithConfig`
([SystemConfiguration.psm1:124](modules/type2/SystemConfiguration.psm1#L124)) via
`winget install --id Microsoft.Sysinternals.Sysmon`, then configured with
[config/sysmon/sysmonconfig.xml](config/sysmon/sysmonconfig.xml).

**Command line:** `-i [config]` install · `-c [config]` update config (or dump current config with
no argument) · `-c --` reset to defaults · `-m` install event manifest · `-s` print schema ·
`-u [force]` uninstall · `-accepteula`. Neither install nor uninstall requires a reboot. Events go
to `Applications and Services Logs/Microsoft/Windows/Sysmon/Operational`, timestamped UTC.

The module's idempotency is correct: it uses `-c` when the service already exists and `-i` only for
a fresh install. Our config declares `schemaversion="4.50"` and
`<HashAlgorithms>md5,sha256,IMPHASH</HashAlgorithms>`.

### Interactions to keep in mind — Sysmon watches what this project *does*

Because Sysmon is a kernel-level monitor and this project performs aggressive file and registry
surgery on the same machine, they interact. Three of these are already handled correctly and should
stay that way; one is a live consideration.

| Sysmon feature | Interaction with this project | Status |
|---|---|---|
| **Event 28 `FileBlockShredding`** | *"generated when Sysmon detects and blocks file shredding from tools such as SDelete"* — with the wrong config, our own Sysmon would **block our own SDelete**. | ✅ Not configured. Another reason SDelete stays opt-in (§6.6). |
| **Event 23 `FileDelete` + `ArchiveDirectory`** | Event 23 **saves a copy of every deleted file** into `ArchiveDirectory` (default `C:\Sysmon`). Combined with DiskCleanup deleting thousands of temp files monthly, this would silently consume more disk than the cleanup frees — a maintenance tool that fills the disk. The docs' own warning: *"this directory might grow to an unreasonable size."* | ✅ Our config comments `ArchiveDirectory` out (and records that an invalid `enabled` attribute fail-fast crashes Sysmon 15.x with `0xC0000409`), and scopes `FileDelete` narrowly to `Security.evtx`/`System.evtx`/`Application.evtx` and `\Prefetch\`. **Do not broaden it.** |
| **`FileDelete` T1070.004 `\Prefetch\` rule** | If DiskCleanup is ever extended to purge Prefetch, it will generate anti-forensics alerts **against itself**, every month. | ⚠️ DiskCleanup does not currently touch Prefetch. Keep it that way, or add an exclusion for our own process first. |
| **Event 15 `FileCreateStreamHash`** | Fires on `Zone.Identifier` creation — i.e. the launcher's own `master.zip` download. Expected noise, not a problem. | ℹ️ Informational. |
| **Events 12/13/14 `RegistryEvent`** | `SystemConfiguration` applies ~300 registry baseline values per run; each is a registry-set event. Also the EULA pre-seed in §3.1. | ℹ️ Expected. Consider a rule-group exclusion for our own image path if the volume becomes annoying. |

**General principle: every Type2 action module writes to the system, and Sysmon logs writes.**
When adding a Sysinternals tool or a new remediation, ask what it looks like in the Sysmon log
before shipping it.

---

## 9. Recommended integration plan, in priority order

Sequenced by value-per-unit-risk. Each phase is independently shippable.

### Phase 0 — infrastructure (prerequisite for everything below)

1. `Get-SysinternalsTool -Name <tool>` in [Maintenance.psm1](modules/core/Maintenance.psm1):
   download `https://download.sysinternals.com/files/<Name>.zip` → extract to
   `temp_files/tools/` → resolve `64`-first (§2.2) → verify Microsoft Authenticode signature
   (§2.4) → return the path, or `$null` with a `WARN` on any failure.
2. Seed the EULA registry values in both `HKCU:` and `HKEY_USERS\S-1-5-18` (§3.1).
3. `Invoke-SysinternalsCommand` — stdout-capturing sibling of `Invoke-ExternalPackageCommand`
   (§3.2), always injecting `-accepteula` and `-nobanner`.
4. A `modules.sysinternals` block in `main-config.json`: a master `enabled` flag plus a per-tool
   toggle, so any of this can be switched off centrally.

**Every caller must tolerate `$null`.** No Sysinternals feature may ever fail the run — same rule
as winget being a soft requirement.

### Phase 1 — MoveFile in DiskCleanup ⭐ highest value, lowest risk

Boot-time deletion of locked temp files (§5.1a). Small, self-contained, fixes a real recurring
failure, and pairs perfectly with the Stage 5 reboot. Remember `RebootRequired = $true` and the
strict path allowlist.

### Phase 2 — Handle for lock diagnostics

Log the holder when the extracted-tree cleanup or a DiskCleanup delete fails (§5.2). Read-only,
turns two silent failure modes into named ones. Pairs naturally with Phase 1: report the holder,
queue the delete, reboot.

### Phase 3 — PendMoves in the reboot signal

Enrich `Test-CbsRebootPending` and the report with *what* is actually queued (§5.1b). Read-only,
trivial parser, immediately visible in the report.

### Phase 4 — Autorunsc in `SystemConfigurationAudit` Phase B ⭐ biggest capability gain

`-a * -c -h -s -t *`, persisted to `temp_files/data/autoruns-audit.json`, rendered as a new report
section (§5.3). **Report-only to begin with** — get the data visible and confirm what it finds on
real machines before letting any Type2 code act on it. Must run *after* `Save-DiffList`, in Phase B,
for the reason Phase B exists.

### Phase 5 — Sigcheck for unsigned executables and root-store hygiene

Scoped `-u -e -s -c` over high-risk directories, plus `-tv` on the certificate store (§5.4). No
VirusTotal. Report-only.

### Phase 6 — `du` in `DiskCleanupAudit`

Faster and more accurate reclaim estimates, with a real `DirectorySizeOnDisk` before/after figure
in the report (§5.5). Pure optimisation of something that already works — hence last among the
recommended items.

### Later / opt-in

AccessChk service-and-directory ACL audit (§6.1, report-only), ListDLLs `-u` (§6.3),
Coreinfo/NTFSInfo inventory garnish (§6.5). SDelete `-z` only if this ever targets VMs (§6.6).

### Explicitly out of scope

RAMMap, PsExec, Procmon, ProcDump-in-the-normal-path, every GUI tool, and every Ps\* tool that
duplicates a PowerShell 7 cmdlet.

---

## 10. Sources

All Microsoft Learn pages retrieved 7 August 2026.

**Suite-level**
- [Sysinternals Utilities index](https://learn.microsoft.com/en-us/sysinternals/downloads/) — complete tool list with versions
- [Sysinternals Suite](https://learn.microsoft.com/en-us/sysinternals/downloads/sysinternals-suite) — bundle contents, download sizes
- [Microsoft Store version](https://learn.microsoft.com/en-us/sysinternals/downloads/microsoft-store) — MSIX packaging, app execution aliases, per-user install
- [Sysinternals Software License Terms](https://learn.microsoft.com/en-us/sysinternals/license-terms)
- [Sysinternals home / Sysinternals Live](https://learn.microsoft.com/en-us/sysinternals/)

**Per-tool documentation**
- [Autoruns / Autorunsc](https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns)
- [Sigcheck](https://learn.microsoft.com/en-us/sysinternals/downloads/sigcheck)
- [Handle](https://learn.microsoft.com/en-us/sysinternals/downloads/handle)
- [PendMoves and MoveFile](https://learn.microsoft.com/en-us/sysinternals/downloads/pendmoves)
- [Streams](https://learn.microsoft.com/en-us/sysinternals/downloads/streams)
- [AccessChk](https://learn.microsoft.com/en-us/sysinternals/downloads/accesschk)
- [Disk Usage (Du)](https://learn.microsoft.com/en-us/sysinternals/downloads/du)
- [SDelete](https://learn.microsoft.com/en-us/sysinternals/downloads/sdelete)
- [Contig](https://learn.microsoft.com/en-us/sysinternals/downloads/contig)
- [ListDLLs](https://learn.microsoft.com/en-us/sysinternals/downloads/listdlls)
- [LogonSessions](https://learn.microsoft.com/en-us/sysinternals/downloads/logonsessions)
- [ProcDump](https://learn.microsoft.com/en-us/sysinternals/downloads/procdump)
- [Process Monitor](https://learn.microsoft.com/en-us/sysinternals/downloads/procmon)
- [RAMMap](https://learn.microsoft.com/en-us/sysinternals/downloads/rammap)
- [Sysmon](https://learn.microsoft.com/en-us/sysinternals/downloads/sysmon) — full event ID reference and config schema
- [PsExec](https://learn.microsoft.com/en-us/sysinternals/downloads/psexec)
- [PsInfo](https://learn.microsoft.com/en-us/sysinternals/downloads/psinfo)
- [PsService](https://learn.microsoft.com/en-us/sysinternals/downloads/psservice)
- [PsLogList](https://learn.microsoft.com/en-us/sysinternals/downloads/psloglist)
- [PsShutdown](https://learn.microsoft.com/en-us/sysinternals/downloads/psshutdown)
- [PsPing](https://learn.microsoft.com/en-us/sysinternals/downloads/psping)

**Supplementary (non-Microsoft — flagged where relied upon)**
- [winget-pkgs — Microsoft/Sysinternals manifests](https://github.com/microsoft/winget-pkgs/tree/master/manifests/m/Microsoft/Sysinternals) — the individual winget package names
- EULA registry acceptance under SYSTEM: community-documented, not on Learn — see
  [The Lonely Administrator](https://jdhitsolutions.com/blog/powershell/9130/configure-sysinternals-eula-acceptance/)
  and [Batch Files, Task Scheduler and PSTools – and a EULA?](https://techcommunity.microsoft.com/blog/askperf/batch-files-task-scheduler-and-pstools-8211-and-a-eula/373486)
- `HKU\.DEFAULT` ≡ `HKU\S-1-5-18` (LocalSystem profile): see Raymond Chen,
  [The .Default user is not the default user](https://devblogs.microsoft.com/oldnewthing/20070302-00/?p=27783)
- Sysinternals EULA registry writes as a monitored behaviour:
  [Sigma rule — Usage of Renamed Sysinternals Tools](https://detection.fyi/sigmahq/sigma/windows/registry/registry_set/registry_set_renamed_sysinternals_eula_accepted/)
- RAMMap `-Et`/`-Ew`/`-E0…-E4` switches are **undocumented** — community-sourced only, which is
  part of why §7.1 rejects them

**Books referenced by the official docs**
- *Troubleshooting with the Windows Sysinternals Tools* — Russinovich & Margosis
- *Windows Internals* — Russinovich, Solomon, Ionescu
