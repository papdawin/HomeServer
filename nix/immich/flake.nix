{
  description = "Immich NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.immich = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ config, pkgs, ... }: {
            system.stateVersion = "25.11";
            boot.isContainer = true;

            systemd.mounts = [
              {
                enable = false;
                where = "/sys/kernel/debug";
              }
            ];

            services.postgresql.dataDir = "/appdata/immich/postgresql/${config.services.postgresql.package.psqlSchema}";
            services.immich = {
              enable = true;
              host = "0.0.0.0";
              port = 2283;
              mediaLocation = "/appdata/immich/media";
            };
            systemd.services.immich-migrate-appdata = {
              description = "Migrate legacy Immich state from rootfs to /appdata";
              before = [ "immich-server.service" "postgresql.service" ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ coreutils findutils ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              script = ''
                set -eu

                legacy_media_dir="/var/lib/immich"
                target_media_dir="/appdata/immich/media"
                pg_schema="${config.services.postgresql.package.psqlSchema}"
                legacy_pg_root="/var/lib/postgresql/$pg_schema"
                target_pg_root="/appdata/immich/postgresql/$pg_schema"

                mkdir -p "$target_media_dir" "$target_pg_root"

                if [ -d "$legacy_media_dir" ] && [ -z "$(find "$target_media_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
                  cp -a "$legacy_media_dir/." "$target_media_dir/"
                fi

                if [ -d "$legacy_pg_root" ] && [ -z "$(find "$target_pg_root" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
                  cp -a "$legacy_pg_root/." "$target_pg_root/"
                fi

                chown -R immich:immich "$target_media_dir" || true
                chown -R postgres:postgres "$target_pg_root" || true
                echo "immich-migrate-appdata: migration step completed"
              '';
            };
            systemd.services.postgresql.after = [ "immich-migrate-appdata.service" ];
            systemd.services.immich-server.after = [ "immich-migrate-appdata.service" ];

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 2283 ];
          })
        ];
    };
  };
}
