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

              systemd.tmpfiles.rules = [
                "d /var/lib/nomad 0755 root root - -"
                "d /appdata 0755 root root - -"
                "d /appdata/nomad 0755 root root - -"
                "d /appdata/nomad/data 0755 root root - -"
                "d /appdata/nomad/uploads 0755 root root - -"
              ];

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
                image = "docker.io/mauriceboe/trek:latest";
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
