-- Copyright (c) 2015-present, Facebook, Inc.
-- All rights reserved.
--
-- This source code is licensed under the BSD-style license found in the
-- LICENSE file in the root directory of this source tree. An additional grant
-- of patent rights can be found in the PATENTS file in the same directory.


local class = require 'class'

local List = require 'pl.List'
local Set = require 'pl.Set'
local tablex = require 'pl.tablex'

local Entity = require 'babi.Entity'

--[[-- KNOWLEDGE --]]--

local EntityProperties = class('EntityProperties')

function EntityProperties:__init(knowledge)
    self.knowledge = knowledge
end

function EntityProperties:add(property, value, truth_value, support)
    -- Add knowledge about an entity e.g. John is not in the
    -- kitchen:
    -- knowledge[john]:add('is_in', {kitchen}, false)
    self[property] = self[property] or List()
    for _, _value in ipairs(self[property]) do
        if _value.value == value or
                (self.knowledge.exclusive[property] and truth_value and
                 _value.truth_value) then
            self[property]:remove_value(_value)
        end
    end
    self[property]:append({value=value, truth_value=truth_value,
                           support=support})
end

function EntityProperties:set(property, value, truth_value, support)
    -- Add knowledge about an entity e.g. John is in the
    -- kitchen:
    -- knowledge[john]:set('is_in', {kitchen}, false)
    self[property] = List{{value=value, truth_value=truth_value,
                           support=support}}
end

function EntityProperties:merge(property, values, support)
    -- Combines two lists of values, but assumes exclusivity
    self:rawadd(property, values, support)
    local true_values = tablex.filter(
        self[property],
        function(value) return value.truth_value end
    )
    if #true_values > 0 then
        self[property] = List{true_values[1]}
    end
end

function EntityProperties:rawset(property, values, support)
    -- Update knowledge of an entity with multiple values.
    -- Useful to transfer knowledge between entities. For
    -- example, John is not in the kitchen nor in the garden:
    -- knowledge[john]:update('is_in',
    --     List{{value=kitchen, truth_value=false},
    --          {value=garden, truth_value=false}})
    self[property] = tablex.deepcopy(values)
    if support then
        for _, value in ipairs(self[property]) do
            value.support = value.support + support
        end
    end
end

function EntityProperties:rawadd(property, values, support)
    self[property] = self[property] or List()
    if support then
        for _, value in ipairs(values) do
            value.support = value.support + support
        end
    end
    self[property]:extend(values)
end

function EntityProperties:is_true(property, value, return_support)
    -- Check whether it is true that an entity has a certiain
    -- property e.g. to check if John is in the garden
    -- knowledge[john]:is_true('is_in', garden)
    local truth_value = false
    local support = Set()
    if self[property] then
        for i, fact in ipairs(self[property]) do
            if value == fact.value and fact.truth_value then
                truth_value = true
                support = fact.support
                break
            end
        end
    end
    if return_support then
        return truth_value, support
    else
        return truth_value
    end
end

function EntityProperties:is_false(property, value, return_support)
    -- Check whether it is true that an entity does not have a
    -- certiain property e.g. to check if John is not in the
    -- garden
    -- knowledge[john]:is_false('is_in', garden)
    local truth_value = false
    local support = Set()
    if self[property] then
        for i, fact in ipairs(self[property]) do
            if value == fact.value and not fact.truth_value then
                truth_value = true
                support = fact.support
            elseif self.knowledge.exclusive[property] and
                    value ~= fact.value and fact.truth_value then
                truth_value = true
                support = fact.support
            end
        end
    end
    if return_support then
        return truth_value, support
    else
        return truth_value
    end
end

function EntityProperties:get_truth_value(property, value, return_support)
    -- Check whether a property holds, doesn't hold, or is
    -- unknown (nil)
    -- knowledge[john]:get_truth_value('is_in', garden)
    local is_true, support1 = self:is_true(property, value, true)
    local is_false, support2 = self:is_false(property, value, true)
    local support = (support1 or Set()) + (support2 or Set())
    if is_true or is_false then
        local truth_value = is_true and true or false
        if return_support then
            return truth_value, support
        else
            return truth_value
        end
    end
end

function EntityProperties:get_value(property, return_support)
    -- Return the true value of a property, if we know it
    local values, support = self:get_values(property, true)
    if #values > 1 then
        error('this property has multiple values')
    elseif #values == 1 then
        if return_support then
            return values[1], support[1]
        else
            return values[1]
        end
    end
end

function EntityProperties:get_support(property, value)
    if self[property] then
        if value == nil then
            if #self[property] > 1 then
                error('more than one value')
            end
            return self[property][1].support
        else
            for _, _value in ipairs(self[property]) do
                if _value.value == value then
                    return _value.support
                end
            end
        end
    end
end

function EntityProperties:_get_values(property, return_support, truth_value)
    -- Return the true value of a property, if we know it
    local values = List()
    local support = List()
    if self[property] then
        for _, value in ipairs(self[property]) do
            if self:is_true(property, value.value) then
                values:append(value.value)
                support:append(value.support)
            end
        end
    end
    if return_support then
        return values, support
    else
        return values
    end
end


function EntityProperties:get_values(property, return_support)
    return self:_get_values(property, return_support, true)
end

function EntityProperties:get_non_values(property, return_support)
    return self:_get_values(property, return_support, false)
end

local KnowledgeTable = class('KnowledgeTable')

function KnowledgeTable:__init(knowledge)
    self.knowledge = knowledge
end

local _index = KnowledgeTable.__index

function KnowledgeTable.__index(tbl, key)
    local val = rawget(tbl, key)
    if val == nil then
        if class.istype(key, 'Entity') then
            tbl[key] = EntityProperties(tbl.knowledge)
            return tbl[key]
        else
            return _index[key]
        end
    else
        return val
    end
end

-- Find entities with a certain property
function KnowledgeTable:find(property, value)
    return tablex.filter(
        tablex.keys(self),
        function(entity)
            if class.istype(entity, 'Entity') then
                local _value = self[entity]:get_value(property)
                return _value and (value == _value or value == nil)
            end
        end
    )
end

local Knowledge = class('Knowledge')

function Knowledge:__init(world, rules)
    self.t = 0
    self.knowledge = {}
    self.world = world

    -- Rules are applied at each step to deduce new knowledge
    self.rules = rules or List()

    -- Keep a history of all clauses
    self.story = {}

    -- Properties that are exclusive e.g. John is in the kitchen means that he
    -- is not in the bathroom.
    self.exclusive = Set()
end

function Knowledge:get_value_history(entity, property, resolve_location)
    local value_history = List{}
    local support_history = List{}
    local resolve_location = resolve_location or true
    for t = 1, self.t do -- Reverse order?
        local value, support =
            self.knowledge[t][entity]:get_value(property, true)
        if resolve_location and value and value.is_actor then
            local new_support
            value, new_support = self.knowledge[t][value]:get_value(property, true)
            if new_support then
                support = support + new_support
            end
        end
        if value and (#value_history == 0 or value_history[#value_history].name ~= value.name) then
            value_history:append(value)
            support_history:append(support)
        end
    end
    return value_history, support_history
end

function Knowledge:update(clause)
    self.t = self.t + 1
    local t = self.t

    self.story[t] = clause

    -- Copy the knowledge from the previous step Done in a complicated way
    -- because tablex.copy throws out all methods and metamethods it seems?
    self.knowledge[t] = KnowledgeTable(self)
    if t > 1 then
        for k, v in pairs(self.knowledge[t - 1]) do
            if k ~= 'knowledge' then
                self.knowledge[t][k] = EntityProperties(self)
                for l, w in pairs(self.knowledge[t - 1][k]) do
                    if l ~= 'knowledge' then
                        self.knowledge[t][k][l] = List(tablex.copy(self.knowledge[t - 1][k][l]))
                    end
                end
            end
        end
    end

    -- Apply clause
    if class.istype(clause, 'Rule') then
        self.rules:append(clause)
    else
        clause.action:update_knowledge(self.world, self.knowledge[t], clause,
                                       clause.actor, unpack(clause.args))
    end

    for _, rule in pairs(self.rules) do
        if rule:is_applicable(clause, self.knowledge[t], self.story) then
            rule:perform(self.world)
            rule:update_knowledge(self.world, self.knowledge[t], clause)
        end
    end
end

function Knowledge:current()
    return self.knowledge[self.t]
end

function Knowledge:describe(time)
    local log = List()
    local cknowledge = self.knowledge[time]
    for entity,ent_state in pairs(cknowledge) do
        -- Ignore the phantom "knowledge" entry
        if entity ~= 'knowledge' then
            log:append(entity.name .. ':\n')
            for relation,targets in pairs(ent_state) do
                -- Ignore the phantom "knowledge" entry
                if relation ~= 'knowledge' then 
                    log:append('\t' .. relation .. '[ ')
                    for _,target in pairs(targets) do
                        log:append(target.value.name .. '(' .. tostring(target.truth_value) .. '), ')
                    end
                    log:append(']\n')
                end
            end
        end
    end
    return log:join("")
end

function Knowledge:describe_all()
    local log = List()
    for t = 1, self.t do
        log:append(self:describe(t) .. '-------\n')
    end
    return log:join("")
end

function Knowledge:augment_with_value_histories(entities, property, resolve_location)
    for _, entity in pairs(entities) do
        local value_history = List{}
        local records = List{}

        for t = 1, self.t do -- Reverse order?
            local value, support =
                self.knowledge[t][entity]:get_value(property, true)
            if resolve_location and value and value.is_actor then
                local new_support
                value, new_support = self.knowledge[t][value]:get_value(property, true)
            end
            if value and (#value_history == 0 or value_history[#value_history].name ~= value.name) then
                value_history:append(value)
                local record_ent = Entity("record_" .. property .. "#" .. entity.name .. "_" .. tostring(#value_history),{})
                records:append(record_ent)
            end

            if #value_history > 0 then
                self.knowledge[t][entity]:set("history_now_"..property, records[#records], true, {})
                for i = 2,#value_history do
                    self.knowledge[t][records[i]]:set("prev", records[i-1], true, {})
                end
                for i = 1,#value_history do
                    self.knowledge[t][entity]:add("history_"..property, records[i], true, {})
                    self.knowledge[t][records[i]]:set("value", value_history[i], true, {})
                end
            end
        end
    end
end

function help_desc_type(thing)
    local has = List()
    local relevant_types = { 'actor', 'location', 'gettable', 'motivation', 'animal'}
    for _, t in pairs(relevant_types) do
        if thing['is_' .. t] then
            has:append(t)
        end
    end
    return has:join('-')
end

function Knowledge:describe_graph(time)
    local flip_key = { s="n", e="w" }

    local nodes = Set{}
    local edges = List()

    local cknowledge = self.knowledge[time]
    for entity,ent_state in pairs(cknowledge) do
        -- Ignore the phantom "knowledge" entry
        if entity ~= 'knowledge' then
            nodes = nodes + Set{entity.name}
            for relation,targets in pairs(ent_state) do
                -- Ignore the phantom "knowledge" entry
                if relation ~= 'knowledge' then 
                    for _,target in pairs(targets) do
                        nodes = nodes + Set{target.value.name}
                        local negate_prefix = ""
                        if not target.truth_value then
                            negate_prefix = "not_"
                        end

                        local from = entity
                        local to = target.value
                        if flip_key[relation] then
                            relation = flip_key[relation]
                            from = target.value
                            to = entity
                        end
                        local edgedesc = negate_prefix .. help_desc_type(from) .. '_' .. relation .. '_' .. help_desc_type(to)
                        edges:append('{ ' ..
                            '"type":"' .. edgedesc .. '",' ..
                            '"from":"' .. from.name .. '",' ..
                            '"to":"' .. to.name .. '"' ..
                            '}')
                    end
                end
            end
        end
    end
    return '{' ..
        '"nodes":["' .. List(Set.values(nodes)):join('","') ..'"],' ..
        '"edges":[' .. edges:join(',') ..']' ..
        '}'
end

return Knowledge
