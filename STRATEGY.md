# headless Strategy

## Vision

<!-- vision: author-approved 2026-11-21 -->

`headless` exists so that a person can hand an agent the machines they will never sit at and get back machines that run unattended, without ever giving the agent their keys.
It serves an individual owner with a Mac mini in a closet, a Linux box under the desk, a Windows PC nobody sits at, or a rented server.
It turns admin access over SSH - usually an admin account with a password and remote login on - into machines that never sleep, sign themselves in after a restart, take SSH keys only, and come back.
It owns exactly one thing: the journey from that first admin sign-in to a headless machine verified through a restart, and the way back.

### The agent never holds the secret

The admin password lives in the user's secret store, and the agent only ever names the entry.
Scripts read the secret themselves and pipe it on a file descriptor or standard input; it never lands on a command line, in the agent's environment, in a config folder, or in a log.
No step weakens the machine's own guard to make the agent's life easier: there is no passwordless sudo rule, not even as an opt-in, and every later admin step reads the password from the store again.
A machine that starts with key-only access and no password has no secret to hold, and the rest of the journey is the same.
Coming back after a power cut outranks protecting the disk at rest: when automatic sign-in is chosen, FileVault goes off, and no mode trades that for a machine that may stop at an unlock screen.
Where unattended operation forces a secret onto the machine itself - the automatic sign-in password, the Windows LSA secret - it is kept the platform's own way, root-only, and the user is told plainly what that costs.
Every secret path is proven by a CI journey whose log is checked for the secret.

### One step at a time, every step reruns

Each step says what it does, runs, and shows its result before the next one starts.
Apply changes only what differs and says what it changed; a second apply changes nothing.
A failing step stops with a plain message saying what to do, and stops before changing anything whenever the failure can be detected in advance.
Verify reads every setting back from the machine and claims only what it actually checked; a verify that passes a setting it did not inspect is a bug.
The journey is not done until the machine has restarted and been verified again.
Key-only sign-in turns on only after the user's key has been proven to work, and a changed host key stops every step on purpose.

### The user decides, and the machine keeps what is its own

The skill asks before anything the user did not choose, and never works around a failed step by loosening security.
Handing the agent a set of machines is consent to set up each of them; the work may run in parallel, but every machine still gets its own steps, results, and verify through a restart.
Destructive or one-way actions - erasing a disk to install NixOS, uninstalling a Tailscale another account joined - happen only after the user agrees.
Where the user already chose the outcome, as with automatic sign-in requiring FileVault off, the skill acts and asks only when the platform refuses.
Optional reach stays optional: Tailscale is offered, never required.
An existing NixOS machine keeps its own config, its release, and its own updates; the skill layers its settings on and refuses rather than overwrites what it does not own.
The way back belongs to the journey: undoing headless returns a machine toward its platform defaults as far as it can, and tells the user plainly what it cannot restore.

### Declarative where the owner wants it, the same guarantee everywhere

Nix is the default where it fits: a nix-darwin module on a Mac and a NixOS module on NixOS, both usable from the user's own flake without the skill.
Nix is never a gate: a plain script path with the same settings and the same rerun guarantee is welcome wherever an owner does not want Nix, a Mac included, as it already is for Debian, Ubuntu, Fedora, and Windows.
The settings are few and specific to running unattended: power, sign-in, SSH, reachability, and the platform extras that keep a machine from stalling or waking someone.

### Proven on the real thing

Each platform's whole journey runs end to end in CI, over SSH to itself, on GitHub-hosted or self-hosted runners, and changes are also exercised on fresh real or virtual machines before they land.
A platform, release, or path is supported only when a CI journey proves it; one no runner can exercise is not supported, however well it was tested by hand.
Field bugs are reproduced on a disposable machine before they are fixed, and the fix lands with the coverage that would have caught it.
Docs speak in the user's outcomes - the Mac comes back, password sign-in is refused - not in the machinery.

### Scope

headless is not general configuration management, not a provisioning or imaging service, and not a fleet manager: it can set up many machines in one run, but it keeps no inventory and no standing view of them afterward.
It does not install the user's workloads, toolchains, container runtimes, or agent harnesses; the machine it hands back is a clean, reachable, unattended base, and the user's own flake or tools build on it.
The first console step - an admin account with remote login on - stays the user's; automating it with keyboard dongles, KVMs, or MDM adds more complexity than it removes.
Nothing stays resident on the machine to watch for drift until owners clearly ask for one; until then, rerunning the skill is the drift check.
Personal material - the config folder, keys, store entries - stays on the user's computer and in their store, never in this repository.
This repository ships through its own discipline: pull requests go through no-mistakes, and shellcheck, flake checks, and every platform journey stay green.

A change aligns when it makes an unattended machine more reliably reachable after a restart, keeps the secret further from the agent, makes a step more honest about what it changed or checked, lowers what an owner must accept to get the same guarantee, makes the way back clearer, adds a platform with a CI journey that proves it, or turns a confusing failure into a plain refusal.
A change should be resisted when it puts a secret where the agent or a log can read it, weakens sudo or SSH for convenience, trades coming back after a restart for something else, acts beyond what the user chose, claims a setting it does not verify, adds a platform or path no CI journey proves, adds machinery that costs more than the human step it removes, or grows the skill from setting up a headless base into managing what runs on it.
