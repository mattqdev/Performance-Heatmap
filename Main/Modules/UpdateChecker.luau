--!strict
-- UpdateChecker.luau
-- Scarica l'ultima versione pubblicata da version.json (GitHub raw) e la
-- confronta con la versione locale incorporata (Version.current).
-- Tutto protetto: qualsiasi errore di rete o di parsing ritorna un risultato
-- non fatale, così il plugin si carica comunque.

local HttpService = game:GetService("HttpService")
local Version = require(script.Parent.Version)

local UpdateChecker = {}

-- JSON grezzo su GitHub. Aggiorna branch/percorso se cambia il layout del repo.
UpdateChecker.VERSION_URL =
	"https://raw.githubusercontent.com/mattqdev/Performance-Heatmap/main/version.json"

export type Result = {
	ok: boolean,             -- il check è andato a buon fine (rete + parsing)
	updateAvailable: boolean,
	current: string,
	latest: string?,
	url: string?,
	notes: string?,
	error: string?,
}

-- Esegue la verifica. Cede (yield) per la richiesta HTTP: chiamalo dentro un
-- task.spawn per non bloccare il caricamento del plugin.
function UpdateChecker.check(): Result
	local current = Version.current

	local ok, body = pcall(function()
		return HttpService:GetAsync(UpdateChecker.VERSION_URL)
	end)
	if not ok then
		return { ok = false, updateAvailable = false, current = current, error = tostring(body) }
	end

	local decoded
	local decodedOk = pcall(function()
		decoded = HttpService:JSONDecode(body)
	end)
	if not decodedOk or type(decoded) ~= "table" or type(decoded.version) ~= "string" then
		return {
			ok = false,
			updateAvailable = false,
			current = current,
			error = "version.json malformato o irraggiungibile",
		}
	end

	return {
		ok = true,
		updateAvailable = Version.isNewer(decoded.version, current),
		current = current,
		latest = decoded.version,
		url = decoded.url,
		notes = decoded.notes,
	}
end

return UpdateChecker
