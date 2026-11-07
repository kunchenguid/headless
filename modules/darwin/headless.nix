{ config, lib, pkgs, ... }:

# The headless layer for a Mac that has no keyboard, screen or person in
# front of it and is reached only over SSH. Import it and set `headless.*`;
# the headless skill writes those settings for you (skills/headless).
#
# Determinate Nix manages Nix itself, so nix-darwin leaves Nix alone.
let
  cfg = config.headless;
  inherit (lib) mkOption types;
  ext = cfg.extras;
  extra = description: mkOption {
    type = types.bool;
    default = true;
    inherit description;
  };
in
{
  # nix-darwin's /Applications/Nix Apps step checks for the App Management
  # permission, which nobody can grant over SSH, and fails activation. A
  # headless Mac installs no Nix app bundles, so the whole step goes.
  disabledModules = [ "system/applications.nix" ];

  options.headless = {
    user = mkOption {
      type = types.strMatching "[a-z_][a-z0-9_-]*";
      description = "The admin account the machine is set up for and signs in to.";
    };
    hostName = mkOption {
      type = types.nullOr (types.strMatching "[A-Za-z0-9][A-Za-z0-9-]{0,62}");
      default = null;
      description = "The machine's name on the network and in Tailscale; null keeps the current one.";
    };
    sshKeys = mkOption {
      type = types.listOf (types.strMatching "(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) [A-Za-z0-9+/=]+( .*)?");
      default = [ ];
      description = "Public keys that may sign in as the user, besides ~/.ssh/authorized_keys.";
    };
    keyOnlySsh = mkOption {
      type = types.bool;
      default = true;
      description = "Turn SSH password and keyboard-interactive sign-in off, and root sign-in off.";
    };
    autoLogin = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Sign the user in on the machine's screen at every start, so apps that
        need a signed-in session run unattended. Needs FileVault off. The
        password itself is written once by the skill's admin step
        (/etc/kcpassword); turning this off removes it.
      '';
    };
    tailscale.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run the open-source Tailscale daemon. The skill joins it to your
        tailnet afterwards, with a sign-in link or an auth key. Leave this off
        on a Mac that already runs the Tailscale app.
      '';
    };
    extras = {
      neverSleep = extra "Never sleep the machine or its disks; only the display sleeps.";
      startAfterPowerLoss = extra "Start up again by itself after a power cut, and whenever power is connected.";
      wakeOnLan = extra "Wake for network access.";
      powerNapOff = extra "Turn Power Nap off.";
      spotlightOff = extra "Turn Spotlight indexing off on every volume.";
      siriOff = extra "Turn Siri off for the user.";
    };
  };

  config = {
    assertions = [
      {
        assertion = !(cfg.keyOnlySsh && cfg.sshKeys == [ ]);
        message = "headless.keyOnlySsh needs at least one key in headless.sshKeys, or nobody could sign in.";
      }
      {
        assertion = !(lib.any (lib.hasSuffix " example-key-replaced-by-setup") cfg.sshKeys);
        message = "headless.sshKeys still holds the template's example key; put your own public key in settings.json (the skill's new-config.sh does).";
      }
    ];

    # Determinate Nix manages Nix.
    nix.enable = false;
    system.primaryUser = cfg.user;

    users.users.${cfg.user} = {
      home = lib.mkDefault "/Users/${cfg.user}";
      # nix-darwin serves these from /etc/ssh/nix_authorized_keys.d.
      openssh.authorizedKeys.keys = cfg.sshKeys;
    };

    # The empty app environment keeps the modules that read it evaluating
    # now that the applications step is gone (disabledModules above).
    system.build.applications = pkgs.buildEnv {
      name = "system-applications";
      paths = config.environment.systemPackages;
      pathsToLink = [ "/Applications" ];
    };
    system.activationScripts.applications.text = "";

    # SSH is the only way in. End sessions whose other end is gone after
    # about three minutes, so they never fill the connection limit.
    services.openssh.enable = true;
    services.openssh.extraConfig = "ClientAliveInterval 60\nClientAliveCountMax 3";

    # The Determinate Nix installer adds its hook to these files, and its
    # repair job writes them again at start-up. These are that file's exact
    # bytes, so nix-darwin may replace it.
    environment.etc =
      let
        determinateHook = "\n# Nix\nif [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then\n    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'\nfi\n# End Nix\n\n        \n";
        known.knownSha256Hashes = [ (builtins.hashString "sha256" determinateHook) ];
      in
      {
        zshrc = known;
        bashrc = known;
        # sshd takes the first value it reads, and macOS's own drop-in is
        # 100-macos.conf, so this one is named to come first.
        "ssh/sshd_config.d/000-headless.conf".text = lib.optionalString cfg.keyOnlySsh ''
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          PermitRootLogin no
        '';
        # What this machine should be, for the skill's verify step to read.
        "headless/settings.json".text = builtins.toJSON {
          inherit (cfg) user hostName keyOnlySsh autoLogin extras;
          tailscale = cfg.tailscale.enable;
        };
      };

    services.tailscale.enable = cfg.tailscale.enable;

    networking.computerName = lib.mkIf (cfg.hostName != null) cfg.hostName;
    networking.hostName = lib.mkIf (cfg.hostName != null) cfg.hostName;
    networking.localHostName = lib.mkIf (cfg.hostName != null) cfg.hostName;

    system.defaults.loginwindow.autoLoginUser = if cfg.autoLogin then cfg.user else null;

    # Only the display may sleep; there is no screen to keep awake.
    power.sleep = lib.mkIf ext.neverSleep {
      computer = "never";
      harddisk = "never";
      display = 10;
    };

    system.defaults.CustomUserPreferences = lib.mkIf ext.siriOff {
      "com.apple.assistant.support"."Assistant Enabled" = false;
      "com.apple.Siri" = {
        StatusMenuVisible = false;
        VoiceTriggerUserEnabled = false;
      };
    };

    system.activationScripts.postActivation.text = lib.concatStringsSep "\n" (
      [
        ''
          # Some Macs, virtual ones among them, lack a power setting; pmset
          # lists the ones this Mac has.
          headless_has() { /usr/bin/pmset -g cap | /usr/bin/grep -qw "$1"; }
        ''
      ]
      ++ lib.optional ext.powerNapOff ''
        echo >&2 "headless: turning Power Nap off..."
        headless_has powernap && /usr/bin/pmset -a powernap 0
      ''
      ++ lib.optional ext.startAfterPowerLoss ''
        # Start up after a power cut (autorestart).
        echo >&2 "headless: turning start-up after power loss on..."
        if headless_has autorestart; then
          /usr/bin/pmset -a autorestart 1
        else
          echo >&2 "headless: warning: this Mac has no start-up after power loss setting"
        fi
      ''
      ++ lib.optional ext.wakeOnLan ''
        echo >&2 "headless: turning wake for network access on..."
        if headless_has womp; then
          /usr/bin/pmset -a womp 1
        else
          echo >&2 "headless: warning: this Mac has no wake for network access setting"
        fi
      ''
      ++ lib.optional ext.spotlightOff ''
        echo >&2 "headless: turning Spotlight indexing off..."
        /usr/bin/mdutil -a -i off > /dev/null || echo >&2 "headless: warning: Spotlight indexing could not be turned off"
      ''
      ++ lib.optional (!cfg.autoLogin) ''
        if [ -e /etc/kcpassword ]; then
          echo >&2 "headless: automatic sign-in is off; removing its stored password..."
          rm -f /etc/kcpassword
        fi
      ''
      ++ lib.optional cfg.autoLogin ''
        [ -e /etc/kcpassword ] \
          || echo >&2 "headless: warning: automatic sign-in has no stored password; run the skill's admin step"
        [ "$(/usr/bin/fdesetup isactive 2> /dev/null || true)" != true ] \
          || echo >&2 "headless: warning: FileVault is on, so automatic sign-in cannot work"
      ''
    );
  };
}
