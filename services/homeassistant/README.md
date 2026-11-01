# Home Assistant

Home Assistant is exposed at `https://homeassistant.home.papdavid.eu`.

The configuration is persisted in the `homeassistant-config` PVC using the
`application-state-nfs` StorageClass. Authentication is handled by Home
Assistant itself; the Ingress intentionally does not add Authentik ForwardAuth
so the Home Assistant mobile app can use the endpoint.
