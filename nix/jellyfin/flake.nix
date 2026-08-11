{
  description = "Jellyfin NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.jellyfin = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ lib, pkgs, ... }:
            let
              jellyfinBootstrapUsername = "papdawin";
              jellyfinBootstrapScript = builtins.readFile ./jellyfin-bootstrap-user.sh;
              jellyfinBootstrapLibrariesScript = builtins.readFile ./jellyfin-bootstrap-libraries.sh;
              observabilityHost = "192.168.68.42";
              nodeExporterPort = 9100;
              promtailDir = "/appdata/promtail";
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
            users.groups.media = {
              gid = 2000;
            };
            users.users.papdawin = {
              isNormalUser = true;
              extraGroups = [
                "wheel"
                "jellyfin"
                "media"
              ];
              hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
            };
            users.users.jellyfin.extraGroups = [ "media" ];

            services.jellyfin = {
              enable = true;
              dataDir = "/appdata";
              configDir = "/appdata/config";
              logDir = "/appdata/log";
              cacheDir = "/appdata/cache";
            };
            services.prometheus.exporters.node = {
              enable = true;
              listenAddress = "0.0.0.0";
              port = nodeExporterPort;
              enabledCollectors = [ "systemd" ];
            };

            services.promtail = {
              enable = true;
              configuration = {
                server = {
                  http_listen_address = "0.0.0.0";
                  http_listen_port = 9080;
                  grpc_listen_port = 0;
                };
                positions.filename = "${promtailDir}/positions.yaml";
                clients = [ { url = "http://${observabilityHost}:3100/loki/api/v1/push"; } ];
                scrape_configs = [
                  {
                    job_name = "jellyfin-journal";
                    journal = {
                      max_age = "12h";
                      labels = {
                        job = "jellyfin-journal";
                        source_container = "jellyfin";
                        service = "jellyfin";
                        service_name = "jellyfin";
                        signal_type = "log";
                        log_source = "journal";
                      };
                    };
                    relabel_configs = [
                      {
                        source_labels = [ "__journal__systemd_unit" ];
                        target_label = "unit";
                      }
                      {
                        source_labels = [ "__journal__hostname" ];
                        target_label = "hostname";
                      }
                    ];
                  }
                  {
                    job_name = "jellyfin-file-logs";
                    static_configs = [
                      {
                        targets = [ "localhost" ];
                        labels = {
                          job = "jellyfin-file-logs";
                          source_container = "jellyfin";
                          service = "jellyfin";
                          service_name = "jellyfin";
                          signal_type = "log";
                          log_source = "file";
                          __path__ = "/appdata/log/*.log";
                        };
                      }
                    ];
                  }
                ];
              };
            };

            environment.systemPackages = with pkgs; [ curl ];

            systemd.services.jellyfin-credentials = {
              description = "Prepare Jellyfin bootstrap credentials from shared SOPS secret";
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

                password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["jellyfin"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"

                cat > /run/jellyfin-bootstrap.env <<EOF
                JELLYFIN_BOOTSTRAP_USERNAME=${jellyfinBootstrapUsername}
                JELLYFIN_BOOTSTRAP_PASSWORD=$password
                EOF
              '';
            };

            systemd.services.jellyfin-bootstrap = {
              description = "Bootstrap Jellyfin startup user";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" "jellyfin.service" "jellyfin-credentials.service" ];
              after = [ "network-online.target" "jellyfin.service" "jellyfin-credentials.service" ];
              path = with pkgs; [
                bash
                coreutils
                curl
                gawk
                gnugrep
                gnused
                systemd
              ];
              serviceConfig = {
                Type = "oneshot";
                Restart = "on-failure";
                RestartSec = "15s";
              };
              script = jellyfinBootstrapScript;
            };

            systemd.services.jellyfin-bootstrap-libraries = {
              description = "Bootstrap Jellyfin media libraries";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" "jellyfin.service" "jellyfin-credentials.service" "jellyfin-bootstrap.service" ];
              after = [ "network-online.target" "jellyfin.service" "jellyfin-credentials.service" "jellyfin-bootstrap.service" ];
              path = with pkgs; [
                bash
                coreutils
                curl
                jq
                gnugrep
                gnused
                systemd
              ];
              serviceConfig = {
                Type = "oneshot";
                Restart = "on-failure";
                RestartSec = "15s";
              };
              script = jellyfinBootstrapLibrariesScript;
            };

            systemd.services.jellyfin-enable-metrics = {
              description = "Enable Jellyfin Prometheus metrics endpoint";
              wantedBy = [ "multi-user.target" ];
              after = [ "jellyfin.service" ];
              wants = [ "jellyfin.service" ];
              path = with pkgs; [
                coreutils
                gnugrep
                gnused
                systemd
              ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu

                config_file="/appdata/config/system.xml"
                for _ in $(seq 1 30); do
                  [ -f "$config_file" ] && break
                  sleep 2
                done

                [ -f "$config_file" ]

                if grep -q "<EnableMetrics>" "$config_file"; then
                  if grep -q "<EnableMetrics>true</EnableMetrics>" "$config_file"; then
                    exit 0
                  fi
                  sed -i 's#<EnableMetrics>.*</EnableMetrics>#<EnableMetrics>true</EnableMetrics>#' "$config_file"
                else
                  sed -i 's#</ServerConfiguration>#  <EnableMetrics>true</EnableMetrics>\n</ServerConfiguration>#' "$config_file"
                fi

                systemctl try-restart jellyfin.service
              '';
            };

            systemd.services.jellyfin = {
              wants = [ "promtail-prepare.service" ];
              after = [ "promtail-prepare.service" ];
              serviceConfig.Restart = lib.mkForce "on-failure";
            };

            systemd.services.promtail-prepare = {
              description = "Prepare Promtail state directory";
              wantedBy = [ "multi-user.target" ];
              before = [ "promtail.service" ];
              path = with pkgs; [ coreutils ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu
                install -d -m 0750 -o promtail -g promtail ${promtailDir}
              '';
            };

            systemd.services.promtail = {
              wants = [ "promtail-prepare.service" ];
              after = [ "promtail-prepare.service" ];
              serviceConfig.Restart = lib.mkForce "on-failure";
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
              iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport 8096 -j nixos-fw-accept
              iptables -A nixos-fw -p tcp -s 192.168.68.32 --dport 8096 -j nixos-fw-accept
              iptables -A nixos-fw -p tcp -s ${observabilityHost} --dport 8096 -j nixos-fw-accept
              iptables -A nixos-fw -p tcp -s ${observabilityHost} --dport ${toString nodeExporterPort} -j nixos-fw-accept
            '';
          })
        ];
    };
  };
}
