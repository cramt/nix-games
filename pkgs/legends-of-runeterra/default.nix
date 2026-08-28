# Legends of Runeterra, playable on Linux in 2026.
#
# The interesting part is WHY this needs a bespoke package rather than "run it in
# Proton". LoR is protected by Packman, Riot's ring-3 anti-tamper (ships as
# stub.dll — separate from Vanguard, which LoR does NOT use). Packman executes
# `int 0x2c` and raises STATUS_ASSERTION_FAILURE (0xC0000420) when it dislikes
# its environment, killing the game before Unity writes a single log line.
#
# Current mainline wine (tested: wine-staging 11.15) trips that check. The last
# build that satisfies it is GE-Proton8-27-LoL, which carries two ntdll patches
# not present upstream:
#   - LoL-ntdll-fix-signal-set-full-context.patch
#   - LoL-ntdll-nopguard-call_vectored_handlers.patch
# Full investigation: https://github.com/cramt/lor-on-linux
{
  lib,
  stdenvNoCC,
  fetchurl,
  buildFHSEnv,
  writeShellApplication,
  writeText,
  # runtime
  dxvk,
  coreutils,
  gnugrep,
  gnused,
  findutils,
  # FHS deps for the prebuilt GE-Proton wine
  glibc,
  zlib,
  libGL,
  vulkan-loader,
  libxkbcommon,
  freetype,
  fontconfig,
  alsa-lib,
  libpulseaudio,
  openldap,
  cups,
  gnutls,
  krb5,
  libgcrypt,
  libxml2,
  libjpeg,
  libpng,
  libtiff,
  mesa,
  xorg,
  udev,
  libva,
  gst_all_1,
  ocl-icd,
  vulkan-tools,
}: let
  version = "GE-Proton8-27-LoL";

  # Prebuilt Lutris-style wine. Not buildable from source here: the point of this
  # package is bit-for-bit the binary whose patches Packman accepts.
  wine-ge = stdenvNoCC.mkDerivation {
    pname = "wine-ge-lol";
    inherit version;
    src = fetchurl {
      url = "https://github.com/GloriousEggroll/wine-ge-custom/releases/download/${version}/wine-lutris-${version}-x86_64.tar.xz";
      hash = "sha256-XS0a980eHhb7ebPcwbN97TZQOqHcmS2u5tfeNbjt2ag=";
    };
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true; # prebuilt glibc binaries; patchelf would break them
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a . "$out/"
      runHook postInstall
    '';
    meta.description = "GE-Proton wine build carrying the LoL/Packman ntdll patches";
  };

  # The Riot installer is fetched at runtime, not build time: Riot rebuilds this
  # URL in place (observed 2026-08-11), so pinning a hash would rot immediately
  # and break the package rather than the game.
  installerUrl = "https://bacon.secure.dyn.riotcdn.net/channels/public/x/installer/current/live.live.americas.exe";

  launcher = writeShellApplication {
    name = "legends-of-runeterra-unwrapped";
    runtimeInputs = [coreutils gnugrep gnused findutils vulkan-tools];
    text = ''
      set -uo pipefail

      STATE="''${XDG_DATA_HOME:-$HOME/.local/share}/legends-of-runeterra"
      PFX="$STATE/prefix"
      LOGS="$STATE/logs"
      mkdir -p "$PFX" "$LOGS"

      export WINEPREFIX="$PFX"
      export WINEARCH=win64
      export WINEDEBUG="''${WINEDEBUG:--all}"

      # winemenubuilder writes .desktop files into the real ~/Desktop and
      # ~/.local/share/applications. mscoree/mshtml suppress the Mono and Gecko
      # installer dialogs, which otherwise deadlock an unattended first run.
      export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml=d"

      # The launcher is Electron. On this wine its GPU process cannot create a GL
      # drawable (err:winediag:create_gl_drawable) and the window paints pure
      # black. Forcing Mesa's software path makes it render. This does NOT cost
      # the game any performance: LIBGL_ALWAYS_SOFTWARE is an OpenGL knob, and
      # the game reaches the GPU through D3D11 -> DXVK -> Vulkan, which it does
      # not touch.
      export LIBGL_ALWAYS_SOFTWARE="''${LIBGL_ALWAYS_SOFTWARE:-1}"
      export GALLIUM_DRIVER="''${GALLIUM_DRIVER:-llvmpipe}"

      WINE="${wine-ge}/bin/wine64"

      # ---- first run: init prefix, install DXVK, fetch + run the installer ----
      if [ ! -e "$PFX/drive_c/Riot Games/Riot Client/RiotClientServices.exe" ]; then
        echo "first run: initialising wine prefix (this takes a minute)"
        "$WINE" wineboot -u >"$LOGS/wineboot.log" 2>&1 || true
        "${wine-ge}/bin/wineserver" -w 2>/dev/null || true

        echo "installing DXVK (routes the game's D3D11 through Vulkan)"
        for d in d3d11 dxgi d3d10core; do
          install -Dm644 "${dxvk}/x64/$d.dll" "$PFX/drive_c/windows/system32/$d.dll"
          if [ -d "$PFX/drive_c/windows/syswow64" ]; then
            install -Dm644 "${dxvk}/x32/$d.dll" "$PFX/drive_c/windows/syswow64/$d.dll"
          fi
        done

        echo "downloading the Riot installer"
        INST="$STATE/riot-installer.exe"
        curl -sSL --fail -o "$INST" "${installerUrl}" \
          || { echo "failed to download the Riot installer" >&2; exit 1; }

        echo
        echo "The Riot installer will open. Click Install, then sign in."
        echo "Afterwards this command launches the game directly."
        echo
        exec "$WINE" "$INST" --launch-product=bacon --launch-patchline=live
      fi

      # ---- normal launch ----
      # DXVK must be declared native or wine uses its own builtin d3d11.
      export WINEDLLOVERRIDES="$WINEDLLOVERRIDES;d3d11,dxgi,d3d10core=n"

      exec "$WINE" "$PFX/drive_c/Riot Games/Riot Client/RiotClientServices.exe" \
        --launch-product=bacon --launch-patchline=live
    '';
  };
in
  # GE-Proton is a prebuilt glibc binary expecting an FHS layout
  # (/lib64/ld-linux-x86-64.so.2), which NixOS does not provide. buildFHSEnv
  # supplies it — deliberately instead of steam-run, which drags in unfree
  # steam-unwrapped and would force allowUnfree on every consumer of this repo.
  buildFHSEnv {
    name = "legends-of-runeterra";
    runScript = "${launcher}/bin/legends-of-runeterra-unwrapped";

    targetPkgs = pkgs:
      [
        glibc
        zlib
        libGL
        vulkan-loader
        libxkbcommon
        freetype
        fontconfig
        alsa-lib
        libpulseaudio
        openldap
        cups
        gnutls
        krb5
        libgcrypt
        libxml2
        libjpeg
        libpng
        libtiff
        mesa
        udev
        libva
        ocl-icd
        pkgs.curl
      ]
      ++ (with xorg; [
        libX11
        libXext
        libXrandr
        libXrender
        libXcursor
        libXi
        libXinerama
        libXcomposite
        libXfixes
        libXxf86vm
        libxcb
      ])
      ++ (with gst_all_1; [gstreamer gst-plugins-base gst-plugins-good]);

    meta = with lib; {
      description = "Legends of Runeterra via GE-Proton, with the Packman workaround applied";
      homepage = "https://playruneterra.com";
      # This derivation ships GE-Proton (wine, LGPL-2.1+) and a launcher script.
      # The game itself is proprietary but is downloaded at RUNTIME and never
      # embedded here, so the closure is free and consumers do not need
      # allowUnfree. Playing the game is still subject to Riot's EULA.
      license = with licenses; [lgpl21Plus mit];
      platforms = ["x86_64-linux"];
      mainProgram = "legends-of-runeterra";
    };
  }
