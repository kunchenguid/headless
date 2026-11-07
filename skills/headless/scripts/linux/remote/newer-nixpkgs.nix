# remote/newer-nixpkgs.nix - the config folder's flake.lock with the
# nixpkgs of the machine's /etc/nixos/flake.lock, when the machine's own
# updates moved it to a newer revision of the same branch and the machine's
# boot default was built from it (an update that did not build is not
# kept); "" otherwise. apply.sh runs it on the machine with nix eval.
folder: machine:
let
  a = builtins.fromJSON (builtins.readFile folder);
  b = builtins.fromJSON (builtins.readFile machine);
  # The node a lock's top-level nixpkgs input names (not one it follows).
  node = lock: lock.nodes.${lock.root}.inputs.nixpkgs or null;
  na = node a;
  nb = node b;
  newer = builtins.isString na && builtins.isString nb
    && (a.nodes.${na}.original or null) == (b.nodes.${nb}.original or null)
    && (b.nodes.${nb}.locked.lastModified or 0) > (a.nodes.${na}.locked.lastModified or 0)
    && built (b.nodes.${nb}.locked.rev or "");
  # The boot default's version ends in the nixpkgs revision it was built
  # from, shortened (26.05.20261105.c56a87d).
  version = builtins.readFile /nix/var/nix/profiles/system/nixos-version;
  short = builtins.match ".*[.]([0-9a-f]+)" version;
  built = rev: short != null
    && builtins.substring 0 (builtins.stringLength (builtins.head short)) rev == builtins.head short;
in
if newer then builtins.toJSON (a // { nodes = a.nodes // { ${na} = b.nodes.${nb}; }; }) else ""
