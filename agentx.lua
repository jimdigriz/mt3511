-- SNMP AgentX Subagent
-- Copyright (C) 2023, coreMem Limited <info@coremem.com>
-- SPDX-License-Identifier: AGPL-3.0-only

-- https://datatracker.ietf.org/doc/html/rfc2741

local bit32 = require "bit32"
local socket = require "posix.sys.socket"
local poll = require "posix.poll"
local unistd = require "posix.unistd"
if socket.AF_PACKET == nil then error("AF_PACKET not available, did you install lua-posix 35.1 or later?") end
-- https://github.com/iryont/lua-struct
local status, struct = pcall(function () return require "struct" end)
if not status then
	struct = assert(loadfile(arg[0]:match("^(.-/?)[^/]+.lua$") .. "struct.lua"))()
end

local unpack = table.unpack or _G.unpack

local DEADTIME = 3
local MAXSIZE = 9000

local val = { enc = {}, dec = {} }

function val.enc.objectid (v, i)
	local prefix = 0
	if v[1] < 256 then
		prefix = v[1]
		table.remove(v)
	end

	local include = i and 1 or 0

	return struct.pack(">BBBB" .. string.rep("I", #v), #v, prefix, include, 0, unpack(v))
end

function val.enc.searchrange (s, e, i)
	return val.objectid(s, i) .. val.objectid(e)
end

function val.enc.octetstring (v)
	return struct.pack(">Ic0c0", v:len(), v, string.rep("\0", v:len() - (v:len() % 4)))
end

function val.enc.type ()
	error("nyi")
end

local pdu = {}

function pdu._hdr (type, payload, flags)
	flags = bit32.bor(flags and flags or 0x00, 0x0f)
	return struct.pack(">BBBBIIIIc0", 1, type, flags, 0, 0, 0, 0, payload:len(), payload)
end

-- https://datatracker.ietf.org/doc/html/rfc2741#section-6.2.1
function pdu.open ()
	return pdu._hdr(1, struct.pack(">B", DEADTIME) .. "\0\0\0" .. "\0\0\0\0" .. val.enc.octetstring("EBM"))
end

local M = {}

function M:session (t)
	t = t or {}

	setmetatable({ __gc = function() M:disconnect() end }, self)
	self.__index = self

	t.path = t.path or "/var/agentx/master"

	self._fd = assert(socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0))
	local ok, err, e = socket.connect(self._fd, { family=socket.AF_UNIX, path=t.path })
	if not ok then
		return nil, err
	end

	M:send(pdu.open())
	print(M:recv())

	return self
end

function M:disconnect ()
	if self._fd ~= nil then
		unistd.close(self_.fd)
		self._fd = nil
	end
end

function M:send (msg)
	assert(socket.send(self._fd, msg) == msg:len())
end

function M:recv ()
	local pkt = socket.recv(self._fd, MAXSIZE)
	return pkt
end

return M
