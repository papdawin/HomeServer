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
            users.mutableUsers = false;
            users.groups.media = {
              gid = 2000;
            };
            users.users.papdawin = {
              isNormalUser = true;
              extraGroups = [
                "wheel"
                "qbittorrent"
                "media"
              ];
              hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
            };
            users.users.qbittorrent.extraGroups = [ "media" ];
            systemd.tmpfiles.rules = [
              "d /media 2775 root media -"
              "d /media/movies 2775 root media -"
              "d /media/shows 2775 root media -"
              "d /media/series 2775 root media -"
              "d /media/other 2775 root media -"
              "d /media/music 2775 root media -"
              "z /var/lib/qBittorrent 0750 qbittorrent qbittorrent -"
              "z /var/lib/qBittorrent/qBittorrent 0750 qbittorrent qbittorrent -"
              "z /var/lib/qBittorrent/qBittorrent/config 0750 qbittorrent qbittorrent -"
            ];
            services.qbittorrent.enable = true;
            systemd.services.qbittorrent.serviceConfig.UMask = "0002";
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
