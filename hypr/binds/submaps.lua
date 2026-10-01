-- Submaps (entry bind only — submap body disabled pending API verification)
-- The { submap = "name" } option was silently ignored, causing all binds to be global.
-- Re-enable once correct scoping API is confirmed.

hl.bind("ALT + W", hl.dsp.submap("resize"))
