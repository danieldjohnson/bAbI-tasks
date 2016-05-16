-- Copyright (c) 2015-present, Facebook, Inc.
-- All rights reserved.
--
-- This source code is licensed under the BSD-style license found in the
-- LICENSE file in the root directory of this source tree. An additional grant
-- of patent rights can be found in the PATENTS file in the same directory.


local class = require 'class'

local List = require 'pl.List'
local Set = require 'pl.Set'

local actions = require 'babi.actions'
local Task = require 'babi.Task'
local World = require 'babi.World'
local Question = require 'babi.Question'
local Clause = require 'babi.Clause'

local OPPOSITE_DIRECTIONS = {n='s', ne='sw', e='w', se='nw', s='n',
                             sw='ne', w='e', nw='se', u='d', d='u'}

local IsDir = class('IsDir', 'Task')

function IsDir:new_world()
    local world = World()

    -- Pick three random locations
    local options = {'bedroom', 'bathroom', 'kitchen',
                     'office', 'garden', 'hallway'}
    local locations = List()
    while #locations < 3 do
        local option = options[math.random(#options)]
        if not world.entities[option] then
            local location = world:create_entity(option, {is_location = true})
            locations:append(location)
        end
    end

    -- Choose the direction in which the locations wlil be ordered
    local direction = ({'n', 'e'})[math.random(2)]
    for i = 1, 3 do
        world:perform_action('set_pos', world:god(), locations[i],
                             direction == 'e' and (i - 2) or 0,
                             direction == 'n' and (i - 2) or 0)
        if i > 1 then
            world:perform_action('set_dir', world:god(), locations[i - 1],
                                 direction, locations[i])
        end
    end
    self.locations = locations
    self.dir = direction
    return world
end

function IsDir:generate_story(world, knowledge, story)
    -- Inform the reader of the two relations
    story[1] = Clause(world, true, world:god(), actions.set, self.locations[1],
                      self.dir, self.locations[2])
    story[2] = Clause(world, true, world:god(), actions.set, self.locations[2],
                      self.dir, self.locations[3])

    -- Give the information in either order
    local swap = math.random(2)
    if swap > 1 then
        story[1], story[2] = story[2], story[1]
    end

    -- Ask about one of the two relations
    local ask_dir = ({self.dir, OPPOSITE_DIRECTIONS[self.dir]})[math.random(2)]
    local ask_location = self.dir == ask_dir and 3 or 1

    -- Keep track of which of the two statements supports this
    local supporting_fact = math.min(ask_location, 2)
    supporting_fact = swap > 1 and supporting_fact % 2 + 1 or supporting_fact

    -- Ask the question
    story[3] = Question(
        'eval',
        Clause(world, true, world:god(), actions.set, self.locations[2],
               ask_dir, self.locations[ask_location]),
        Set{story[supporting_fact]}
    )

    for i = 1, #story do
        if not class.istype(story[i], 'Question') then
            story[i]:perform()
            knowledge:update(story[i])
        end
    end
    return story, knowledge
end

return IsDir
