local M = {}

local util = require("xcodebuild.util")

function M.refresh_diagnostics(bufnr, testClass, report)
	if not report.tests then
		return
	end

	local ns = vim.api.nvim_create_namespace("xcodebuild-diagnostics")
	local diagnostics = {}
	local duplicates = {}

	for _, test in ipairs(report.tests[testClass] or {}) do
		if
			not test.success
			and test.filepath
			and test.lineNumber
			and not duplicates[test.filepath .. test.lineNumber]
		then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = test.lineNumber - 1,
				col = 0,
				severity = vim.diagnostic.severity.ERROR,
				source = "xcodebuild",
				message = table.concat(test.message, "\n"),
				user_data = {},
			})
			duplicates[test.filepath .. test.lineNumber] = true
		end
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	vim.diagnostic.set(ns, bufnr, diagnostics, {})
end

function M.set_buf_marks(bufnr, testClass, tests)
	if not tests then
		return
	end

	local ns = vim.api.nvim_create_namespace("xcodebuild-marks")
	local successSign = "✔"
	local failureSign = "✖"
	local bufLines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local findTestLine = function(testName)
		for lineNumber, line in ipairs(bufLines) do
			if string.find(line, "func " .. testName .. "%(") then
				return lineNumber - 1
			end
		end

		return nil
	end

	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	for _, test in ipairs(tests[testClass] or {}) do
		local lineNumber = findTestLine(test.name)
		local mark = test.time and { "(" .. test.time .. ")", test.success and "DiagnosticWarn" or "DiagnosticError" }
			or { "" }

		if test.filepath and lineNumber then
			vim.api.nvim_buf_set_extmark(bufnr, ns, lineNumber, 0, {
				virt_text = { mark },
				sign_text = test.success and successSign or failureSign,
				sign_hl_group = test.success and "DiagnosticSignOk" or "DiagnosticSignError",
			})
		end
	end
end

function M.refresh_buf_diagnostics(report)
	if report.buildErrors and report.buildErrors[1] then
		return
	end

	local buffers = util.get_bufs_by_name_matching(".*/.*[Tt]est[s]?%.swift$")

	for _, buffer in ipairs(buffers or {}) do
		local testClass = util.get_filename(buffer.file)
		M.refresh_diagnostics(buffer.bufnr, testClass, report)
		M.set_buf_marks(buffer.bufnr, testClass, report.tests)
	end
end

return M
