extends Node
## Global signal bus for decoupled presentation/UI events.
##
## Simulation code must not depend on this bus for gameplay correctness: the
## simulation emits its own tick-stamped events (PLAN §3.1, §3.3.3). This bus
## only carries UI- and app-level notifications.

signal settings_changed(section: String, key: String, value: Variant)
signal diagnostics_toggled(visible: bool)
