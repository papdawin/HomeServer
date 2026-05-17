{
  description = "Sonarr NixOS container for Proxmox LXC";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.sonarr = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        (nixpkgs.lib.optional (builtins.pathExists "/etc/nixos/configuration.nix")
          (import "/etc/nixos/configuration.nix"))
        ++ [
          ({ pkgs, ... }:
            let
              sonarrBootstrapUsername = "papdawin";
              sonarrBootstrapUserScript = builtins.readFile ./sonarr-bootstrap-user.sh;
              qbittorrentHost = "192.168.68.26";
              qbittorrentPort = 8080;
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
                  "media"
                ];
                hashedPasswordFile = "/etc/nixos/secrets/papdawin-password-hash";
              };

              services.sonarr = {
                enable = true;
                dataDir = "/appdata";
                user = "sonarr";
                group = "media";
                settings.server = {
                  bindaddress = "*";
                  port = 8989;
                };
              };
              systemd.services.sonarr.serviceConfig.UMask = "0002";

              environment.systemPackages = with pkgs; [ curl jq ];

              systemd.services.sonarr-credentials = {
                description = "Prepare Sonarr bootstrap credentials from shared SOPS secret";
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

                  qbt_username="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["mediaautomation"]["qbittorrent"]["username"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"
                  qbt_password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["mediaautomation"]["qbittorrent"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"
                  password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["sonarr"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"
                  api_key="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["mediaautomation"]["sonarr"]["apiKey"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"

                  cat > /run/sonarr-bootstrap.env <<EOF_INNER
                  SONARR_QBITTORRENT_HOST=${qbittorrentHost}
                  SONARR_QBITTORRENT_PORT=${toString qbittorrentPort}
                  SONARR_QBITTORRENT_USERNAME=$qbt_username
                  SONARR_QBITTORRENT_PASSWORD=$qbt_password
                  SONARR_API_KEY=$api_key
                  SONARR_BOOTSTRAP_USERNAME=${sonarrBootstrapUsername}
                  SONARR_BOOTSTRAP_PASSWORD=$password
                  EOF_INNER
                '';
              };

              systemd.services.sonarr-bootstrap-user = {
                description = "Bootstrap Sonarr startup user";
                wantedBy = [ "multi-user.target" ];
                wants = [ "network-online.target" "sonarr.service" "sonarr-credentials.service" ];
                after = [ "network-online.target" "sonarr.service" "sonarr-credentials.service" ];
                path = with pkgs; [
                  bash
                  coreutils
                  curl
                  jq
                  gnused
                  systemd
                ];
                serviceConfig = {
                  Type = "oneshot";
                };
                script = sonarrBootstrapUserScript;
              };

              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = true;
                  PermitRootLogin = "yes";
                };
              };

              networking.firewall.allowPing = true;
              networking.firewall.allowedTCPPorts = [ 22 8989 ];
            })
        ];
    };
  };
}
