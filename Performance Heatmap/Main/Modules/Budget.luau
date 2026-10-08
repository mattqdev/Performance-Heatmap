-- Budget.luau
-- Cooperative time-slicing + cancellation for long scans.
--
-- Every loop that walks the place must call `budget:step()` on each item. When
-- the current slice of work runs out, `step` yields for a frame so Studio stays
-- responsive, and reports progress on the way out. `step` returns false once the
-- scan has been cancelled, which is the caller's cue to bail immediately.

local Budget = {}
Budget.__index = Budget

-- Seconds of work per frame. ~8ms leaves the rest of the frame to Studio; going
-- higher makes scans marginally faster but visibly stutters the viewport.
local DEFAULT_SLICE = 0.008

-- onProgress(label, done, total) -- total is 0 when the phase length is unknown
function Budget.new(onProgress)
	return setmetatable({
		slice       = DEFAULT_SLICE,
		_onProgress = onProgress,
		_mark       = os.clock(),
		_cancelled  = false,
		_label      = "",
		_done       = 0,
		_total      = 0,
	}, Budget)
end

function Budget:cancel()
	self._cancelled = true
end

function Budget:cancelled()
	return self._cancelled
end

function Budget:_report()
	if self._onProgress then
		-- a bad progress callback must never take the scan down with it
		pcall(self._onProgress, self._label, self._done, self._total)
	end
end

-- Starts a new phase. `total` is the expected item count, or nil when unknown.
function Budget:setPhase(label, total)
	self._label = label
	self._total = total or 0
	self._done  = 0
	self:_report()
end

-- Accounts for `n` processed items (default 1) and yields if the slice is spent.
-- Returns false when the scan has been cancelled.
function Budget:step(n)
	self._done += n or 1

	if os.clock() - self._mark >= self.slice then
		self:_report()
		task.wait()
		self._mark = os.clock()
	end

	return not self._cancelled
end

return Budget
