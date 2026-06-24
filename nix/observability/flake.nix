{
  description = "Observability NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.observability = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, lib, ... }:
            let
              observabilityRoot = "/var/lib/observability";
              grafanaDir = "${observabilityRoot}/grafana";
              lokiDir = "${observabilityRoot}/loki";
              promtailDir = "${observabilityRoot}/promtail";
              grafanaPasswordFile = "${grafanaDir}/admin-password";
              lokiConfig = pkgs.writeText "loki-observability-config.yaml" ''
                auth_enabled: false

                server:
                  http_listen_address: 127.0.0.1
                  http_listen_port: 3100
                  grpc_listen_port: 9096
                  log_level: info

                common:
                  instance_addr: 127.0.0.1
                  path_prefix: ${lokiDir}
                  storage:
                    filesystem:
                      chunks_directory: ${lokiDir}/chunks
                      rules_directory: ${lokiDir}/rules
                  replication_factor: 1
                  ring:
                    kvstore:
                      store: inmemory

                schema_config:
                  configs:
                    - from: 2020-10-24
                      store: tsdb
                      object_store: filesystem
                      schema: v13
                      index:
                        prefix: index_
                        period: 24h

                ruler:
                  storage:
                    type: local
                    local:
                      directory: ${lokiDir}/rules

                analytics:
                  reporting_enabled: false
              '';
              observabilityHealthcheck = pkgs.writeShellScriptBin "observability-healthcheck" ''
                set -euo pipefail

                curl --fail --silent --show-error http://127.0.0.1:3000/api/health >/dev/null
                curl --fail --silent --show-error http://127.0.0.1:9090/-/healthy >/dev/null
                curl --fail --silent --show-error http://127.0.0.1:3100/ready >/dev/null
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

              services.grafana = {
                enable = true;
                dataDir = grafanaDir;
                settings = {
                  server = {
                    http_addr = "0.0.0.0";
                    http_port = 3000;
                    domain = "observability.home.papdavid.eu";
                    root_url = "https://observability.home.papdavid.eu/";
                  };
                  security = {
                    admin_user = "papdawin";
                    admin_password = "$__file{${grafanaPasswordFile}}";
                  };
                  users = {
                    allow_sign_up = false;
                  };
                };
                provision = {
                  enable = true;
                  datasources.settings = {
                    apiVersion = 1;
                    datasources = [
                      {
                        name = "Prometheus";
                        type = "prometheus";
                        uid = "prometheus";
                        access = "proxy";
                        url = "http://127.0.0.1:9090";
                        isDefault = true;
                        editable = false;
                      }
                      {
                        name = "Loki";
                        type = "loki";
                        uid = "loki";
                        access = "proxy";
                        url = "http://127.0.0.1:3100";
                        editable = false;
                      }
                    ];
                  };
                };
              };

              services.prometheus = {
                enable = true;
                listenAddress = "127.0.0.1";
                port = 9090;
                stateDir = "observability/prometheus";
                globalConfig = {
                  scrape_interval = "15s";
                  evaluation_interval = "15s";
                };
                scrapeConfigs = [
                  {
                    job_name = "prometheus";
                    static_configs = [
                      {
                        targets = [ "127.0.0.1:9090" ];
                        labels = {
                          instance = "observability";
                        };
                      }
                    ];
                  }
                ];
              };

              services.loki = {
                enable = true;
                dataDir = lokiDir;
                configFile = lokiConfig;
              };

              services.promtail = {
                enable = true;
                configuration = {
                  server = {
                    http_listen_address = "127.0.0.1";
                    http_listen_port = 9080;
                    grpc_listen_port = 0;
                  };
                  positions.filename = "${promtailDir}/positions.yaml";
                  clients = [ { url = "http://127.0.0.1:3100/loki/api/v1/push"; } ];
                  scrape_configs = [
                    {
                      job_name = "systemd-journal";
                      journal = {
                        max_age = "12h";
                        labels = {
                          job = "systemd-journal";
                          host = "observability";
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
                  ];
                };
              };

              systemd.services.observability-prepare-data = {
                description = "Prepare persistent observability data directories";
                before = [
                  "grafana-credentials.service"
                  "grafana.service"
                  "loki.service"
                  "prometheus.service"
                  "promtail.service"
                ];
                wantedBy = [ "multi-user.target" ];
                path = with pkgs; [ coreutils ];
                serviceConfig = {
                  Type = "oneshot";
                };
                script = ''
                  set -eu

                  install -d -m 0755 ${observabilityRoot}
                  install -d -m 0750 -o grafana -g grafana ${grafanaDir}
                  install -d -m 0750 -o prometheus -g prometheus ${observabilityRoot}/prometheus
                  install -d -m 0750 -o loki -g loki ${lokiDir}
                  install -d -m 0750 -o loki -g loki ${lokiDir}/chunks
                  install -d -m 0750 -o loki -g loki ${lokiDir}/rules
                  install -d -m 0750 -o promtail -g promtail ${promtailDir}
                '';
              };

              systemd.services.grafana-credentials = {
                description = "Generate persistent Grafana admin credentials";
                before = [ "grafana.service" ];
                wants = [ "observability-prepare-data.service" ];
                after = [ "observability-prepare-data.service" ];
                wantedBy = [ "multi-user.target" ];
                path = with pkgs; [
                  coreutils
                  openssl
                ];
                serviceConfig = {
                  Type = "oneshot";
                };
                script = ''
                  set -eu
                  umask 077

                  if [ ! -s ${grafanaPasswordFile} ]; then
                    openssl rand -base64 24 > ${grafanaPasswordFile}
                    chown grafana:grafana ${grafanaPasswordFile}
                    chmod 0600 ${grafanaPasswordFile}
                  fi
                '';
              };

              systemd.services.grafana = {
                wants = [ "grafana-credentials.service" ];
                after = [ "grafana-credentials.service" ];
                serviceConfig.Restart = lib.mkForce "on-failure";
              };

              systemd.services.prometheus = {
                wants = [ "observability-prepare-data.service" ];
                after = [ "observability-prepare-data.service" ];
                serviceConfig.Restart = lib.mkForce "on-failure";
              };

              systemd.services.loki = {
                wants = [ "observability-prepare-data.service" ];
                after = [ "observability-prepare-data.service" ];
                serviceConfig.Restart = lib.mkForce "on-failure";
              };

              systemd.services.promtail = {
                wants = [ "observability-prepare-data.service" "loki.service" ];
                after = [ "observability-prepare-data.service" "loki.service" ];
                serviceConfig.Restart = lib.mkForce "on-failure";
              };

              systemd.services.observability-healthcheck = {
                description = "Validate Grafana, Prometheus, and Loki readiness";
                after = [
                  "grafana.service"
                  "prometheus.service"
                  "loki.service"
                ];
                path = with pkgs; [
                  coreutils
                  curl
                  observabilityHealthcheck
                ];
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = "${observabilityHealthcheck}/bin/observability-healthcheck";
                };
              };

              environment.systemPackages = with pkgs; [
                curl
                jq
                observabilityHealthcheck
              ];

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
                iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport 3000 -j nixos-fw-accept
              '';
            })
        ];
    };
  };
}
