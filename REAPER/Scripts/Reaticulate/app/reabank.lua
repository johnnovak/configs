-- Copyright 2017 Jason Tackaberry
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

require 'lib.utils'
local rtk = require 'lib.rtk'
local class = require 'lib.middleclass'
local articons = require 'articons'
local rfx = nil

local reabank = {
    reabank_filename_factory = nil,
    reabank_filename_user = nil,
    filename_tmp = nil,
    version = nil,
    banks = {},
    -- Maps fully qualified group/name to bank object.
    banks_by_path = {},
    articulation_map = {},
    menu = nil,
    colors = {
        ['default'] = '#666666'
    },
    textcolors = {
        ['default'] = '#ffffff'
    }

}

local ARTICULATION_FLAG_CHASE = 1 << 0
local ARTICULATION_FLAG_ANTIHANG = 1 << 1
local ARTICULATION_FLAG_ANTIHANG_CC = 1 << 2
local ARTICULATION_FLAG_BLOCK_BANK_CHANGE = 1 << 3
local ARTICULATION_FLAG_TOGGLE = 1 << 4
local ARTICULATION_FLAG_HIDDEN = 1 << 5

local function insert_program_change(take, selected, ppq, channel, bank_msb, bank_lsb, program)
    reaper.MIDI_InsertCC(take, selected, false, ppq, 0xb0, channel, 0, bank_msb)
    reaper.MIDI_InsertCC(take, selected, false, ppq, 0xb0, channel, 32, bank_lsb)
    reaper.MIDI_InsertCC(take, selected, false, ppq, 0xc0, channel, program, 0)
    local item = reaper.GetMediaItemTake_Item(take)
    reaper.UpdateItemInProject(item)
end

local function replace_selected_events(take, channel, bank_msb, bank_lsb, val)
    local evtidx = reaper.MIDI_EnumSelEvts(take, 0)
    local replace = {}
    while evtidx > -1 do
        local rv, selected, muted, ppq, msg = reaper.MIDI_GetEvt(take, evtidx, true, true, 1, "")
        local command = string.byte(msg, 1) & 0xf0
        local value = string.byte(msg, 2)
        -- Replace either CC 0 (command == 176) and value 0/32, which is a bank select, or
        -- a program change (command == 192).
        if (command == 0xb0 and (value == 0 or value == 0x20)) or command == 0xc0 then
            replace[#replace+1] = {evtidx, ppq}
        end
        evtidx = reaper.MIDI_EnumSelEvts(take, evtidx + 1)
    end
    if #replace > 0 then
        for _, events in ipairs(replace) do
            local evtidx, ppq = table.unpack(events)
            reaper.MIDI_DeleteEvt(take, evtidx)
            insert_program_change(take, true, ppq, channel, bank_msb, bank_lsb, val)
        end
        return true
    else
        return false
    end
    return #replace > 0
end

-- Source channel starts at 1 (17 = use default channel)
local function activate_articulation(source_channel, msb, lsb, program)
    local channel = source_channel - 1
    if channel >= 16 then
        channel = App.default_channel - 1
    end
    local hwnd = reaper.MIDIEditor_GetActive()
    if hwnd then
        -- Magic value 32060 is the MIDI editor context
        local stepInput = reaper.GetToggleCommandStateEx(32060, 40481)
        if stepInput == 1 then
            -- Step recording is enabled in the editor, so inject the PC event at
            -- the current cursor position.
            reaper.PreventUIRefresh(1)
            reaper.Undo_BeginBlock2(0)
            local take = reaper.MIDIEditor_GetTake(hwnd)
            -- Replace any existing selected events (if those events are program changes)
            -- otherwise insert a new event at the cursor position.
            if not replace_selected_events(take, channel, msb, lsb, program) then
                local cursor = reaper.GetCursorPosition()
                local ppq = reaper.MIDI_GetPPQPosFromProjTime(take, cursor)
                insert_program_change(take, false, ppq, channel, msb, lsb, program)
            end
            reaper.Undo_EndBlock2(0, "MIDI editor: insert program change (" .. program .. ")", -1)
            reaper.PreventUIRefresh(-1)
        end
    end
    rfx.activate_articulation(channel, program)
    reaper.StuffMIDIMessage(0, 0xb0 + channel, 0, msb)
    reaper.StuffMIDIMessage(0, 0xb0 + channel, 0x20, lsb)
    reaper.StuffMIDIMessage(0, 0xc0 + channel, program, 0)
end


local function _parse_flags(flags, value)
    if not flags then
        return value
    end
    for _, flag in ipairs(flags:split(',')) do
        local negate = false
        local mask = 0
        if flag:starts("!") then
            negate = true
            flag = flag:sub(2)
        end
        if flag == 'chase' then
            mask = ARTICULATION_FLAG_CHASE
        elseif flag == 'antihang' then
            mask = ARTICULATION_FLAG_ANTIHANG
        elseif flag == 'antihangcc' then
            mask = ARTICULATION_FLAG_ANTIHANG_CC
        elseif flag == 'nobank' then
            mask = ARTICULATION_FLAG_BLOCK_BANK_CHANGE
        elseif flag == 'toggle' then
            mask = ARTICULATION_FLAG_TOGGLE
        elseif flag == 'hidden' then
            mask = ARTICULATION_FLAG_HIDDEN
        end
        if negate then
            value = value & ~mask
        else
            value = value | mask
        end
    end
    return value
end


local Bank = class('Bank')
function Bank:initialize(factory, msb, lsb, name, attrs)
    self.factory = factory
    self.msb = tonumber(msb)
    self.lsb = tonumber(lsb)
    self.name = name
    self.msblsb = (self.msb << 8) + self.lsb
    -- List of articulations in order defined in Reabank file
    self.articulations = {}
    -- Articulation objects keyed by program number.
    self.articulations_by_program = {}
    -- Set by the app layer when a track is selected which uses this bank.
    -- 1 = channel 1, 17 = omni
    self.channel = 17
    table.merge(self, attrs)

    self.flags = _parse_flags(self.flags,
        -- Defaults
        ARTICULATION_FLAG_CHASE |
        ARTICULATION_FLAG_ANTIHANG |
        ARTICULATION_FLAG_ANTIHANG_CC |
        ARTICULATION_FLAG_BLOCK_BANK_CHANGE
    )
end

function Bank:add_articulation(art)
    art._index = #self.articulations + 1
    self.articulations[art._index] = art
    self.articulations_by_program[art.program] = art
end

function Bank:get_articulation_by_program(program)
    return self.articulations_by_program[program]
end

function Bank:get_articulation_before(art)
    if art then
        local idx = art._index - 1
        if idx >= 1 then
            return self.articulations[idx]
        end
    end
end

function Bank:get_articulation_after(art)
    if art then
        local idx = art._index + 1
        if idx <= #self.articulations then
            return self.articulations[idx]
        end
    end
end

function Bank:get_first_articulation()
    return self.articulations[1]
end

function Bank:get_last_articulation()
    return self.articulations[#self.articulations]
end

function Bank:get_src_channel()
    if self.srcchannel == 17 then
        return App.default_channel
    else
        return self.srcchannel
    end
end

function Bank:create_ui()
    self.vbox = rtk.VBox:new({spacing=10})
    self.heading = rtk.Heading:new({label=self.shortname or self.name})
    self.vbox:add(self.heading, {lpadding=10, tpadding=#reabank.banks > 0 and 40 or 20, bpadding=10})

    for n, art in ipairs(self.articulations) do
        local color = art.color or reabank.colors.default
        local textcolor = '#ffffff'
        if not color:starts('#') then
            color = reabank.colors[color]
        end
        local textcolor = color2luma(color) > 0.7 and '#000000' or '#ffffff'
        art.icon = articons.get(art.iconname or 'note-eighth')
        local flags = art.channels > 0 and 0 or rtk.Button.FLAT_LABEL
        local outputstr = art:describe_outputs()
        art.button = rtk.Button:new({label=(art.shortname or art.name), icon=art.icon, color=color, textcolor=textcolor,
                                     tpadding=1, rpadding=1, bpadding=1, lpadding=1,
                                     flags=flags, rspace=40})
        -- Make button width fill container (with 10px margin at right)
        art.button:resize(-10, nil)
        art.button.onclick = function(button, event) App.onartclick(art, event) end
        art.button.ondraw = function(button, offx, offy, event) art:draw_button_midi_channel(button, offx, offy, event) end
        art.button.onblur = function(button, event) App.set_statusbar(nil) end
        art.button.onhover = function(button, event)
            -- button:scrollto(130, 40)
            App.set_statusbar(outputstr)
        end
        self.vbox:add(art.button, {lpadding=30})
    end
    self.vbox:hide()
    return self.vbox
end

function Bank:get_path()
    if not self.group then
        return self.shortname or self.name
    else
        return self.group .. '/' .. (self.shortname or self.name)
    end
end

function Bank:copy_articulations_from(from_bank)
    for _, art in ipairs(from_bank.articulations) do
        art:copy_to_bank(self)
    end
end

local Articulation = class('Articulation')
function Articulation:initialize(bank, program, name, attrs)
    self.color = 'default'
    -- 16-bit bitmap of channels this articulation is active on (on current track).
    -- This value is set by the main app layer on track change.
    self.channels = 0
    -- Store the bank index instead of the bank itself to avoid the circular reference.
    self.bankidx = (bank.msb << 8) + bank.lsb
    self.program = program
    self.name = name
    self._attrs = attrs
    table.merge(self, attrs)
    self.group = tonumber(self.group or 1)

    self.flags = _parse_flags(self.flags, bank.flags)
end

function Articulation:get_outputs()
    if not self._outputs then
        self._outputs = {}
        for spec in (self.outputs or ''):gmatch('([^/]+)') do
            output = {type=nil, channel=nil, args={}}
            for prefix, part in ('/' .. spec):gmatch('([/@:])([^@:]+)') do
                if prefix == '/' then
                    output.type = part
                elseif prefix == '@' then
                    output.channel = tonumber(part)
                elseif prefix == ':' then
                    output.args = part:split(',')
                end
            end
            self._outputs[#self._outputs+1] = output
        end
    end
    return self._outputs
end

-- Returns a human readable string explaining what the outputs do.
function Articulation:describe_outputs()
    local outputs = self:get_outputs()
    local description = ''
    local last_verb = nil
    for n, output in ipairs(outputs) do
        local s = nil
        local verb = 'Sends'
        if output.type == 'program' then
            s = string.format('program change %d', output.args[1] or 0)
        elseif output.type == 'cc' then
            s = string.format('CC %d val %d', output.args[1] or 0, output.args[2] or 0)
        elseif output.type == 'note' or output.type == 'note-hold' then
            local note = tonumber(output.args[1] or 0)
            local name = note_to_name(note)
            verb = output.type == 'note' and 'Sends' or 'Holds'
            if (output.args[2] or 127) == 127 then
                s = string.format('note %s', name)
            else
                s = string.format('note %s vel %d', name, output.args[2] or 127)
            end
        elseif output.type == nil and output.channel then
            verb = 'Routes'
            s = string.format('to ch %d', output.channel)
        end
        if s then
            if output.type and output.channel then
                s = s .. string.format(' on ch %d', output.channel)
            end
            if last_verb then
                if verb == last_verb then
                    description = string.format('%s, %s', description, s)
                else
                    description = string.format('%s, %s %s', description, verb:lower(), s)
                end
            else
                description = string.format('%s %s', verb, s)
            end
            last_verb = verb
        end
    end
    return description
end

function Articulation:copy_to_bank(bank)
    local clone = Articulation(bank, self.program, self.name, self._attrs)
    bank:add_articulation(clone)
end

function Articulation:get_bank()
    return reabank.banks[self.bankidx]
end

function Articulation:activate(refocus)
    local refocus = function()
        if refocus == true then
            App.refocus()
        end
    end
    reaper.defer(refocus)
    if self.program >= 0 then
        local bank = self:get_bank()
        activate_articulation(bank.srcchannel, bank.msb, bank.lsb, self.program)
        return true
    else
        return false
    end
end

function Articulation:is_active()
    return self.channels ~= 0
end

function Articulation:draw_button_midi_channel(button, offx, offy, event)
    local hovering = event:is_widget_hovering(button)
    if not hovering and not self:is_active() then
        -- No channel boxes to draw.
        return
    end

    local channels = {}
    local bitmap = self.channels
    local hover_channel = nil
    if hovering then
        local bank = self:get_bank()
        hover_channel = bank:get_src_channel() - 1
        bitmap = bitmap | (1 << hover_channel)
    end

    local channel = 0
    while bitmap > 0 do
        if bitmap & 1 > 0 then
            channels[#channels+1] = channel
        end
        bitmap = bitmap >> 1
        channel = channel + 1
    end

    if channels then
        local x = offx + button.cx + button.cw
        gfx.setfont(1, button.font, (button.fontsize - 2) * rtk.scale, rtk.fonts.BOLD)
        for idx, channel in ipairs(channels) do
            local lw, lh = gfx.measurestr(channel + 1)
            x = x - (lw + 15)
            local y = offy + button.cy + (button.ch - lh) / 2
            button:setcolor('#ffffff')
            local fill = (channel == hover_channel) or (App.active_notes & (1 << channel) > 0)
            gfx.rect(x - 5, y - 1, lw + 10, lh + 2, fill)
            if fill then
                button:setcolor('#000000')
            end
            gfx.x = x
            gfx.y = y
            gfx.drawstr(channel + 1)
        end
    end
end


function reabank.parse_colors(colors)
    for name, color in colors:gsub(',', ' '):gmatch('(%S+)=([^"]%S*)') do
        reabank.colors[name] = color
    end
end


local function parse_properties(line)
    props = {}
    for key, value in line:gmatch('(%w+)=([^"]%S*)') do
        props[key] = value
    end
    for key, value in line:gmatch('(%w+)="([^"]*)"') do
        props[key] = value
    end
    return props
end


function reabank.parse(filename, banks)
    banks = banks or {}
    -- Track banks which are cloned
    cloned = {}
    local f = io.open(filename)
    if f == nil then
        return banks
    end

    function merge(metadata, attr, value)
        if metadata[attr] == nil then
            metadata[attr] = value
        end
    end

    local metadata = {}
    for line in f:lines() do
        line = line:gsub("^%s*(.-)%s*$", "%1")
        if line:starts("Bank") then
            -- Start of new bank
            msb, lsb, name = line:match("Bank +(%d+) +(%d+) +(.*)")
            bank = Bank(filename == reabank.reabank_filename_factory, msb, lsb, name, metadata)
            banks[bank.msblsb] = bank
            reabank.banks_by_path[bank:get_path()] = bank
            if bank.clone then
                cloned[#cloned + 1] = bank
            end
            metadata = {}
        elseif line:starts("//!") then
            -- Reaticulate metadata for the next program/bank
            local props = parse_properties(line)
            for key, value in line:gmatch('(%w+)=([^"]%S*)') do
                props[key] = value
            end
            for key, value in line:gmatch('(%w+)="([^"]*)"') do
                props[key] = value
            end
            merge(metadata, 'color', props.c)
            merge(metadata, 'iconname', props.i)
            merge(metadata, 'shortname', props.n)
            merge(metadata, 'group', props.g)
            merge(metadata, 'off', props.off and tonumber(props.off) or nil)
            merge(metadata, 'outputs', props.o)
            merge(metadata, 'flags', props.f)
            merge(metadata, 'message', props.m)
            merge(metadata, 'clone', props.clone)
            if props.colors then
                reabank.parse_colors(props.colors)
            end
        elseif line:len() > 0 and not line:starts("//") then
            program, name = line:match("(%d+) +(.*)")
            art = Articulation(bank, tonumber(program), name, metadata)
            if art.flags & ARTICULATION_FLAG_HIDDEN == 0 then
                bank:add_articulation(art)
            end
            -- Reinitialize for next articulation
            metadata = {}
        end
    end
    f:close()
    for _, bank in ipairs(cloned) do
        local source = reabank.banks_by_path[bank.clone]
        if source then
            bank:copy_articulations_from(source)
        end
    end
    return banks
end

function reabank.parseall()
    local banks = reabank.parse(reabank.reabank_filename_factory)
    return reabank.parse(reabank.reabank_filename_user, banks)
end

function reabank.create_user_reabank_if_missing()
    local f = io.open(reabank.reabank_filename_user)
    if f then
        f:close()
        return
    end
    -- File is missing, create with header from factory reabank.
    local inf = io.open(reabank.reabank_filename_factory)
    local outf = io.open(reabank.reabank_filename_user, 'w')
    for line in inf:lines() do
        if line:starts("//!") then
            break
        end
        outf:write(line .. '\n')
    end
    inf:close()
    outf:close()
end

local function set_reabank_file(reabank)
    local inifile = reaper.get_ini_file()
    local ini = read_file(inifile)
    if ini:find("mididefbankprog=") then
        ini = ini:gsub("mididefbankprog=[^\n]*", "mididefbankprog=" .. reabank)
    else
        pos = ini:find('%[REAPER%]\n')
        if not pos then
            pos = ini:find('%[reaper%]\n')
        end
        if pos then
            ini = ini:sub(1, pos + 8) .. "mididefbankprog=" .. reabank .. "\n" .. ini:sub(pos + 9)
        end
    end
    log("Updating ini file %s", inifile)
    write_file(inifile, ini)
end

function reabank.banks_to_reabank_string()
    s = ''
    for _, bank in pairs(reabank.banks) do
        s = s .. string.format('\n\nBank %d %d %s\n', bank.msb, bank.lsb, bank.name)
        for _, art in ipairs(bank.articulations) do
            s = s .. string.format('%d %s\n', art.program, art.name)
        end
    end
    return s
end

local function get_reabank_file()
    local ini = read_file(reaper.get_ini_file())
    return ini:match("mididefbankprog=([^\n]*)")
end

function reabank.init()
    -- Require inside function due to circular dependency.  Set global variable rfx.
    rfx = require 'rfx'
    local t0 = os.clock()
    reabank.reabank_filename_factory = Path.join(Path.basedir, "Reaticulate-factory.reabank")
    reabank.reabank_filename_user = Path.join(Path.resourcedir, "Data", "Reaticulate.reabank")
    log("Reabank files: factory=%s user=%s", reabank.reabank_filename_factory, reabank.reabank_filename_user)
    local file = get_reabank_file() or ''
    local tmpnum = file:lower():match("-tmp(%d+).")
    if tmpnum then
        log("parsing existing tmp rebeank")
        reabank.version = tonumber(tmpnum)
        reabank.filename_tmp = file
        reabank.menu = nil
        reabank.banks = reabank.parseall()
    else
        -- Install default Reabank.
        log("generating new reabank")
        reabank.banks = reabank.parse(reabank.reabank_filename_factory)
        reabank.refresh()
    end
    log("Reabank %s parsed in %.03fs", reabank.filename_tmp, os.clock() - t0)
end


function reabank.refresh()
    local tmpnum = 1
    if reabank.filename_tmp then
        tmpnum = tonumber(reabank.filename_tmp:match("-tmp(%d+).")) + 1
    end

    -- FIXME: assumes case
    local newfile = reabank.reabank_filename_user:gsub("(.*).reabank", "%1-tmp" .. tmpnum .. ".reabank")
    -- Copy contents to tmp reabank
    local header = "// Generated file.  DO NOT EDIT!  CONTENTS WILL BE LOST!\n"
    header = header .. "// Edit this instead: " .. reabank.reabank_filename_user .. "\n\n\n\n"

    reabank.banks = reabank.parseall()
    write_file(newfile, header .. reabank.banks_to_reabank_string())
    set_reabank_file(newfile)

    -- Kick all media items on the current track as well as the selected media
    -- item in the ass to recognize the changes made to the reabank.
    local item = reaper.GetSelectedMediaItem(0, 0)
    if item then
        local retval, chunk = reaper.GetItemStateChunk(item, "", 0)
        reaper.SetItemStateChunk(item, chunk, 0)
    end
    if App.track then
        for idx = 0, reaper.GetTrackNumMediaItems(App.track) - 1 do
            local item = reaper.GetTrackMediaItem(App.track, idx)
            local retval, chunk = reaper.GetItemStateChunk(item, "", 0)
            reaper.SetItemStateChunk(item, chunk, 0)
        end
    end

    if reabank.filename_tmp and reaper.file_exists(reabank.filename_tmp) then
        log("deleting old reabank file: %s", reabank.filename_tmp)
        os.remove(reabank.filename_tmp)
    end
    reabank.filename_tmp = newfile
    log("switched to new reabank file: %s", newfile)
    reabank.version = tmpnum
    reabank.menu = nil
end


function reabank.get_bank(msb, lsb)
    return reabank.get_bank_by_msblsb((msb << 8) + lsb)
end

function reabank.get_bank_by_msblsb(msglsb)
    -- math.floor() used to cast float to int
    return reabank.banks[math.floor(msglsb)]
end

function reabank.to_menu()
    if reabank.menu then
        return reabank.menu
    end

    local bankmenu = {}
    for _, bank in pairs(reabank.banks) do
        local submenu = bankmenu
        if bank.group then
            local group = (bank.factory and 'Factory/' or 'User/') .. bank.group
            for part in group:gmatch("[^/]+") do
                -- Find the index of this part in the current submenu.
                local found = false
                for n, tmpmenu in ipairs(submenu) do
                    if tmpmenu[1] == part then
                        submenu = tmpmenu[2]
                        found = true
                        break
                    end
                end
                if not found then
                    tmpmenu = {part, {}}
                    submenu[#submenu+1] = tmpmenu
                    submenu = tmpmenu[2]
                end
            end
        end
        submenu[#submenu+1] = {bank.shortname or bank.name, tostring(bank.msblsb), 0, bank.name}
    end

    function cmp(a, b)
        return a[1] < b[1]
    end
    function sort(t)
        for _, submenu in pairs(t) do
            if type(submenu[2]) == 'table' then
                sort(submenu[2])
            end
        end
        table.sort(t, cmp)
    end
    sort(bankmenu)
    reabank.menu = bankmenu
    return bankmenu
end

return reabank