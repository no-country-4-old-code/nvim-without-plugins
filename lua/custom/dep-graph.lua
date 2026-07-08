local M = {}

function M.setup()
	local script = vim.fn.stdpath("config") .. "/scripts/cdeps.sh"

	local function run(mode)
		local root = vim.fs.root(0, ".git") or vim.fn.getcwd()
		vim.system({ "bash", script, mode, root }, { text = true }, function(o)
			vim.schedule(function()
				if o.code ~= 0 then
					vim.notify(
						"cdeps failed:\n" .. (o.stderr or "(no output)"),
						vim.log.levels.ERROR,
						{ title = "C/C++ dep graph" }
					)
				else
					vim.notify(o.stdout or "done", vim.log.levels.INFO, { title = "C/C++ dep graph" })
				end
			end)
		end)
	end

	vim.api.nvim_create_user_command("CDeps", function()
		run("--folders")
	end, { desc = "Render C/C++ folder dependency graph (SVG)" })

	vim.api.nvim_create_user_command("CDepsFiles", function()
		run("--files")
	end, { desc = "Render C/C++ file dependency graph (SVG)" })
end

return M
