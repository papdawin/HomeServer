{
  description = "Traefik NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.traefik = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ lib, pkgs, ... }:
            let
              proxiedServices = {
                adguardhome = {
                  host = "adguardhome";
                  url = "http://192.168.68.39:3000";
                };
                bazarr = {
                  host = "bazarr";
                  url = "http://192.168.68.35:6767";
                };
                gotify = {
                  host = "gotify";
                  url = "http://192.168.68.37:8080";
                };
                hermes = {
                  host = "hermes";
                  url = "http://192.168.68.27:8787";
                };
                immich = {
                  host = "immich";
                  url = "http://192.168.68.28:2283";
                };
                jellyfin = {
                  host = "jellyfin";
                  url = "http://192.168.68.25:8096";
                };
                jellyseerr = {
                  host = "jellyseerr";
                  url = "http://192.168.68.32:5055";
                };
                kima = {
                  host = "kima";
                  url = "http://192.168.68.41:3030";
                };
                lidarr = {
                  host = "lidarr";
                  url = "http://192.168.68.40:8686";
                };
                mealie = {
                  host = "mealie";
                  url = "http://192.168.68.36:80";
                };
                nextcloud = {
                  host = "nextcloud";
                  url = "http://192.168.68.34:80";
                };
                nomad = {
                  host = "nomad";
                  url = "http://192.168.68.33:3000";
                };
                observability = {
                  host = "observability";
                  url = "http://192.168.68.42:3000";
                };
                prowlarr = {
                  host = "prowlarr";
                  url = "http://192.168.68.31:9696";
                };
                qbittorrent = {
                  host = "qbittorrent";
                  url = "http://192.168.68.26:8080";
                };
                radarr = {
                  host = "radarr";
                  url = "http://192.168.68.29:7878";
                };
                sonarr = {
                  host = "sonarr";
                  url = "http://192.168.68.30:8989";
                };
              };
              mkRouter = name: service: {
                rule = "Host(`${service.host}.home.papdavid.eu`)";
                entryPoints = [ "websecure" ];
                service = name;
                tls = { };
              };
              mkService = service: {
                loadBalancer = {
                  passHostHeader = true;
                  servers = [
                    {
                      url = service.url;
                    }
                  ];
                };
              };
              issueHomeCertificate = pkgs.writeShellScriptBin "issue-home-certificate" ''
                set -euo pipefail

                email="''${LETSENCRYPT_EMAIL:-''${1:-}}"
                if [ -z "$email" ]; then
                  echo "Usage: LETSENCRYPT_EMAIL=you@example.com issue-home-certificate" >&2
                  echo "   or: issue-home-certificate you@example.com" >&2
                  exit 1
                fi

                cert_name="home.papdavid.eu"
                cert_dir="/var/lib/traefik/certs"

                certbot certonly \
                  --manual \
                  --preferred-challenges dns \
                  --cert-name "$cert_name" \
                  --agree-tos \
                  --no-eff-email \
                  --email "$email" \
                  -d "*.home.papdavid.eu" \
                  -d "home.papdavid.eu"

                install -d -m 0750 -o traefik -g traefik "$cert_dir"
                cp "/etc/letsencrypt/live/$cert_name/fullchain.pem" "$cert_dir/home.papdavid.eu.pem"
                cp "/etc/letsencrypt/live/$cert_name/privkey.pem" "$cert_dir/home.papdavid.eu-key.pem"
                chown traefik:traefik "$cert_dir/home.papdavid.eu.pem" "$cert_dir/home.papdavid.eu-key.pem"
                chmod 0640 "$cert_dir/home.papdavid.eu.pem"
                chmod 0600 "$cert_dir/home.papdavid.eu-key.pem"

                systemctl reload-or-restart traefik.service
                openssl x509 -noout -subject -issuer -dates -in "$cert_dir/home.papdavid.eu.pem"
              '';
            in {
            system.stateVersion = "25.11";
            boot.isContainer = true;

            systemd.mounts = [
              {
                enable = false;
                where = "/sys/kernel/debug";
              }
            ];

            users.mutableUsers = false;
            users.users.papdawin = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
            };

            services.traefik = {
              enable = true;
              dataDir = "/var/lib/traefik";
              staticConfigOptions = {
                log.level = "INFO";
                entryPoints.websecure.address = ":443";
              };
              dynamicConfigOptions = {
                http = {
                  routers = lib.mapAttrs mkRouter proxiedServices;
                  services = lib.mapAttrs (_: mkService) proxiedServices;
                };
                tls = {
                  certificates = [
                    {
                      certFile = "/var/lib/traefik/certs/home.papdavid.eu.pem";
                      keyFile = "/var/lib/traefik/certs/home.papdavid.eu-key.pem";
                    }
                  ];
                  stores.default.defaultCertificate = {
                    certFile = "/var/lib/traefik/certs/home.papdavid.eu.pem";
                    keyFile = "/var/lib/traefik/certs/home.papdavid.eu-key.pem";
                  };
                };
              };
            };

            systemd.services.traefik-placeholder-certificate = {
              description = "Generate temporary placeholder certificate until Let's Encrypt cert is installed";
              wantedBy = [ "multi-user.target" ];
              requiredBy = [ "traefik.service" ];
              before = [ "traefik.service" ];
              path = with pkgs; [
                coreutils
                openssl
              ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu

                cert_dir=/var/lib/traefik/certs
                install -d -m 0750 -o traefik -g traefik "$cert_dir"

                cert_key="$cert_dir/home.papdavid.eu-key.pem"
                cert="$cert_dir/home.papdavid.eu.pem"

                if [ ! -f "$cert_key" ] || [ ! -f "$cert" ]; then
                  openssl req -x509 -newkey rsa:4096 -nodes -sha256 -days 7 \
                    -keyout "$cert_key" \
                    -out "$cert" \
                    -subj "/CN=temporary.home.papdavid.eu" \
                    -addext "subjectAltName=DNS:home.papdavid.eu,DNS:*.home.papdavid.eu,DNS:jellyfin.home.papdavid.eu"
                fi

                chown traefik:traefik "$cert" "$cert_key"
                chmod 0640 "$cert_dir"/*.pem
                chmod 0600 "$cert_key"
              '';
            };

            environment.systemPackages = with pkgs; [
              certbot
              curl
              issueHomeCertificate
              openssl
            ];

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };

            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 443 ];
          })
        ];
    };
  };
}
