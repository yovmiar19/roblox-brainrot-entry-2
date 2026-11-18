-- Brainrot Boulevard: server entrypoint.
-- Rojo turns this folder into a Script named "Server" whose children are
-- the sibling modules, so the init requires its child by name.
require(script.GameServer).start()
