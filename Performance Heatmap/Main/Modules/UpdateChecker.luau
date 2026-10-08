--!strict
-- UpdateChecker.luau
-- Fetches the latest published version from version.json (GitHub raw) and
-- compares it with the locally baked version (Version.current).
-- Fully guarded: any network or parsing error returns a non-fatal result,
-- so the plugin still loads.

local HttpService = game:GetService("HttpService")
local Version = require(script.Parent.Version)

local UpdateChecker = {}

-- Raw JSON on GitHub. Update the branch/path if the repo layout changes.
UpdateChecker.VERSION_URL =
	"https://raw.githubusercontent.com/mattqdev/Performance-Heatmap/main/version.json"

export type Result = {
	ok: boolean,             -- the check succeeded (network + parsing)
	updateAvailable: boolean,
	current: string,
	latest: string?,
	url: string?,
	notes: string?,
	error: string?,
}

-- Runs the check. Yields for the HTTP request: call it inside a task.spawn
-- so it doesn't block the plugin's loading.
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
			error = "version.json malformed or unreachable",
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
