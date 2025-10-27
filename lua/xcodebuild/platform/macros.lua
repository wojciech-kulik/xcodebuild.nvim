---@mod xcodebuild.platform.macros Swift Macro Management
---@brief [[
---This module is responsible for managing Swift macro approvals.
---
---It handles parsing macro errors from build logs, reading/writing
---the macros.json file, and resolving package fingerprints from Package.resolved.
---
---The macros.json file is located at:
---  ~/Library/org.swift.swiftpm/security/macros.json
---
---It contains an array of approved macros with their fingerprints (revision hashes or checksum):
---
--->json
---  [
---    {
---      "fingerprint": "abc123...",
---      "packageIdentity": "swift-dependencies",
---      "targetName": "DependenciesMacrosPlugin"
---    }
---  ]
---<
---@brief ]]

---@class MacroError
---@field targetName string macro target name (e.g., "StructuredQueriesMacros")
---@field packageIdentity string package identity (e.g., "swift-structured-queries")
---@field message string full error message

---@class ApprovedMacro
---@field fingerprint string revision hash or checksum from Package.resolved
---@field packageIdentity string package identity
---@field targetName string macro target name

local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")
local projectConfig = require("xcodebuild.project.config")

---@class MacrosModule
---@field has_unapproved_macros fun(): boolean
---@field get_unapproved_macros fun(): MacroError[]
---@field parse_macro_errors fun(buildErrors: table): MacroError[]
local M = {}

local MACROS_JSON_PATH = vim.fn.expand("~/Library/org.swift.swiftpm/security/macros.json")

---Reads the macros.json file.
---@return ApprovedMacro[]
function M.read_macros_json()
  if not util.file_exists(MACROS_JSON_PATH) then
    return {}
  end

  local success, content = util.readfile(MACROS_JSON_PATH)
  if not success then
    return {}
  end

  local ok, macros = pcall(vim.fn.json_decode, content)
  if not ok then
    notifications.send_error("Failed to parse macros.json")
    return {}
  end

  return macros or {}
end

---Writes the macros.json file.
---@param macros ApprovedMacro[]
---@return boolean success
function M.write_macros_json(macros)
  local dir = vim.fn.fnamemodify(MACROS_JSON_PATH, ":h")
  if not util.file_exists(dir) then
    vim.fn.mkdir(dir, "p")
  end

  local json = vim.fn.json_encode(macros)
  local formattedJson = vim.split(json, "\n", { plain = true })

  local success = pcall(vim.fn.writefile, formattedJson, MACROS_JSON_PATH)
  if not success then
    notifications.send_error("Failed to write macros.json")
    return false
  end

  return true
end

---Parses macro approval errors from build errors.
---Uses the isMacroError flag that the parser already set.
---@param buildErrors ParsedBuildError[]|ParsedBuildGenericError[]
---@return MacroError[]
function M.parse_macro_errors(buildErrors)
  local macroErrors = {}
  local seen = {}

  for _, error in ipairs(buildErrors) do
    -- Use the fields that the parser already set (no need to re-parse the message)
    if error.isMacroError and error.macroName and error.packageIdentity then
      local key = error.packageIdentity .. "/" .. error.macroName
      if not seen[key] then
        table.insert(macroErrors, {
          targetName = error.macroName,
          packageIdentity = error.packageIdentity,
          message = error.message and error.message[1] or "",
        })
        seen[key] = true
      end
    end
  end

  return macroErrors
end

---Reads Package.resolved to get package information including fingerprint.
---@param packageIdentity string
---@return {version: string|nil, revision: string|nil, checksum: string|nil}|nil
local function get_package_info(packageIdentity)
  local workingDir = projectConfig.settings.workingDirectory or vim.fn.getcwd()
  local packageResolved = workingDir .. "/Package.resolved"

  -- For Xcode projects, also check inside the .xcodeproj
  if not util.file_exists(packageResolved) and projectConfig.settings.projectFile then
    packageResolved = projectConfig.settings.projectFile
      .. "/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
  end

  if not util.file_exists(packageResolved) then
    -- Try .build/workspace-state.json for SPM projects
    local workspaceState = workingDir .. "/.build/workspace-state.json"
    if not util.file_exists(workspaceState) then
      return nil
    end

    local success, content = util.readfile(workspaceState)
    if not success then
      return nil
    end

    local ok, data = pcall(vim.fn.json_decode, content)
    if not ok or not data.object or not data.object.dependencies then
      return nil
    end

    for _, dep in ipairs(data.object.dependencies) do
      if dep.packageRef and dep.packageRef.identity == packageIdentity then
        if dep.state then
          return {
            version = dep.state.version,
            revision = dep.state.revision,
            checksum = dep.state.checksum,
          }
        end
      end
    end

    return nil
  end

  -- Parse Package.resolved
  local success, content = util.readfile(packageResolved)
  if not success then
    return nil
  end

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok or not data.pins then
    return nil
  end

  for _, pin in ipairs(data.pins) do
    if pin.identity == packageIdentity then
      if pin.state then
        return {
          version = pin.state.version,
          revision = pin.state.revision,
          checksum = pin.state.checksum,
        }
      end
    end
  end

  return nil
end

---Gets the fingerprint for a package from Package.resolved.
---The fingerprint is the revision (SHA-1 hash) or checksum from the package's state.
---@param packageIdentity string
---@return string|nil fingerprint
function M.get_fingerprint(packageIdentity)
  local packageInfo = get_package_info(packageIdentity)

  if not packageInfo then
    return nil
  end

  if type(packageInfo.revision) == "string" and packageInfo.revision ~= "" then
    -- The revision IS the fingerprint
    return packageInfo.revision
  end

  if type(packageInfo.checksum) == "string" and packageInfo.checksum ~= "" then
    return packageInfo.checksum
  end

  return nil
end

---Approves macros by adding or updating them in macros.json.
---@param macrosToApprove MacroError[]
---@return boolean success
function M.approve_macros(macrosToApprove)
  if util.is_empty(macrosToApprove) then
    return true
  end

  local currentMacros = M.read_macros_json()
  local updatedCount = 0

  for _, macroError in ipairs(macrosToApprove) do
    local fingerprint = M.get_fingerprint(macroError.packageIdentity)

    if not fingerprint then
      notifications.send_error(
        "Could not find package '"
          .. macroError.packageIdentity
          .. "' in Package.resolved. Build the project first."
      )
      return false
    else
      -- Check if macro already exists
      local found = false
      for i, macro in ipairs(currentMacros) do
        if
          macro.packageIdentity == macroError.packageIdentity and macro.targetName == macroError.targetName
        then
          -- Update existing fingerprint if it changed
          if macro.fingerprint ~= fingerprint then
            currentMacros[i].fingerprint = fingerprint
            updatedCount = updatedCount + 1
          end
          found = true
          break
        end
      end

      -- Add new macro if not found
      if not found then
        table.insert(currentMacros, {
          fingerprint = fingerprint,
          packageIdentity = macroError.packageIdentity,
          targetName = macroError.targetName,
        })
        updatedCount = updatedCount + 1
      end
    end
  end

  if updatedCount == 0 then
    notifications.send("No changes needed - macros are already approved with current fingerprints")
    return true
  end

  local success = M.write_macros_json(currentMacros)
  if success then
    notifications.send("✓ Approved " .. updatedCount .. " macro(s)")
  end

  return success
end

---Finds the DerivedData path for the current project.
---@return string|nil
local function find_project_derived_data()
  local buildDir = projectConfig.settings.buildDir

  if buildDir then
    local derivedDataPath = string.match(buildDir, "(.+/DerivedData/[^/]+)")
    if derivedDataPath and util.dir_exists(derivedDataPath) then
      return derivedDataPath
    end
  end

  local productName = projectConfig.settings.productName
  local workingDirectory = projectConfig.settings.workingDirectory

  if productName and workingDirectory then
    local xcode = require("xcodebuild.core.xcode")
    local derivedDataPath = xcode.find_derived_data_path(productName, workingDirectory)
    if derivedDataPath then
      return derivedDataPath
    end
  end

  local derivedDataDir = vim.fn.expand("~/Library/Developer/Xcode/DerivedData")
  if not util.dir_exists(derivedDataDir) then
    return nil
  end

  local projectFile = projectConfig.settings.projectFile or projectConfig.settings.swiftPackage
  if not projectFile then
    return nil
  end

  local projectName = vim.fn.fnamemodify(projectFile, ":t:r")
  local pattern = derivedDataDir .. "/" .. projectName .. "-*"
  local dirs = vim.fn.glob(pattern, false, true)

  if #dirs == 0 then
    return nil
  end

  table.sort(dirs, function(a, b)
    return vim.fn.getftime(a) > vim.fn.getftime(b)
  end)

  return dirs[1]
end

---Finds the package checkout directory in DerivedData.
---@param packageIdentity string
---@return string|nil
local function find_package_checkout_dir(packageIdentity)
  if not packageIdentity then
    return nil
  end

  local derivedDataPath = find_project_derived_data()
  if not derivedDataPath then
    return nil
  end

  local checkoutsDir = derivedDataPath .. "/SourcePackages/checkouts"
  if not util.dir_exists(checkoutsDir) then
    return nil
  end

  local normalizedIdentity = packageIdentity:lower():gsub("[^a-z0-9]", "")

  local dirs = vim.fn.glob(checkoutsDir .. "/*", false, true)
  for _, dir in ipairs(dirs) do
    local dirName = vim.fn.fnamemodify(dir, ":t"):lower():gsub("[^a-z0-9]", "")
    if dirName:find(normalizedIdentity, 1, true) or normalizedIdentity:find(dirName, 1, true) then
      return dir
    end
  end

  return nil
end

---Finds the source files for a macro target.
---@param packageIdentity string
---@param targetName string
---@return string[]|nil
function M.find_macro_source_files(packageIdentity, targetName)
  local checkoutDir = find_package_checkout_dir(packageIdentity)
  if not checkoutDir then
    return nil
  end

  local sourcesDir = checkoutDir .. "/Sources/" .. targetName
  if not util.dir_exists(sourcesDir) then
    return nil
  end

  -- Recursively search for Swift files in all subdirectories
  local files = vim.fn.glob(sourcesDir .. "/**/*.swift", false, true)
  if #files == 0 then
    return nil
  end

  -- Sort files prioritizing macro-related files and directories
  table.sort(files, function(a, b)
    local aFileName = vim.fn.fnamemodify(a, ":t"):lower()
    local bFileName = vim.fn.fnamemodify(b, ":t"):lower()
    local aPath = a:lower()
    local bPath = b:lower()

    -- Check if filename contains "macro" or is in a "macros" directory
    local aHasMacro = aFileName:find("macro", 1, true) ~= nil or aPath:find("/macros/", 1, true) ~= nil
    local bHasMacro = bFileName:find("macro", 1, true) ~= nil or bPath:find("/macros/", 1, true) ~= nil

    if aHasMacro and not bHasMacro then
      return true
    elseif not aHasMacro and bHasMacro then
      return false
    end

    return a < b
  end)

  return files
end

---Opens the first macro source file in the editor.
---@param macroError MacroError
function M.open_macro_source(macroError)
  local files = M.find_macro_source_files(macroError.packageIdentity, macroError.targetName)

  if not files or #files == 0 then
    notifications.send_warning(
      "Could not find source files for " .. macroError.packageIdentity .. "/" .. macroError.targetName
    )
    return
  end

  vim.cmd("hide edit " .. vim.fn.fnameescape(files[1]))
  notifications.send("Opened: " .. vim.fn.fnamemodify(files[1], ":t"))
end

---Checks if the last build report contains unapproved macros.
---This helper avoids emitting notifications, so it can be used in UI probes.
---@return boolean
function M.has_unapproved_macros()
  local appdata = require("xcodebuild.project.appdata")
  local report = appdata.report

  if not report or util.is_empty(report.buildErrors) then
    return false
  end

  local macroErrors = M.parse_macro_errors(report.buildErrors)
  return util.is_not_empty(macroErrors)
end

---Gets unapproved macros from the last build report.
---@return MacroError[]
function M.get_unapproved_macros()
  local appdata = require("xcodebuild.project.appdata")

  if not appdata.report then
    notifications.send_warning("No build report found. Please run a build first.")
    return {}
  end

  if util.is_empty(appdata.report.buildErrors) then
    notifications.send_warning("No build errors found in the last build.")
    return {}
  end

  local macroErrors = M.parse_macro_errors(appdata.report.buildErrors)

  if util.is_empty(macroErrors) then
    notifications.send_warning(
      "Found " .. #appdata.report.buildErrors .. " build errors, but none are macro approval errors."
    )
  end

  return macroErrors
end

return M
