{
  description = "Kima Hub NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.kima = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }:
            let
              kimaBootstrapScript = builtins.readFile ./kima-bootstrap.sh;
              lidarrHost = "192.168.68.40";
              lidarrPort = 8686;
              kimaHost = "192.168.68.41";
              kimaPort = 3030;
            in {
              system.stateVersion = "25.11";
              boot.isContainer = true;
              boot.tmp.useTmpfs = false;

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
                  "docker"
                ];
                hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
              };

              virtualisation.docker = {
                enable = true;
                package = pkgs.docker_29;
                autoPrune = {
                  enable = true;
                  dates = "weekly";
                };
              };
              virtualisation.oci-containers.backend = "docker";
              virtualisation.oci-containers.containers.kima = {
                image = "docker.io/chevron7locked/kima:latest";
                ports = [ "${toString kimaPort}:3030" ];
                volumes = [
                  "/appdata/kima:/data"
                  "/media/music:/music"
                ];
                environment = {
                  TZ = "Europe/Budapest";
                  NODE_ENV = "production";
                  MUSIC_PATH = "/music";
                  KIMA_CALLBACK_URL = "http://${kimaHost}:${toString kimaPort}";
                  LIDARR_ENABLED = "true";
                  LIDARR_URL = "http://${lidarrHost}:${toString lidarrPort}";
                  DISABLE_CLAP = "false";
                };
                environmentFiles = [ "/run/kima-lidarr.env" ];
                extraOptions = [
                  "--add-host=host.docker.internal:host-gateway"
                  "--memory=6g"
                  "--memory-swap=8g"
                ];
              };

              systemd.tmpfiles.rules = [
                "d /appdata/kima 0755 root root - -"
                "d /appdata/kima/postgres 0700 101 103 - -"
                "d /appdata/kima/redis 0700 100 102 - -"
                "d /media/music 2775 root media - -"
              ];

              systemd.services.kima-credentials = {
                description = "Prepare Kima Hub integration credentials from shared SOPS secret";
                wantedBy = [ "multi-user.target" ];
                before = [ "docker-kima.service" ];
                requiredBy = [ "docker-kima.service" ];
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

                  read_sops_secret() {
                    local extract="$1"
                    SOPS_AGE_SSH_PRIVATE_KEY_FILE="$sops_private_key" sops -d --extract "$extract" "$sops_secret_file" 2>/dev/null | tr -d '\n' || true
                  }

                  lidarr_api_key="$(read_sops_secret '["services"]["lidarr"]["apiKey"]')"
                  [ -n "$lidarr_api_key" ] || { echo "Missing services.lidarr.apiKey in $sops_secret_file" >&2; exit 1; }

                  cat > /run/kima-lidarr.env <<EOF_INNER
LIDARR_API_KEY=$lidarr_api_key
EOF_INNER
                '';
              };

              systemd.services.kima-bootstrap = {
                description = "Bootstrap Kima Hub Lidarr provider";
                wantedBy = [ "multi-user.target" ];
                wants = [
                  "docker-kima.service"
                  "kima-credentials.service"
                  "network-online.target"
                ];
                after = [
                  "docker-kima.service"
                  "kima-credentials.service"
                  "network-online.target"
                ];
                path = with pkgs; [
                  bash
                  coreutils
                  curl
                  docker_29
                  gnugrep
                  gnused
                  jq
                  systemd
                ];
                environment = {
                  KIMA_BASE_URL = "http://127.0.0.1:${toString kimaPort}";
                  KIMA_CALLBACK_URL = "http://${kimaHost}:${toString kimaPort}";
                  LIDARR_URL = "http://${lidarrHost}:${toString lidarrPort}";
                  MUSIC_PATH = "/music";
                  KIMA_DOWNLOAD_SOURCE = "lidarr";
                };
                serviceConfig = {
                  Type = "oneshot";
                };
                script = kimaBootstrapScript;
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
                iptables -A nixos-fw -p tcp -s 192.168.68.38 --dport ${toString kimaPort} -j nixos-fw-accept
                iptables -A nixos-fw -p tcp -s 192.168.68.40 --dport ${toString kimaPort} -j nixos-fw-accept
              '';

              environment.systemPackages = with pkgs; [
                curl
                docker_29
                jq
              ];
            })
        ];
    };
  };
}
