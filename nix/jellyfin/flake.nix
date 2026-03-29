{
  description = "NixOS services for Proxmox LXC containers";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.jellyfin = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
        ({ ... }: {
          system.stateVersion = "25.11";
          boot.isContainer = true;
          systemd.mounts = [
            {
              enable = false;
              where = "/sys/kernel/debug";
            }
          ];
          services.jellyfin.enable = true;
          services.openssh = {
            enable = true;
            settings = {
              PasswordAuthentication = true;
              PermitRootLogin = "yes";
            };
          };
          networking.firewall.allowPing = true;
          networking.firewall.allowedTCPPorts = [ 22 8096 ];
        })
      ];
    };
  };
}
