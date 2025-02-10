{
  lib,
  config,
  nixpkgs,
  pkgs,
  ...
}:

let
  pkg1 = pkgs.go;
in

{
  name = "fsync";

  nodes.machine =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      boot.kernelPatches = [
        {
          name = "fs-verity";
          patch = null;
          extraStructuredConfig = {
            FS_VERITY = lib.kernel.yes;
          };
        }
      ];
      virtualisation.emptyDiskImages = [ 1024 ];
      environment.systemPackages = [ pkg1 pkgs.fsverity-utils ];
      nix.settings.experimental-features = [ "nix-command" ];
      nix.settings.fsync-store-paths = true;
      nix.settings.fsverity-store-paths = true;
      nix.settings.require-sigs = false;
      boot.supportedFilesystems = [
        "ext4"
        "btrfs"
      ];
    };

  testScript =
    { nodes }:
    ''
      # fmt: off
      for fs in ("ext4", "btrfs"):
        machine.succeed("mkfs.{} {} /dev/vdb".format(fs, "-O verity -F" if fs == "ext4" else "-f"))
        machine.succeed("mkdir -p /mnt")
        machine.succeed("mount /dev/vdb /mnt")
        machine.succeed("sync")
        machine.succeed("nix copy --offline ${pkg1} --to /mnt")
        machine.crash()

        machine.start()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("mkdir -p /mnt")
        machine.succeed("mount /dev/vdb /mnt")
        machine.succeed("nix path-info --offline --store /mnt ${pkg1}")
        machine.succeed("nix store verify --all --store /mnt --no-trust")
        machine.succeed("find /mnt${pkg1} -type f -print0 | xargs -0 -n 1 fsverity measure")

        machine.succeed("echo test > ./test.txt")
        path = machine.succeed("nix store add --store /mnt --mode flat ./test.txt").strip()
        machine.succeed(f"fsverity measure /mnt{path}")

        machine.succeed("umount /dev/vdb")
    '';
}
