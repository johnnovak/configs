-- enable debug mode

_AUTO_RELOAD_DEBUG = function()
  renoise.app():show_status('Tweaks reloaded... ' .. os.clock())
end

------------------------------------------------------------------------------
-- WORKSPACES
------------------------------------------------------------------------------

-- NOTES:
--   - should not be used together with View Presets (results in very
--     confusing and erratic operation)
--   - Sampler state is not preserved when changing tabs in the detached
--     Instrument Editor


-- shortcuts
local _window = renoise.app().window
local AppWindow = renoise.ApplicationWindow

------------------------------------------------------------------------------
-- globals

local PATTERN_WORKSPACE = 0
local MIXER_WORKSPACE   = 1
local SAMPLER_WORKSPACE = 2

local CYCLE_UPPER_FRAME     = 0
local CYCLE_LOWER_FRAME     = 1
local TOGGLE_UPPER_FRAME    = 2
local TOGGLE_LOWER_FRAME    = 3
local TOGGLE_BOTH_FRAMES    = 4
local TOGGLE_PATTERN_MATRIX = 5
local TOGGLE_DISK_BROWSER   = 6

local _active_workspace_index = 0

local view_workspace_map = {
  [AppWindow.MIDDLE_FRAME_PATTERN_EDITOR] = PATTERN_WORKSPACE,

  [AppWindow.MIDDLE_FRAME_MIXER] = MIXER_WORKSPACE,

  [AppWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_OVERVIEW]   = SAMPLER_WORKSPACE,
  [AppWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR]     = SAMPLER_WORKSPACE,
  [AppWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_KEYZONES]   = SAMPLER_WORKSPACE,
  [AppWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_MODULATION] = SAMPLER_WORKSPACE,
  [AppWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EFFECTS]    = SAMPLER_WORKSPACE,
  [AppWindow.MIDDLE_FRAME_INSTRUMENT_PLUGIN_EDITOR]     = SAMPLER_WORKSPACE,
  [AppWindow.MIDDLE_FRAME_INSTRUMENT_MIDI_EDITOR]       = SAMPLER_WORKSPACE
}

local workspace_states = {
  [PATTERN_WORKSPACE] = {
    middle_frame            = AppWindow.MIDDLE_FRAME_PATTERN_EDITOR,
    upper_frame             = AppWindow.UPPER_FRAME_TRACK_SCOPES,
    upper_frame_visible     = true,
    lower_frame             = AppWindow.LOWER_FRAME_TRACK_DSPS,
    lower_frame_visible     = true,
    pattern_matrix_visible  = false,
    --instrument_box_visible  = true,
    disk_browser_visible    = false
  },
  [MIXER_WORKSPACE] = {
    middle_frame            = AppWindow.MIDDLE_FRAME_MIXER,
    upper_frame             = AppWindow.UPPER_FRAME_MASTER_SPECTRUM,
    upper_frame_visible     = true,
    lower_frame             = AppWindow.LOWER_FRAME_TRACK_DSPS,
    lower_frame_visible     = true,
    pattern_matrix_visible  = false,
    --instrument_box_visible  = true,
    disk_browser_visible    = false
  },
  [SAMPLER_WORKSPACE] = {
    middle_frame            = AppWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_OVERVIEW,
    upper_frame             = AppWindow.UPPER_FRAME_TRACK_SCOPES,
    upper_frame_visible     = true,
    lower_frame             = AppWindow.LOWER_FRAME_TRACK_DSPS,
    lower_frame_visible     = true,
    pattern_matrix_visible  = false,
    --instrument_box_visible  = true,
    disk_browser_visible    = false
  }
}

------------------------------------------------------------------------------
-- options

local options = renoise.Document.create("WorkspacePreferencesxyz") {
  restore_upper_frame_state = true,
  restore_lower_frame_state = true,
  restore_pattern_matrix_state = true,
  --restore_instruments_box_state = true,
  restore_disk_browser_state = true,

  pattern_workspace_action = CYCLE_UPPER_FRAME,
  mixer_workspace_action = TOGGLE_UPPER_FRAME,
  sampler_workspace_action = TOGGLE_DISK_BROWSER
}

renoise.tool().preferences = options

------------------------------------------------------------------------------
-- observers

_window.active_middle_frame_observable:add_notifier(

  function()
    -- get the workspace table corresponding to the active renoise view
    _active_workspace_index = view_workspace_map[_window.active_middle_frame]

    local ws = workspace_states[_active_workspace_index]

    -- store middle frame state - this is needed for the 'sampler' workspace
    -- to restore which sampler workspace tab (sampler/plugin/midi) was
    -- last activated, and in the the case of the 'sampler' tab, which sampler
    -- subview was last opened (keyzones/waveform/modulation/effects)
    ws.middle_frame = _window.active_middle_frame

    -- restore frame states depending on the configuration
    if options.restore_upper_frame_state.value then
      _window.active_upper_frame = ws.upper_frame
      _window.upper_frame_is_visible = ws.upper_frame_visible
    end

    if options.restore_lower_frame_state.value then
      _window.active_lower_frame = ws.lower_frame
      _window.lower_frame_is_visible = ws.lower_frame_visible
    end

    if options.restore_pattern_matrix_state.value then
      _window.pattern_matrix_is_visible = ws.pattern_matrix_visible
    end

    --if options.restore_instruments_box_state.value then
      --_window.instrument_box_is_visible = ws.instrument_box_visible
    --end

    print('==================================================')
    print('restore_upper_frame_state: ', options.restore_upper_frame_state.value)
    print('restore_lower_frame_state: ', options.restore_lower_frame_state.value)
    print('restore_pattern_matrix_state: ', options.restore_pattern_matrix_state.value)
    --print('restore_instruments_box_state: ', options.restore_instruments_box_state.value)
    print('restore_disk_browser_state: ', options.restore_disk_browser_state.value)

    if options.restore_disk_browser_state.value then
      _window.disk_browser_is_visible = ws.disk_browser_visible
    end
  end
)

_window.active_upper_frame_observable:add_notifier(
  function()
    workspace_states[_active_workspace_index].upper_frame =
        _window.active_upper_frame
  end
)

_window.upper_frame_is_visible_observable:add_notifier(
  function()
    workspace_states[_active_workspace_index].upper_frame_visible =
        _window.upper_frame_is_visible
  end
)

_window.active_lower_frame_observable:add_notifier(
  function()
    workspace_states[_active_workspace_index].lower_frame =
        _window.active_lower_frame
  end
)

_window.lower_frame_is_visible_observable:add_notifier(
  function()
    workspace_states[_active_workspace_index].lower_frame_visible =
        _window.lower_frame_is_visible
  end
)

_window.pattern_matrix_is_visible_observable:add_notifier(
  function()
    workspace_states[_active_workspace_index].pattern_matrix_visible =
        _window.pattern_matrix_is_visible
  end
)

_window.instrument_box_is_visible_observable:add_notifier(
  function()
    workspace_states[_active_workspace_index].instrument_box_visible =
        _window.instrument_box_is_visible
  end
)

_window.disk_browser_is_visible_observable:add_notifier(
  function()
    workspace_states[_active_workspace_index].disk_browser_visible =
        _window.disk_browser_is_visible
  end
)

------------------------------------------------------------------------------
-- toggle frames

function toggle_upper_frame()
  _window.upper_frame_is_visible = not _window.upper_frame_is_visible
end

function toggle_lower_frame()
  _window.lower_frame_is_visible = not _window.lower_frame_is_visible
end

function toggle_both_frames()
  if _window.upper_frame_is_visible ~= _window.lower_frame_is_visible then
    _window.upper_frame_is_visible = false
    _window.lower_frame_is_visible = false
  else
    toggle_upper_frame()
    toggle_lower_frame()
  end
end

function toggle_pattern_matrix()
  _window.pattern_matrix_is_visible = not _window.pattern_matrix_is_visible
end

function toggle_disk_browser()
  _window.disk_browser_is_visible = not _window.disk_browser_is_visible
end

------------------------------------------------------------------------------
-- cycle frames

function cycle_upper_frame()
  if _window.active_upper_frame == AppWindow.UPPER_FRAME_TRACK_SCOPES then
    _window.active_upper_frame = AppWindow.UPPER_FRAME_MASTER_SPECTRUM
  else
    _window.active_upper_frame = AppWindow.UPPER_FRAME_TRACK_SCOPES
  end
end

function cycle_lower_frame()
  if _window.active_lower_frame == AppWindow.LOWER_FRAME_TRACK_SCOPES then
    _window.active_lower_frame = AppWindow.LOWER_FRAME_MASTER_SPECTRUM
  else
    _window.active_lower_frame = AppWindow.LOWER_FRAME_TRACK_SCOPES
  end
end

------------------------------------------------------------------------------
-- main

function perform_workspace_action()

  local action

  if _active_workspace_index == PATTERN_WORKSPACE then
    action = options.pattern_workspace_action.value

  elseif _active_workspace_index == MIXER_WORKSPACE then
    action = options.mixer_workspace_action.value

  elseif _active_workspace_index == SAMPLER_WORKSPACE then
    action = options.sampler_workspace_action.value
  end

  if     action == CYCLE_UPPER_FRAME     then cycle_upper_frame()
  elseif action == CYCLE_LOWER_FRAME     then cycle_lower_frame()
  elseif action == TOGGLE_UPPER_FRAME    then toggle_upper_frame()
  elseif action == TOGGLE_LOWER_FRAME    then toggle_lower_frame()
  elseif action == TOGGLE_BOTH_FRAMES    then toggle_both_frames()
  elseif action == TOGGLE_PATTERN_MATRIX then toggle_pattern_matrix()
  elseif action == TOGGLE_DISK_BROWSER   then toggle_disk_browser()
  end
end


function activate_workspace(repeated, workspace_index)

  if repeated then return end

  -- perform custom action when active workspace has been activated again
  if workspace_index == _active_workspace_index then
    perform_workspace_action()
  else
    -- switch to a different workspace (the workspace restore logic is in the
    -- active_middle_frame observer in order to make workspace switching work
    -- with mouse actions as well)
    _window.active_middle_frame = workspace_states[workspace_index].middle_frame
  end
end

------------------------------------------------------------------------------
-- keybindings

renoise.tool():add_keybinding {
  name = 'Global:View:Show/Toggle Pattern Workspace',
  invoke = function(repeated)
    activate_workspace(repeated, PATTERN_WORKSPACE)
  end
}

renoise.tool():add_keybinding {
  name = 'Global:View:Show/Toggle Mixer Workspace',
  invoke = function(repeated)
    activate_workspace(repeated, MIXER_WORKSPACE)
  end
}

renoise.tool():add_keybinding {
  name = 'Global:View:Show/Toggle Sampler Workspace',
  invoke = function(repeated)
    activate_workspace(repeated, SAMPLER_WORKSPACE)
  end
}

------------------------------------------------------------------------------
-- COLUMN NAVIGATION
------------------------------------------------------------------------------

function select_next_column()

  local song = renoise.song()

  if song.selected_track.collapsed then
    song:select_next_track()
    return
  end

  local note_column_index   = song.selected_note_column_index
  local effect_column_index = song.selected_effect_column_index
  local visible_note_columns = song.selected_track.visible_note_columns
  local visible_effect_columns = song.selected_track.visible_effect_columns

  if note_column_index > 0 then
    if note_column_index < visible_note_columns then
      song.selected_note_column_index = note_column_index + 1
    else
      if visible_effect_columns > 0 then
        song.selected_effect_column_index = 1
      else
        song:select_next_track()
      end
    end

  else
    if effect_column_index < visible_effect_columns then
      song.selected_effect_column_index = effect_column_index + 1
    else
      song:select_next_track()
    end
  end
end

------------------------------------------------------------------------------

function select_previous_column()

  local song = renoise.song()
  local track = song.selected_track
  local note_column_index   = song.selected_note_column_index
  local effect_column_index = song.selected_effect_column_index
  local visible_note_columns = track.visible_note_columns
  local visible_effect_columns = track.visible_effect_columns

  local function select_last_column_of_previous_track()
    song:select_previous_track()

    if track.visible_effect_columns > 0 then
      song.selected_effect_column_index = visible_effect_columns
    else
      song.selected_note_column_index = visible_note_columns
    end
  end

  if track.collapsed then
    select_last_column_of_previous_track()
    return
  end

  if note_column_index > 0 then
    if note_column_index > 1 then
      song.selected_note_column_index = note_column_index - 1
    else
      select_last_column_of_previous_track()
    end

  else
    if effect_column_index > 1 then
      song.selected_effect_column_index = effect_column_index - 1
    else
      if visible_note_columns > 0 then
        song.selected_note_column_index = visible_note_columns
      else
        select_last_column_of_previous_track()
      end
    end
  end
end

-- keybindings

renoise.tool():add_keybinding {
  name = 'Pattern Editor:Navigation:Jump to Next Note/FX Column',
  invoke = select_next_column
}

renoise.tool():add_keybinding {
  name = 'Pattern Editor:Navigation:Jump to Previous Note/FX Column',
  invoke = select_previous_column
}

------------------------------------------------------------------------------
-- JUMP TO TRACK
------------------------------------------------------------------------------

for i = 1, 32 do
  renoise.tool():add_keybinding {
    name = 'Pattern Editor:Navigation:Jump to Track ' .. i,
    invoke = function() renoise.song().selected_track_index = i end
  }
end

------------------------------------------------------------------------------
-- JUMP BETWEEN NOTE AND FX COLUMNS
------------------------------------------------------------------------------

local _last_note_column_index = 1
local _last_effect_column_index = 1


renoise.tool().app_new_document_observable:add_notifier(
  function()
    renoise.song().selected_track_observable:add_notifier(
      function()
        _last_note_column_index = 1
        _last_effect_column_index = 1
      end
    )
  end
)


function jump_between_note_and_effect_columns(repeated)

  if repeated then return end

  local song = renoise.song()
  local track = song.selected_track;

  if track.collapsed then return end

  if song.selected_note_column_index > 0 then
    if track.visible_effect_columns > 0 then
      _last_note_column_index = song.selected_note_column_index
      song.selected_effect_column_index =
        math.min(_last_effect_column_index, track.visible_effect_columns)
    end
  else
    if track.visible_note_columns > 0 then
      _last_effect_column_index = song.selected_effect_column_index
      song.selected_note_column_index =
        math.min(_last_note_column_index, track.visible_note_columns)
    end
  end
end

-- keybindings

renoise.tool():add_keybinding {
  name = 'Pattern Editor:Navigation:Jump between Note and FX Columns',
  invoke = jump_between_note_and_effect_columns
}

renoise.tool():add_keybinding {
  name = 'Pattern Editor:Navigation:Jump between Note and FX Columns (2nd)',
  invoke = jump_between_note_and_effect_columns
}

------------------------------------------------------------------------------
-- SHOW/TOGGLE LOWER FRAME
------------------------------------------------------------------------------

function show_toggle_lower_frame()

  if _window.lower_frame_is_visible then
    if w.active_lower_frame == AppWindow.LOWER_FRAME_TRACK_DSPS then
      w.active_lower_frame = AppWindow.LOWER_FRAME_TRACK_AUTOMATION
    else
      w.active_lower_frame = AppWindow.LOWER_FRAME_TRACK_DSPS
    end

  else
    w.lower_frame_is_visible = true
  end
end


-- keybindings

renoise.tool():add_keybinding {
  name = 'Global:View:Show/Toggle Lower Frame',
  invoke = show_toggle_lower_frame
}

------------------------------------------------------------------------------
-- TURN OFF SEQUENCE SORTING
------------------------------------------------------------------------------

-- TODO add config options for this

renoise.tool().app_new_document_observable:add_notifier(
  function()
    renoise.song().sequencer.keep_sequence_sorted = false
  end
)

-- vim: ts=2 sts=4 sw=2 et
