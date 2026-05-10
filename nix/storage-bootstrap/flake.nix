{
  description = "Storage bootstrap NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.storagebootstrap = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
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
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu

                mountpoint -q /media || {
                  echo "Expected /media to be a mounted Proxmox volume" >&2
                  exit 1
                }

                mountpoint -q /appdata || {
                  echo "Expected /appdata to be a mounted Proxmox volume" >&2
                  exit 1
                }

                # Unprivileged LXCs map container uid/gid 0 to host 100000 by
                # default. Set shared bind-mount ownership accordingly so all
                # unprivileged containers can write.
                ensure_dir() {
                  dir="$1"
                  mode="$2"
                  uid="$3"
                  gid="$4"
                  mkdir -p "$dir"
                  chown "$uid:$gid" "$dir"
                  chmod "$mode" "$dir"
                }

                ensure_dir /media 0777 100000 100000
                ensure_dir /media/movies 0777 100000 100000
                ensure_dir /media/shows 0777 100000 100000
                ensure_dir /media/other 0777 100000 100000
                ensure_dir /media/music 0777 100000 100000
                ensure_dir /media/downloads 0777 100000 100000
                ensure_dir /media/downloads/radarr 0777 100000 100000
                ensure_dir /media/downloads/sonarr 0777 100000 100000
                ensure_dir /media/downloads/other 0777 100000 100000
                ensure_dir /media/downloads/incomplete 0777 100000 100000

                ensure_dir /appdata 0777 100000 100000
                ensure_dir /appdata/jellyfin 0777 100000 100000
                ensure_dir /appdata/jellyseerr 0777 100000 100000
                ensure_dir /appdata/prowlarr 0777 100000 100000
                ensure_dir /appdata/qbittorrent 0777 100000 100000
                ensure_dir /appdata/radarr 0777 100000 100000
                ensure_dir /appdata/sonarr 0777 100000 100000
                ensure_dir /appdata/immich 0777 100000 100000
                ensure_dir /appdata/openclaw 0777 100000 100000
                ensure_dir /appdata/nomad 0777 100000 100000
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
