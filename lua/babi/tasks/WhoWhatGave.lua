-- Copyright (c) 2015-present, Facebook, Inc.
-- All rights reserved.
--
-- This source code is licensed under the BSD-style license found in the
-- LICENSE file in the root directory of this source tree. An additional grant
-- of patent rights can be found in the PATENTS file in the same directory.

local class = require 'class'

local Set = require 'pl.Set'

local actions = require 'babi.actions'
local Task = require 'babi.Task'
local World = require 'babi.World'
local Question = require 'babi.Question'
local Clause = require 'babi.Clause'
local utilities = require 'babi.utilities'

local WhoWhatGave = class('WhoWhatGave', 'Task')

function WhoWhatGave:new_world()
    local world = World()
    world:load((BABI_HOME or '') .. 'tasks/worlds/world_basic.txt')
    return world
end

local function sample_clause(world)
    local allowed_actions = {actions.get, actions.give, actions.teleport}

    local clause
    while not clause do
        local random_action =
            allowed_actions[math.random(#allowed_actions)]
        if class.istype(random_action, 'Teleport') then
            clause = Clause.sample_valid(
                world, {true}, world:get_actors(),
                {actions.teleport}, world:get_locations()
            )
        elseif class.istype(random_action, 'Get') then
            clause = Clause.sample_valid(
                world, {true}, world:get_actors(),
                {actions.get}, world:get_objects()
            )
        else
            clause = Clause.sample_valid(
                world, {true}, world:get_actors(),
                {actions.give}, world:get_objects(), world:get_actors()
            )
        end
    end
    return clause
end

function WhoWhatGave:generate_story(world, knowledge, story)
    local num_questions = 0
    local story_length = 0

    while num_questions < 5 do
        local clause = sample_clause(world)
        story_length = story_length + 1
        clause:perform()
        story:append(clause)
        knowledge:update(clause)
        if story_length > 1 and class.istype(clause.action, 'Give') then
            -- we don't want the clause the question is about to be the most
            -- recent one, so sample a few more unrelated clauses first
            for i = 2, math.random(6) do -- 0 to 5 extra clauses
                local cls
                -- don't use any more stories about the same item, or
                -- about the same people exchanging any other item
                while not cls or cls.args[1] == clause.args[1] or
                (
                    cls.actor == clause.actor and
                    class.istype(cls.action, 'Give') and
                    cls.args[2] == clause.args[2]
                ) do
                    cls = sample_clause(world)
                end
                cls:perform()
                story:append(cls)
                knowledge:update(cls)
            end
            story:append(Question('eval', clause, Set{clause}))
            num_questions = num_questions + 1
            story_length = 0
        end
    end

    knowledge:augment_with_value_histories(world:get_objects(), 'is_in', false)
    return story, knowledge
end

return WhoWhatGave
