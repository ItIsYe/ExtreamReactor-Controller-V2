# XReactor Controller V2

## Overview
XReactor Controller V2 is a distributed control layer for Extreme Reactors installations built on ComputerCraft computers. It keeps power production safe and reliable by coordinating advisory policies, telemetry, and alarms without ever depending on one computer. The system solves for resilience (no single point of failure) and stability (gradual, informed adjustments) so reactors stay productive even when conditions or connectivity change.

## Installing the controller
Download the installer directly from the `raw.githubusercontent.com` URL (not the GitHub file view) so the file is saved as valid Lua rather than an HTML web page. Do not use `github.com/.../blob/...` links, which serve HTML instead of the Lua installer:

```
wget https://raw.githubusercontent.com/ExtreamX/ExtreamReactor-Controller-V2/main/installer/installer.lua
```

Run the downloaded `installer.lua` from the ComputerCraft computer. If the file is accidentally saved as HTML (for example, by downloading from the GitHub file view instead of `raw.githubusercontent.com`), the installer will stop immediately and explain that it must be fetched from the raw URL.

## Distributed, Autonomous Architecture
Nodes communicate through a lightweight dispatcher that shares telemetry, policy recommendations, and state updates. Each node maintains its own control loop and safety checks so it can keep operating even if other peers are offline. Coordination emerges from shared advisories instead of remote control, keeping decisions near the hardware.

### Why the Master Is Optional
The master role improves fleet-wide visibility and can distribute targets, but all operational logic (alarms, ramping, policy reactions, and safety interlocks) lives on each node. Nodes fall back to their local configuration and the last known policies whenever the master is absent or network links fail, ensuring that power generation and protection continue uninterrupted. Because the master never directly commands reactors or fuel handlers, its loss does not block local operation.

## Control Philosophy
- **Local autonomy first**: Every node is responsible for protecting its attached hardware and maintaining safe operation even if the rest of the network goes silent. Advisory signals help coordinate behavior, but no node waits for permission to act on safety limits.
- **Policies vs. targets vs. alarms**: Policies carry advisory pressure levels that inform nodes about fleet conditions without dictating actions. Targets provide desired operating points when available. Alarms are safety assertions that require immediate local response. Nodes interpret each layer separately to avoid confusing guidance with safety enforcement.
- **Local decision making**: Final adjustments happen on each node, using its own sensors, cached policies, and rate limits. This prevents network latency or master outages from delaying reactions and keeps each reactor, fuel handler, or energy manager accountable for its own safety.
- **Priority-aware behavior**: Nodes consider their configured priority when responding to pressure signals so that lower-priority reactors back off earlier and faster, while higher-priority units hold output longer. This preserves overall capacity without sacrificing the autonomy of any individual node.

## System Architecture
- **Wireless interconnect between computers**: All computers use wireless modems to exchange telemetry and policy updates so coordination works even when nodes are physically separated. Wireless transport keeps communication independent of reactor wiring and removes single points of cabling failure.
- **Wired peripherals for local hardware**: Reactor interfaces, sensors, and other peripherals remain directly wired to their host computer. This keeps hardware control local, reduces latency, and ensures each node can keep operating and protecting its attached equipment without relying on the network.
- **Dispatcher role**: A shared dispatcher abstracts radio messaging, distributing events (telemetry, policy recommendations, alarms) between peers. Nodes publish and subscribe through this channel without assuming a central broker, which keeps the system loosely coupled and fault tolerant.
- **Single receive loop per computer**: Each computer runs one inbound loop that demultiplexes dispatcher messages to its subsystems. This avoids race conditions from multiple listeners, reduces resource usage, and ensures consistent ordering while still allowing all control logic to remain fully local.

## Startup, Recovery, and Failover
- **Node reboot behavior**: When a node restarts, it reloads its local configuration and reconnects to wired peripherals first, then resumes broadcasting telemetry and listening for advisory policies. Cached targets and the last known pressure guidance are reused so attached hardware keeps operating without waiting for fresh network traffic.
- **Master offline**: If the master is unavailable, nodes continue using their own control logic and the most recent policies they received. The absence of the master does not pause ramping, safety checks, or advisory handling; once the master returns, nodes accept updated guidance without needing manual intervention.
- **Network loss**: During connectivity gaps, nodes fall back to local measurements, cached policies, and conservative defaults. They keep applying rate limits and safety rules so reactors and fuel handlers stay stable. When links recover, nodes reconcile new dispatcher events without rewinding local decisions.
- **Persistent state**: Configuration and cached policy state are stored locally so each computer can restart into a safe operating posture. This persistence lets nodes maintain priorities, thresholds, and the latest advisory context across reboots or temporary outages.

## Node Types and Responsibilities
- **Reactor Nodes**: Control individual reactors or turbines with local ramping, rate limits, and priority-aware responses to fuel and energy pressure signals.
- **Energy Nodes**: Monitor energy buffers and generation metrics, emitting advisory energy pressure policies and alarms.
- **Fuel Nodes**: Track fuel availability, reserves, and trends, publishing advisory fuel pressure policies and alarms.
- **Master Node (optional)**: Aggregates fleet telemetry, distributes high-level targets, and coordinates visibility without blocking autonomous operation when unavailable.

## Contributor Guidance
- **Architectural rules to protect**: Keep control loops local to each node, preserve wireless dispatch for inter-node advisories, and maintain one receive loop per computer to prevent race conditions. Never introduce designs that depend on a central coordinator for safety actions.
- **Common pitfalls to avoid**: Do not block decisions on fresh network data or master availability, do not add direct remote control paths that bypass local safeguards, and avoid oscillation-prone feedback by respecting existing rate limits and stabilization windows.
- **Safe extension patterns**: Extend functionality by emitting advisory policies and telemetry rather than remote commands, honor priority-aware behavior when introducing new pressure types, and ensure new features degrade gracefully when offline by relying on cached state and conservative local defaults.

