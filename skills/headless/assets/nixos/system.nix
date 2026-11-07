# The machine's disks, boot loader and hardware, for a machine the skill
# installs NixOS on (install-nixos.sh). On a machine that already ran
# NixOS, the skill replaces this file with one that imports the machine's
# own /etc/nixos configuration instead.
{ config, lib, ... }:
let
  # The whole disk NixOS is installed on; install-nixos.sh writes the one
  # you chose. Everything on it is erased at install.
  disk = "/dev/sda";
in
{
  # Written by install-nixos.sh from the machine itself.
  imports = lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  # GRUB on a GPT disk with both a BIOS boot partition and an EFI system
  # partition, so the same layout starts on BIOS and UEFI machines.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  disko.devices.disk.main = {
    device = disk;
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        bios = {
          size = "1M";
          type = "EF02";
        };
        esp = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  # The account's password is the one it had before the install:
  # install-nixos.sh carries its hash over in this root-only file, read only
  # when the account is first made.
  users.users.${config.headless.user}.hashedPasswordFile = "/var/lib/headless/password-hash";
  users.mutableUsers = true;

  # The release this machine was first installed with; never change it.
  system.stateVersion = "26.05";
}
