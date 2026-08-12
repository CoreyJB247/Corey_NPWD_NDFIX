--[[
    Workaround for project-error/npwd issue #1141:
    "ND Core integration not saving phone numbers correctly"
    https://github.com/project-error/npwd/issues/1141

    npwd's built-in `npwd:framework ndcore` bridge fails to persist a
    character's phonenumber back to `nd_characters` on unload/disconnect,
    which both wipes the number AND leaves npwd's internal player map in a
    bad state (causing the deletePlayerFromMaps crash on drop).

    This resource takes over the bridge manually:
      - We keep the phone number in ND's OWN character metadata, which ND
        Core reliably persists via its own save() cycle.
      - We explicitly call npwd's newPlayer / unloadPlayer exports at the
        right times, so npwd's internal maps are always in a known state.

    IMPORTANT: remove/comment out `set npwd:framework ndcore` from your
    server.cfg before using this. Both bridges running at once will
    double-register players and reintroduce the bug.
]]

local NPWD = exports.npwd

---Get an existing phone number from ND's own phonenumber field, or generate + persist one
---@param character table ND character object (has get/setData)
---@return string
local function getOrCreatePhoneNumber(character)
    -- IMPORTANT: `phonenumber` is its own dedicated field on the ND
    -- character object (and its own DB column), NOT part of `metadata`.
    -- Using getMetadata/setMetadata here was the earlier bug - it wrote to
    -- a completely different JSON blob that self.save() ignores for this
    -- purpose.
    local phoneNumber = character.getData('phonenumber')

    if not phoneNumber or phoneNumber == '' then
        -- ask npwd to generate a valid, unique number
        local ok, generated = pcall(function()
            return NPWD:generatePhoneNumber()
        end)

        if not ok or not generated then
            print('[npwd_ndcore_fix] ERROR: failed to generate phone number from npwd export')
            return nil
        end

        phoneNumber = generated
        character.setData('phonenumber', phoneNumber)
    end

    return phoneNumber
end

---Register the character with npwd
local function registerWithNpwd(character)
    local src = character.source

    if not src then
        print('[npwd_ndcore_fix] WARNING: character has no source, skipping npwd registration')
        return
    end

    -- Clear any stale/previous session for this source first, defensively.
    -- pcall in case npwd throws on a source it doesn't know about.
    pcall(function()
        NPWD:unloadPlayer(src)
    end)

    local phoneNumber = getOrCreatePhoneNumber(character)
    if not phoneNumber then
        return
    end

    NPWD:newPlayer({
        source = src,
        identifier = tostring(character.id),
        firstname = character.firstname,
        lastname = character.lastname,
        phoneNumber = phoneNumber
    })

    print(('[npwd_ndcore_fix] Registered character %s (src %s) with npwd, number %s')
        :format(character.id, src, phoneNumber))
end

---Cleanly unload the character from npwd
local function unloadFromNpwd(src)
    if not src then return end

    pcall(function()
        NPWD:unloadPlayer(src)
    end)

    print(('[npwd_ndcore_fix] Unloaded npwd player for src %s'):format(src))
end

-- Fired when a character finishes loading in ND Core
AddEventHandler('ND:characterLoaded', function(character)
    if not character then return end
    registerWithNpwd(character)
end)

-- Fired when ND Core unloads a character (switch char / logout).
-- At this point character.save() has NOT run yet, so our metadata write
-- in getOrCreatePhoneNumber (done at load time) will be included in the
-- save that ND Core performs right after this event.
AddEventHandler('ND:characterUnloaded', function(src, character)
    unloadFromNpwd(src)
end)

-- Fallback safety net: always clear npwd's map on a raw disconnect, even if
-- ND:characterUnloaded doesn't fire for some edge case (crash, timeout, etc).
AddEventHandler('playerDropped', function()
    local src = source
    unloadFromNpwd(src)
end)
