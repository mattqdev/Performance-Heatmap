--!strict
-- Version.luau
-- Unica fonte di verità per la versione del plugin (incorporata in ogni build).
-- Ad ogni release: aggiorna `Version.current` QUI e il campo "version" in
-- version.json alla radice del repo (servito da GitHub raw all'UpdateChecker).

local Version = {}

Version.current = "1.0.0"

-- Trasforma una stringa semver ("1.2.3") in { major, minor, patch }.
function Version.parse(str: string): { number }
	local parts = {}
	for n in string.gmatch(str or "", "%d+") do
		table.insert(parts, tonumber(n) or 0)
	end
	return { parts[1] or 0, parts[2] or 0, parts[3] or 0 }
end

-- Confronta due versioni. Ritorna 1 se a > b, -1 se a < b, 0 se uguali.
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

-- true se `remote` è più recente di `localVersion`.
function Version.isNewer(remote: string, localVersion: string): boolean
	return Version.compare(remote, localVersion) > 0
end

return Version
