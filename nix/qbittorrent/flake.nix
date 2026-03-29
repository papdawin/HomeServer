{
  description = "qBittorrent NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.qbittorrent = nixpkgs.lib.nixosSystem {
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
            services.qbittorrent.enable = true;
            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };
            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 8080 6881 ];
            networking.firewall.allowedUDPPorts = [ 6881 ];
          })
        ];
    };
  };
}
