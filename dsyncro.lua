---
--- Created By 0xWaleed <https://github.com/0xWaleed>
--- DateTime: 30/12/2021 3:54 PM
---

local dsyncroMT  = {}

local watchMT    = {
    __newindex = function(t, k, v)
        t.__dsyncroInstance['@' .. k] = v
    end,
}

local accessorMT = {
    __newindex = function(t, k, v)
        t.__accessors[k] = v
    end,
}

local mutatorMT  = {
    __newindex = function(t, k, v)
        t.__mutators[k] = v
    end,
}

local silentMT   = {
    __newindex = function(t, k, v)
        t.__dsyncroInstance['-' .. k] = v
    end,
}

local function watch(dsyncroInstance)
    local o             = {}
    o.__dsyncroInstance = dsyncroInstance
    setmetatable(o, watchMT)
    return o
end

local function accessor(dsyncroInstance)
    local o       = {}
    o.__accessors = dsyncroInstance.__accessors
    setmetatable(o, accessorMT)
    return o
end

local function mutator(dsyncroInstance)
    local o      = {}
    o.__mutators = dsyncroInstance.__mutators
    setmetatable(o, mutatorMT)
    return o
end

local function silent(dsyncroInstance)
    local o             = {}
    o.__dsyncroInstance = dsyncroInstance
    setmetatable(o, silentMT)
    return o
end

local function has_silent_modifier(key)
    return string.find(key, '^-') ~= nil
end

local function sanitize_chars_from_string(key, char)
    return string.gsub(key, char, '')
end

dsyncro = {}

local function explode_string(string, sep)
    sep     = sep or '%s'
    local t = {}
    for str in string.gmatch(string, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

local function reverse(t)
    local out = {}
    for i = #t, 1, -1 do
        table.insert(out, t[i])
    end
    return out
end

local function has_watcher_modifier(key)
    return type(key) == 'string' and key:find('@')
end

local function has_full_path(key)
    return type(key) == 'string' and key:find('%.')
end

local function get_target_from_full_path(root, path)
    local keys      = explode_string(path, '.')
    local target    = root
    local keysCount = #keys
    local lastKey   = keys[keysCount]
    for i = 1, keysCount do
        local key = keys[i]

        if key == lastKey then
            break
        end

        if tonumber(key) then
            key = tonumber(key)
        end

        if not target[key] then
            target[key] = target:createChild(key, {})
        end

        target = target[key]
    end

    if tonumber(lastKey) then
        lastKey = tonumber(lastKey)
    end

    return lastKey, target
end

function dsyncroMT:__newindex(key, value)
    if has_watcher_modifier(key) then
        local actualKey                       = sanitize_chars_from_string(key, '@')
        rawget(self, '__watchers')[actualKey] = value
        return
    end

    local __silent = rawget(self, '__silent')

    if self.__parent then
        __silent = {}
    end

    if has_silent_modifier(key) then
        key               = sanitize_chars_from_string(key, '%-')
        local explodedKey = explode_string(key, '.')
        for _, k in ipairs(explodedKey) do
            local indexAsInteger = tonumber(k)
            if indexAsInteger then
                __silent[indexAsInteger] = true
            else
                __silent[k] = true
            end
        end
    end

    if has_full_path(key) then
        local targetKey, target = get_target_from_full_path(self, key)
        target[targetKey]       = value
        return
    end

    if type(value) == 'table' and not dsyncro.classOf(value) then
        value = self:createChild(key, value)
    end

    local store = rawget(self, '__store')
    if store[key] == value then
        return
    end

    local mutatorFunc = rawget(self, '__mutators')[key]
    store[key]        = mutatorFunc and mutatorFunc(value) or value

    if not __silent[key] then
        self:invokeSetCallbacks(key, value)
    end

    self:invokeWatchers(key)
end

function dsyncroMT:onKeySet(callback)
    rawget(self, '__settersCallback')[tostring(callback)] = callback
end

function dsyncroMT:traverseToRoot()
    local currentInstance = self
    return function()
        local instanceToReturn = currentInstance
        if not instanceToReturn then
            return
        end
        currentInstance = rawget(instanceToReturn, '__parent')
        if currentInstance then
            currentInstance = currentInstance()
        end
        return instanceToReturn
    end
end

function dsyncroMT:invokeWatchers(key)
    local w = rawget(self, '__watchers')[key]

    if w then
        w(self[key], self)
    end

    local parent = rawget(self, '__parent')
    if not parent then
        return
    end

    parent():invokeWatchers(rawget(self, '__key'))
end

function dsyncroMT:createChild(key, items)
    local newT = dsyncro.new()

    for k, v in pairs(items) do
        newT[k] = v
    end

    rawset(newT, '__parent', function() return self end)
    rawset(newT, '__key', key)

    return newT
end

function dsyncroMT:invokeSetCallbacks(key, value)
    local handlers = {}
    local path     = { key }

    for instance in self:traverseToRoot() do

        local __silent = rawget(instance, '__silent')

        if __silent[key] then
            return
        end

        local callbacks = rawget(instance, '__settersCallback')

        for _, setterCallback in pairs(callbacks) do
            table.insert(handlers, setterCallback)
        end

        table.insert(path, rawget(instance, '__key'))
    end

    path = table.concat(reverse(path), '.')

    if #handlers < 1 then
        return
    end

    for _, setter in pairs(handlers) do
        setter(self, path, value)
    end
end

function dsyncroMT:rawItems()
    local rawItems = {}
    local items    = rawget(self, '__store')
    for key, value in pairs(items) do
        if dsyncro.classOf(value) then
            rawItems[key] = value:rawItems()
        else
            rawItems[key] = value
        end
    end
    return rawItems
end

function dsyncroMT:__index(key)

    if key == 'watch' then
        return rawget(self, '__watch')
    end

    if key == 'accessor' then
        return rawget(self, '__accessor')
    end

    if key == 'mutator' then
        return rawget(self, '__mutator')
    end

    if key == 'silent' then
        return rawget(self, '__sil')
    end

    local value = rawget(self, '__store')[key]

    if value then
        if not rawget(self, '__accessors')[key] then
            return value
        end
        return rawget(self, '__accessors')[key](value)
    end

    value = dsyncroMT[key]

    if value then
        return value
    end

    if key == '__parent' or key == '__key' then
        return
    end

    for instance in self:traverseToRoot() do
        value = rawget(rawget(instance, '__store'), key)
        if value then
            return value
        end
    end

end

function dsyncroMT:__pairs()
    return next, rawget(self, '__store')
end

function dsyncroMT:__len()
    return #rawget(self, '__store')
end

function dsyncro.new()
    local o             = { __dsyncro = true }
    o.__watchers        = {}
    o.__store           = {}
    o.__settersCallback = {}
    o.__accessors       = {}
    o.__mutators        = {}
    o.__silent          = {}
    o.__watch           = watch(o)
    o.__accessor        = accessor(o)
    o.__mutator         = mutator(o)
    o.__sil             = silent(o)
    setmetatable(o, dsyncroMT)
    return o
end

function dsyncro.classOf(value)
    return type(value) == 'table' and value.__dsyncro
end
