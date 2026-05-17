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

            services.postgresql.dataDir = "/appdata/postgresql/${config.services.postgresql.package.psqlSchema}";
            services.immich = {
              enable = true;
              host = "0.0.0.0";
              port = 2283;
              mediaLocation = "/appdata/media";
            };
            systemd.services.immich-prepare-appdata = {
              description = "Prepare Immich appdata directories";
              before = [ "immich-server.service" "postgresql.service" ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ coreutils ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu
                pg_schema="${config.services.postgresql.package.psqlSchema}"
                # /appdata is the per-container mount root; keep it traversable so
                # immich/postgres users can reach their owned subdirectories.
                install -d -m 0755 /appdata
                install -d -m 0750 /appdata/media /appdata/postgresql "/appdata/postgresql/$pg_schema"
                chown -R immich:immich /appdata/media || true
                chown -R postgres:postgres /appdata/postgresql || true
              '';
            };
            systemd.services.postgresql.after = [ "immich-prepare-appdata.service" ];
            systemd.services.immich-server.after = [ "immich-prepare-appdata.service" ];
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
