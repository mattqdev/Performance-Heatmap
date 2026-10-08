--!strict
-- Format.luau -- shared formatting for the numbers shown in the results list.
--
-- The `Amount` field of a finding is display text and nothing else: it is never
-- parsed, and ordering always comes from the numeric `Sort`. This module exists
-- so three analyzers don't each carry their own copy of the same helper.

local Format = {}

-- 12345 -> "12,345". Counts only; negatives are not a case that occurs here.
function Format.thousands(n: number): string
	local digits  = tostring(math.floor(n + 0.5))
	local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (grouped:gsub("^,", ""))
end

-- "1 draw call" / "2 draw calls"
function Format.plural(n: number, singular: string, plural: string?): string
	local word = (n == 1) and singular or (plural or (singular .. "s"))
	return string.format("%d %s", n, word)
end

return Format
