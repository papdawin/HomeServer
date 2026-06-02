{
  description = "Gotify NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.gotify = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ lib, pkgs, ... }: {
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
                "media"
              ];
              hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
            };
            users.users.gotify = {
              isSystemUser = true;
              group = "media";
              home = "/appdata";
            };

            services.gotify = {
              enable = true;
              environment = {
                GOTIFY_SERVER_PORT = 8080;
                GOTIFY_SERVER_LISTENADDR = "0.0.0.0";
                GOTIFY_DATABASE_DIALECT = "sqlite3";
                GOTIFY_DATABASE_CONNECTION = "data/gotify.db";
                GOTIFY_UPLOADEDIMAGESDIR = "data/images";
                GOTIFY_PLUGINSDIR = "data/plugins";
                GOTIFY_REGISTRATION = "false";
              };
              environmentFiles = [ "/run/gotify-bootstrap.env" ];
            };

            systemd.services.gotify-prepare-appdata = {
              description = "Prepare Gotify appdata directories";
              before = [ "gotify-server.service" ];
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [ coreutils ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu
                install -d -m 0750 -o gotify -g media /appdata
                install -d -m 0750 -o gotify -g media /appdata/data
                install -d -m 0750 -o gotify -g media /appdata/data/images
                install -d -m 0750 -o gotify -g media /appdata/data/plugins
              '';
            };

            systemd.services.gotify-credentials = {
              description = "Prepare Gotify default user credentials from shared SOPS secret";
              wantedBy = [ "multi-user.target" ];
              path = with pkgs; [
                coreutils
                sops
              ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu
                umask 077

                sops_secret_file="/etc/nixos/secrets/common.sops.yaml"
                sops_private_key="/etc/nixos/secrets/bootstrap-ssh-private-key"

                password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE="$sops_private_key" sops -d --extract '["services"]["gotify"]["password"]' "$sops_secret_file" 2>/dev/null | tr -d '\n' || true)"
                [ -n "$password" ] || { echo "Missing services.gotify.password in $sops_secret_file" >&2; exit 1; }

                cat > /run/gotify-bootstrap.env <<EOF
                GOTIFY_DEFAULTUSER_NAME=papdawin
                GOTIFY_DEFAULTUSER_PASS=$password
                EOF
              '';
            };

            systemd.services.gotify-server = {
              wants = [ "gotify-prepare-appdata.service" "gotify-credentials.service" ];
              after = [ "gotify-prepare-appdata.service" "gotify-credentials.service" ];
              serviceConfig = {
                DynamicUser = lib.mkForce false;
                User = "gotify";
                Group = "media";
                StateDirectory = lib.mkForce "";
                WorkingDirectory = lib.mkForce "/appdata";
                UMask = "0002";
              };
              environment.HOME = lib.mkForce "/appdata";
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
            networking.firewall.extraCommands = ''
              iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport 8080 -j nixos-fw-accept
            '';
          })
        ];
    };
  };
}
