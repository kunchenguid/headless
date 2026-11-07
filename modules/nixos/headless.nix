{ config, lib, ... }:

# The headless layer for a NixOS machine that has no keyboard, screen or
# person in front of it and is reached only over SSH. Import it and set
# `headless.*`; the headless skill writes those settings for you
# (skills/headless). The options match the nix-darwin module's where the
# idea is the same; references/linux.md lists them.
let
  cfg = config.headless;
  inherit (lib) mkOption types;
  # Every value the module sets uses this: above a plain definition (100),
  # so a machine's own configuration.nix that says otherwise does not stop
  # the build with conflicting values; below lib.mkForce (50), so a
  # deliberate choice in machine.nix still wins.
  headlessWins = lib.mkOverride 90;
  bool = b: if b then "true" else "false";
in
{
  options.headless = {
    user = mkOption {
      type = types.strMatching "[a-z_][a-z0-9_-]*";
      description = "The admin account the machine is set up for.";
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
        Start the user's session at boot without anyone signing in
        (systemd lingering), so the user's own services run unattended.
        Nothing signs in on the console.
      '';
    };
    tailscale.enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run the Tailscale daemon. The skill joins it to your tailnet
        afterwards, with a sign-in link or an auth key.
      '';
    };
    extras = {
      neverSleep = mkOption {
        type = types.bool;
        default = true;
        description = "Never suspend or hibernate: the sleep targets are masked.";
      };
      autoUpdates = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Install updates automatically. This is for the skill's
          distro-neutral script on other distributions; on NixOS updates come
          from your config folder (update flake.lock, then apply), so this
          option changes nothing here.
        '';
      };
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

    users.users.${cfg.user} = {
      isNormalUser = lib.mkDefault true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = cfg.sshKeys;
      linger = headlessWins cfg.autoLogin;
    };
    # Every admin step pipes the password to sudo; the machine keeps no
    # passwordless admin rule.
    security.sudo.wheelNeedsPassword = headlessWins true;

    # The skill's apply step builds the config with flakes on the machine.
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    # apply.sh keeps a copy of the config folder in /etc/nixos, so the
    # machine's own updates (system.autoUpgrade, or nixos-rebuild switch at
    # the machine) build the same system instead of an older configuration.
    system.autoUpgrade.flake = lib.mkDefault "/etc/nixos#machine";
    # With a flake, nixos-rebuild's --upgrade does nothing: the update first
    # moves the flake's nixpkgs input to the newest revision of its branch,
    # so the machine keeps taking security fixes on its own release.
    system.autoUpgrade.upgrade = lib.mkDefault false;
    systemd.services.nixos-upgrade.preStart = lib.mkIf
      (config.system.autoUpgrade.enable && config.system.autoUpgrade.flake == "/etc/nixos#machine") ''
        ${config.nix.package}/bin/nix --extra-experimental-features 'nix-command flakes' \
          flake update nixpkgs --flake path:/etc/nixos
      '';

    # SSH is the only way in. End sessions whose other end is gone after
    # about three minutes, so they never fill the connection limit.
    services.openssh = {
      enable = headlessWins true;
      settings = lib.mkMerge [
        {
          ClientAliveInterval = headlessWins 60;
          ClientAliveCountMax = headlessWins 3;
        }
        (lib.mkIf cfg.keyOnlySsh {
          PasswordAuthentication = headlessWins false;
          KbdInteractiveAuthentication = headlessWins false;
          PermitRootLogin = headlessWins "no";
        })
      ];
    };

    networking.hostName = lib.mkIf (cfg.hostName != null) (headlessWins cfg.hostName);

    systemd.targets = lib.mkIf cfg.extras.neverSleep {
      sleep.enable = headlessWins false;
      suspend.enable = headlessWins false;
      hibernate.enable = headlessWins false;
      hybrid-sleep.enable = headlessWins false;
    };

    # Off leaves Tailscale as the machine's own config has it.
    services.tailscale.enable = lib.mkIf cfg.tailscale.enable (headlessWins true);

    # What this machine should be, for the skill's verify step to read
    # (the same file the distro-neutral script writes).
    environment.etc."headless/settings.env".text = ''
      KIND=nixos
      USER_NAME=${cfg.user}
      HOST_NAME=${if cfg.hostName == null then "" else cfg.hostName}
      KEY_ONLY=${bool cfg.keyOnlySsh}
      AUTO_LOGIN=${bool cfg.autoLogin}
      TAILSCALE=${bool cfg.tailscale.enable}
      NEVER_SLEEP=${bool cfg.extras.neverSleep}
      AUTO_UPDATES=${bool cfg.extras.autoUpdates}
    '';
  };
}
