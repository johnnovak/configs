_, _, _, _, mode, res, val = reaper.get_action_context()
cmdlist = reaper.GetExtState("reaticulate", "command")
cmd = string.format(' activate_relative_articulation=0,4,%d,%d,%d', mode, res, val)
reaper.SetExtState("reaticulate", "command", (cmdlist or '') .. cmd, false)