---@diagnostic disable: assign-type-mismatch
---@class LanguageManager : ScriptableObjectClass
---@field language string The current language
---@field tags string[] The tag table
LanguageManager = class()

local fallbackLanguage = sm.json.open("$CONTENT_DATA/Gui/Language/English/tags.json")

function LanguageManager:client_onCreate()
    g_languageManager = self
end

---@param name string The name of the language tag from $CONTENT_DATA/Gui/Language/${Language_name}/tags.json
function language_tag(name)
    if not g_languageManager then --Stupid fix because quests load before this.
        g_languageManager = { language = "yo mama" }
    end

    local currentLang = sm.gui.getCurrentLanguage()
    if currentLang ~= g_languageManager.language then --when language changed
        g_languageManager.language = currentLang
        local path = "$CONTENT_DATA/Gui/Language/" .. g_languageManager.language .. "/tags.json"
        if sm.json.fileExists(path) then
            g_languageManager.tags = sm.json.open(path)
        end
    end

    local textInJson = nil
    if g_languageManager.tags then
        textInJson = g_languageManager.tags[name] or fallbackLanguage[name] --return fallback tag if not found
    end

    return tostring(textInJson)
end
