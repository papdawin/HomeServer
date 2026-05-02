{
  description = "Storage bootstrap NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.storagebootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }:
          let
            doneFile = "/var/lib/storage-bootstrap/bootstrap-media-v1.done";
          in {
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
            users.users.radarr = {
              isSystemUser = true;
              group = "media";
            };
            users.users.sonarr = {
              isSystemUser = true;
              group = "media";
            };
            users.users.prowlarr = {
              isSystemUser = true;
              group = "media";
            };
            users.users.jellyseerr = {
              isSystemUser = true;
              group = "media";
            };

            systemd.services."storage-bootstrap" = {
              description = "Bootstrap shared storage directory layout and ownership";
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ util-linux ];
              unitConfig.ConditionPathExists = "!${doneFile}";
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu

                mountpoint -q /media || {
                  echo "Expected /media to be a mounted Proxmox volume" >&2
                  exit 1
                }

                install -d -m 2775 -o root -g media /media
                install -d -m 2775 -o root -g media /media/movies
                install -d -m 2775 -o root -g media /media/shows
                install -d -m 2775 -o root -g media /media/other
                install -d -m 2775 -o root -g media /media/music
                install -d -m 2775 -o root -g media /media/downloads
                install -d -m 2775 -o root -g media /media/downloads/radarr
                install -d -m 2775 -o root -g media /media/downloads/sonarr
                install -d -m 2775 -o root -g media /media/downloads/other
                install -d -m 2775 -o root -g media /media/downloads/incomplete
                install -d -m 2775 -o root -g media /media/appdata
                install -d -m 2775 -o root -g media /media/appdata/qbittorrent
                install -d -m 2775 -o root -g media /media/appdata/radarr
                install -d -m 2775 -o root -g media /media/appdata/sonarr
                install -d -m 2775 -o root -g media /media/appdata/prowlarr
                install -d -m 2775 -o root -g media /media/appdata/jellyseerr

                install -d -m 0755 -o root -g root "$(dirname "${doneFile}")"
                touch "${doneFile}"
              '';
            };

            # Do not power off this helper from inside NixOS. Terraform applies
            # this flake over SSH, so a boot-time shutdown races the provisioner
            # before it can upload and switch to a fixed generation.
            system.activationScripts.cancelLegacyStorageBootstrapShutdown.text = ''
              ${pkgs.systemd}/bin/shutdown -c 2>/dev/null || true
              ${pkgs.systemd}/bin/systemctl disable storage-bootstrap-shutdown.service 2>/dev/null || true
              ${pkgs.systemd}/bin/systemctl reset-failed storage-bootstrap-shutdown.service 2>/dev/null || true
            '';

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
