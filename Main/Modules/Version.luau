--!strict
-- Version.luau
-- Single source of truth for the plugin's version (baked into every build).
-- On each release: bump `Version.current` HERE and the "version" field in
-- version.json at the repo root (served by GitHub raw to the UpdateChecker).

local Version = {}

Version.current = "1.0.0"

-- Turns a semver string ("1.2.3") into { major, minor, patch }.
function Version.parse(str: string): { number }
	local parts = {}
	for n in string.gmatch(str or "", "%d+") do
		table.insert(parts, tonumber(n) or 0)
	end
	return { parts[1] or 0, parts[2] or 0, parts[3] or 0 }
end

-- Compares two versions. Returns 1 if a > b, -1 if a < b, 0 if equal.
function Version.compare(a: string, b: string): number
	local pa, pb = Version.parse(a), Version.parse(b)
	for i = 1, 3 do
		if pa[i] > pb[i] then
			return 1
		elseif pa[i] < pb[i] then
			return -1
		end
	end
	return 0
end

-- true if `remote` is newer than `localVersion`.
function Version.isNewer(remote: string, localVersion: string): boolean
	return Version.compare(remote, localVersion) > 0
end

return Version
