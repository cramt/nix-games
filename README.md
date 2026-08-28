# nix-games

cramt's games, packaged as nixpkgs. Each game is a normal derivation with its
platform-specific workarounds baked in, so running it is one command instead of
an afternoon.

```sh
nix run github:cramt/nix-games#legends-of-runeterra
```

## Packages

| package | notes |
|---|---|
| `legends-of-runeterra` | Works around Riot's Packman anti-tamper, which current mainline wine trips. |

## Use as an overlay

```nix
{
  inputs.nix-games.url = "github:cramt/nix-games";

  # in your nixpkgs config
  nixpkgs.overlays = [inputs.nix-games.overlays.default];
  # then
  environment.systemPackages = [pkgs.legends-of-runeterra];
}
```

Or reference a package directly:

```nix
environment.systemPackages = [inputs.nix-games.packages.${system}.legends-of-runeterra];
```

## Legends of Runeterra

Riot does **not** protect LoR with Vanguard — verified against Riot's own live
client-config service, where `league_of_legends` and `valorant` declare an
`{"id": "vanguard"}` dependency and `bacon` (LoR) declares `"dependencies": null`
on every platform.

What it *does* ship is **Packman**, Riot's ring-3 anti-tamper and PE-encryption
layer (`stub.dll`). Packman decrypts the game at startup, hooks `VirtualProtect`,
and runs integrity plus anti-debug checks. When it dislikes its environment it
executes `int 0x2c`, raising `STATUS_ASSERTION_FAILURE` (`0xC0000420`) — a
deliberate abort, not a crash — before Unity writes a single log line.

Current mainline wine trips that check. wine-staging 11.15 produces a 0-byte
Unity log and dies. GE-Proton8-27-LoL boots the game, because it carries two
ntdll patches that never landed upstream:

- `LoL-ntdll-fix-signal-set-full-context.patch` — `signal_set_full_context()`
  skips restoring integer registers when `NtContinue` is called with
  ContextFlags lacking the `CONTEXT_AMD64` bit, corrupting register state.
- `LoL-ntdll-nopguard-call_vectored_handlers.patch` — NOP guard around ntdll's
  vectored-handler dispatch, which Packman patches around.

So this package pins that wine build. Two further quirks it handles:

- **The launcher renders black** without software OpenGL. Electron's GPU process
  can't create a GL drawable on this wine (`err:winediag:create_gl_drawable`).
  `LIBGL_ALWAYS_SOFTWARE=1` fixes it and costs the game nothing, because the game
  reaches the GPU via D3D11 → DXVK → **Vulkan**, which that variable doesn't
  touch.
- **DXVK is installed into the prefix.** Without it the game runs on wined3d and
  reports a fake adapter (an "NVIDIA GeForce GTX 470" on an Intel laptop), with
  CPU load ~24 on 12 threads. With it, the real GPU is named and load drops to
  ~4.

Full investigation, including the measurements behind every claim above:
<https://github.com/cramt/lor-on-linux>

### First run

The Riot installer is downloaded at runtime and opens for you to click through
and sign in. Subsequent runs launch the game directly. State lives in
`$XDG_DATA_HOME/legends-of-runeterra` (prefix, logs), never in the store.

The installer URL is fetched at runtime rather than pinned with a hash on
purpose: Riot rebuilds that URL in place (observed 2026-08-11), so a pinned hash
would rot and break the package rather than the game.

### The black square in the corner

On Wayland desktops a black 32×32 square appears in the top-left corner
whenever the client runs. It's wine's standalone systray holder window,
unembedded because Wayland compositors generally don't own
`_NET_SYSTEM_TRAY_S0` and so never adopt it.

This package sets `ShowSystray` in the prefix, which fixes it:

```
HKCU\Software\Wine\X11 Driver  ShowSystray  = "N"   (wine <= 9.21)
HKCU\Software\Wine\Explorer    ShowSystray  = 0     (newer wine)
```

That gates only `ShowWindow()` on the tray window — the windows are still
created, so `Shell_NotifyIcon` succeeds and the app is none the wiser.

**Do not** use `WINEDLLOVERRIDES=explorer.exe=d` instead. It removes the square
but kills the client after ~6s with no window at all, because wine's explorer
also handles desktop and window management. Measured the hard way.

Side effect: the tray icon becomes invisible, hence unclickable. Close the
client via its own window. If you want the icon usable in your panel, an
XEmbed→StatusNotifierItem bridge (`xembedsniproxy`, in
`kdePackages.plasma-workspace`) is the direction — COSMIC's lead dev names it as
the fix in [cosmic-epoch#974](https://github.com/pop-os/cosmic-epoch/issues/974).

## Adding a game

1. `pkgs/<name>/default.nix` with a normal derivation
2. one line in `pkgs/default.nix`
3. `nix build .#<name>`

`pkgs/default.nix` is a plain attrset taking `{pkgs}`, so it serves as both the
per-system package set and the overlay body.

## Licence

Packaging is MIT. The games themselves are covered by their own licences and are
not redistributed here — these derivations fetch from official sources.
