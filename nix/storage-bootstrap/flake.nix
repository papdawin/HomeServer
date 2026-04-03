{
  description = "Storage bootstrap NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.storagebootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ ... }: {
            system.stateVersion = "25.11";
            boot.isContainer = true;

            systemd.mounts = [
              {
                enable = false;
                where = "/sys/kernel/debug";
              }
            ];

            # Keep root credentials from LXC initialization (set by Terraform),
            # so NixOS doesn't assert lockout on this utility container.
            users.mutableUsers = true;
            users.groups.media = {
              gid = 2000;
            };

            # Names are informational in this helper; cross-container access is
            # controlled by shared group ID ownership on /media.
            users.users.jellyfin = {
              isSystemUser = true;
              group = "media";
            };
            users.users.qbittorrent = {
              isSystemUser = true;
              group = "media";
            };

            systemd.tmpfiles.rules = [
              "d /media 2775 root media -"
              "d /media/movies 2775 root media -"
              "d /media/shows 2775 root media -"
              "d /media/series 2775 root media -"
              "d /media/other 2775 root media -"
              "d /media/music 2775 root media -"
            ];

            systemd.services."storage-bootstrap" = {
              description = "Bootstrap shared storage directory layout and ownership";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu

                install -d -m 2775 -o root -g media /media
                install -d -m 2775 -o root -g media /media/movies
                install -d -m 2775 -o root -g media /media/shows
                install -d -m 2775 -o root -g media /media/series
                install -d -m 2775 -o root -g media /media/other
                install -d -m 2775 -o root -g media /media/music
              '';
            };

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 ];
          })
      ];
    };
  };
}
