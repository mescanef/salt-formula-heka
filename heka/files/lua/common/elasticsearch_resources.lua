-- Copyright 2016 Mirantis, Inc.
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
local string = require "string"
local cjson = require "cjson"
local utils = require "lma_utils"
local table = require "table"
local pairs = pairs
local read_message = read_message
local utils = require "lma_utils"

local index = read_config("index") or "index"
local type_name = read_config("type_name") or "source"

local ResourceEncoder = {}
ResourceEncoder.__index = ResourceEncoder

setfenv(1, ResourceEncoder) -- Remove external access to contain everything in the module

function encode()
    local ns
    local resources = cjson.decode(read_message("Payload"))
    payload = {}
    for resource_id, resource in pairs(resources) do
        local update = cjson.encode({
            update = {_index = index, _type = type_name, _id = resource_id}
        })
        local body = {
            script = {
                source = 'def SDF = new SimpleDateFormat(\"yyyy-MM-dd\'T\'HH:mm:ss.SSSSSSXXX\"); ' ..
                         'ctx._source.meters.putAll(params.meter); ' ..
                         'ctx._source.user_id = params.user_id; ' ..
                         'ctx._source.project_id = params.project_id; ' ..
                         'ctx._source.source = params.source; ' ..
                         'ctx._source.metadata = ' ..
                         'SDF.parse(ctx._source.last_sample_timestamp).getTime() <= ' ..
                         'SDF.parse(params.timestamp).getTime() ? ' ..
                         'params.metadata : ctx._source.metadata; ' ..
                         'ctx._source.last_sample_timestamp = ' ..
                         'SDF.parse(ctx._source.last_sample_timestamp).getTime() < ' ..
                         'SDF.parse(params.timestamp).getTime() ? ' ..
                         'params.timestamp : ctx._source.last_sample_timestamp; ' ..
                         'ctx._source.first_sample_timestamp = ' ..
                         'SDF.parse(ctx._source.first_sample_timestamp).getTime() > ' ..
                         'SDF.parse(params.timestamp).getTime() ?' ..
                         'params.timestamp : ctx._source.first_sample_timestamp;',
                params = {
                    meter = resource.meter,
                    metadata = resource.metadata,
                    timestamp = resource.timestamp,
                    user_id = resource.user_id or '',
                    project_id = resource.project_id or '',
                    source = resource.source or '',
                }
            },
            upsert = {
                first_sample_timestamp = resource.timestamp,
                last_sample_timestamp = resource.timestamp,
                project_id = resource.project_id or '',
                user_id = resource.user_id or '',
                source = resource.source or '',
                metadata = resource.metadata,
                meters = resource.meter
            }
        }
        bulk_body = string.format("%s\n%s\n", update, cjson.encode(body))
        table.insert(payload, bulk_body)
    end
    return 0, table.concat(payload)
end

return ResourceEncoder