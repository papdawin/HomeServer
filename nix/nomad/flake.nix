{
  description = "Nomad Docker-in-LXC NixOS container for Proxmox";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.nomad = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ lib, ... }: {
              system.stateVersion = lib.mkForce "25.11";
              boot.isContainer = true;
              boot.tmp.useTmpfs = false;

              systemd.mounts = [
                {
                  enable = false;
                  where = "/sys/kernel/debug";
                }
              ];

              # Ensure TREK can always write to persistent directories,
              # regardless of the UID baked into upstream images.
              systemd.services.nomad-appdata-permissions = {
                description = "Prepare writable appdata directories for TREK";
                before = [ "docker-nomad.service" ];
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                script = ''
                  install -d -m 0775 /appdata/nomad /appdata/nomad/data /appdata/nomad/uploads
                  chown -R 1000:1000 /appdata/nomad || true
                  chmod -R u+rwX,g+rwX /appdata/nomad || true
                '';
              };

              systemd.services.docker-nomad = {
                wants = [ "nomad-appdata-permissions.service" ];
                after = [ "nomad-appdata-permissions.service" ];
              };

              users.mutableUsers = false;
              users.users.papdawin = {
                isNormalUser = true;
                extraGroups = [ "wheel" ];
                hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
              };

              virtualisation.docker = {
                enable = true;
                autoPrune = {
                  enable = true;
                  dates = "weekly";
                };
                daemon.settings = {
                  "storage-driver" = "vfs";
                  "log-driver" = "json-file";
                  "log-opts" = {
                    "max-size" = "10m";
                    "max-file" = "3";
                  };
                };
              };

              virtualisation.oci-containers.backend = "docker";
              virtualisation.oci-containers.containers.nomad = {
                image = "docker.io/mauriceboe/trek:3.0.15";
                autoStart = true;
                environment = {
                  PORT = "3000";
                  NODE_ENV = "production";
                  TZ = "Europe/Budapest";
                  ADMIN_EMAIL = "papdavid98@gmail.com";
                  ADMIN_PASSWORD = "Admin123";
                  FORCE_HTTPS = "false";
                  COOKIE_SECURE = "false";
                };
                ports = [ "3000:3000" ];
                volumes = [
                  "/appdata/nomad/data:/app/data"
                  "/appdata/nomad/uploads:/app/uploads"
                ];
              };

              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = true;
                  PermitRootLogin = "yes";
                };
              };

              networking.firewall.allowPing = true;
              networking.firewall.allowedTCPPorts = [ 22 3000 ];
            })
        ];
    };
  };
}
