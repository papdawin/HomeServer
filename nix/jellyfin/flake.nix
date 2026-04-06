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
          ({ pkgs, ... }: {
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

            systemd.tmpfiles.rules = [
              "d /media 2775 root media -"
              "d /media/movies 2775 root media -"
              "d /media/shows 2775 root media -"
              "d /media/series 2775 root media -"
              "d /media/other 2775 root media -"
              "d /media/music 2775 root media -"
              "z /var/lib/jellyfin 0750 jellyfin jellyfin -"
              "z /var/lib/jellyfin/config 0750 jellyfin jellyfin -"
              "z /var/lib/jellyfin/log 0750 jellyfin jellyfin -"
              "z /var/cache/jellyfin 0750 jellyfin jellyfin -"
            ];

            services.jellyfin.enable = true;

            systemd.services.jellyfin-bootstrap = {
              description = "Bootstrap Jellyfin user from shared SOPS secret";
              after = [ "jellyfin.service" ];
              wants = [ "jellyfin.service" ];
              path = with pkgs; [
                curl
                jq
                sops
              ];
              serviceConfig = {
                Type = "oneshot";
              };
              script = ''
                set -eu

                base_url="http://127.0.0.1:8096"
                username="papdawin"
                auth_header='X-Emby-Authorization: MediaBrowser Client="nixos-bootstrap", Device="nixos", DeviceId="nixos-bootstrap", Version="1.0.0"'
                password="$(SOPS_AGE_SSH_PRIVATE_KEY_FILE=/etc/nixos/secrets/bootstrap-ssh-private-key sops -d --extract '["services"]["jellyfin"]["password"]' /etc/nixos/secrets/common.sops.yaml | tr -d '\n')"

                auth_ok() {
                  payload_pw="$(jq -cn --arg u "$username" --arg p "$password" '{Username: $u, Pw: $p}')"
                  token="$(curl -fsS -X POST -H "Content-Type: application/json" -H "$auth_header" --data "$payload_pw" "$base_url/Users/AuthenticateByName" 2>/dev/null | jq -r '.AccessToken // empty' || true)"
                  [ -n "$token" ] && [ "$token" != "null" ] && return 0

                  payload_password="$(jq -cn --arg u "$username" --arg p "$password" '{Username: $u, Password: $p}')"
                  token="$(curl -fsS -X POST -H "Content-Type: application/json" -H "$auth_header" --data "$payload_password" "$base_url/Users/AuthenticateByName" 2>/dev/null | jq -r '.AccessToken // empty' || true)"
                  [ -n "$token" ] && [ "$token" != "null" ]
                }

                i=0
                until curl -fsS "$base_url/System/Ping" >/dev/null 2>&1; do
                  i="$((i + 1))"
                  if [ "$i" -ge 120 ]; then
                    echo "Warning: Jellyfin did not become ready in time; skipping bootstrap" >&2
                    exit 0
                  fi
                  sleep 2
                done

                if auth_ok; then
                  systemctl stop jellyfin-bootstrap.timer >/dev/null 2>&1 || true
                  exit 0
                fi

                users_count="$(curl -fsS "$base_url/Users/Public" | jq 'length' 2>/dev/null || echo 0)"
                if [ "$users_count" -gt 0 ]; then
                  echo "Warning: Jellyfin has users but $username/$password does not authenticate; leaving existing users unchanged" >&2
                  systemctl stop jellyfin-bootstrap.timer >/dev/null 2>&1 || true
                  exit 0
                fi

                i=0
                while [ "$i" -lt 30 ]; do
                  payload="$(jq -cn --arg Name "$username" --arg Password "$password" '{Name: $Name, Password: $Password}')"
                  status_user="$(curl -sS -o /tmp/jellyfin-startup-user.out -w '%{http_code}' -X POST -H "Content-Type: application/json" -H "$auth_header" --data "$payload" "$base_url/Startup/User" || true)"
                  case "$status_user" in
                    200|204|400) ;;
                    *)
                      echo "Startup/User failed with HTTP $status_user" >&2
                      ;;
                  esac

                  status_complete="$(curl -sS -o /tmp/jellyfin-startup-complete.out -w '%{http_code}' -X POST -H "$auth_header" "$base_url/Startup/Complete" || true)"
                  case "$status_complete" in
                    200|204|400) ;;
                    *)
                      echo "Startup/Complete failed with HTTP $status_complete" >&2
                      ;;
                  esac

                  if auth_ok; then
                    systemctl stop jellyfin-bootstrap.timer >/dev/null 2>&1 || true
                    exit 0
                  fi
                  i="$((i + 1))"
                  sleep 2
                done

                users_count="$(curl -fsS "$base_url/Users/Public" | jq 'length' 2>/dev/null || echo 0)"
                if [ "$users_count" -eq 0 ]; then
                  echo "No Jellyfin users found; attempting startup wizard recovery" >&2
                  systemctl stop jellyfin.service >/dev/null 2>&1 || true
                  for xml in /var/lib/jellyfin/config/system.xml /etc/jellyfin/system.xml; do
                    [ -f "$xml" ] || continue
                    sed -i \
                      -e 's#<IsStartupWizardCompleted>true</IsStartupWizardCompleted>#<IsStartupWizardCompleted>false</IsStartupWizardCompleted>#g' \
                      -e 's#<IsStartupWizardComplete>true</IsStartupWizardComplete>#<IsStartupWizardComplete>false</IsStartupWizardComplete>#g' \
                      "$xml" || true
                  done
                  systemctl start jellyfin.service >/dev/null 2>&1 || true

                  i=0
                  until curl -fsS "$base_url/System/Ping" >/dev/null 2>&1; do
                    i="$((i + 1))"
                    [ "$i" -ge 60 ] && break
                    sleep 2
                  done

                  i=0
                  while [ "$i" -lt 15 ]; do
                    payload="$(jq -cn --arg Name "$username" --arg Password "$password" '{Name: $Name, Password: $Password}')"
                    curl -sS -X POST -H "Content-Type: application/json" -H "$auth_header" --data "$payload" "$base_url/Startup/User" >/dev/null || true
                    curl -sS -X POST -H "$auth_header" "$base_url/Startup/Complete" >/dev/null || true
                    if auth_ok; then
                      systemctl stop jellyfin-bootstrap.timer >/dev/null 2>&1 || true
                      exit 0
                    fi
                    i="$((i + 1))"
                    sleep 2
                  done
                fi

                echo "Warning: Failed to create/authenticate Jellyfin user $username; manual intervention required" >&2
                curl -fsS "$base_url/Users/Public" >&2 || true
                systemctl stop jellyfin-bootstrap.timer >/dev/null 2>&1 || true
                exit 0
              '';
            };

            systemd.timers.jellyfin-bootstrap = {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnActiveSec = "2m";
                OnUnitActiveSec = "2m";
                Persistent = true;
                Unit = "jellyfin-bootstrap.service";
              };
            };

            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "yes";
              };
            };
            networking.firewall.allowPing = true;
            networking.firewall.allowedTCPPorts = [ 22 8096 ];
          })
        ];
    };
  };
}
