# Paperclip suite

Paperclip is the control plane; each named role runs as an isolated Hermes gateway.

Agents:

- Frank Underwoord — orchestrator/main agent
- Gavin Orsay — ITO and security; read-only Kubernetes access
- Claire Underwood — program, venue, activity, and calendar assistant
- Doug Stamper — chores and housekeeping
- Tom Hammerschmidt — research and technology radar
- Zoé Barnes — email and social handler
- Raymond Tusk — finance, procurement, and resource strategy
- Remy Danton — negotiation and external strategy

The runtime starts all agents with role-specific profiles but does not grant external calendar, email, social, payment, or purchase credentials. Those integrations are intentionally added only after the corresponding approval policy and connector are configured in Paperclip.

The Work iSCSI PVC is shared because it is a single-node RWO filesystem; each process uses a unique directory beneath `/work`. All workloads are pinned to `talos-cp-1`.
