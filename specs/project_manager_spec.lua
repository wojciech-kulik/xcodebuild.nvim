---@diagnostic disable: duplicate-set-field

-- Mocks 3rd party dependencies
package.loaded["telescope.pickers"] = {}
package.loaded["telescope.finders"] = {}
package.loaded["telescope.actions"] = {}
package.loaded["telescope.config"] = {}
package.loaded["telescope.actions.state"] = {}
package.loaded["telescope.actions.utils"] = {}
package.loaded["telescope.themes"] = {}

local assert = require("luassert")
local manager = require("xcodebuild.project.manager")
local util = require("xcodebuild.util")
local cwd = vim.fn.getcwd()
local pickerReceivedItems = nil
local pickerShown = false
local projectRoot = cwd .. "/specs/tmp/XcodebuildNvimApp/"

---@param filepath string
local function setFilePath(filepath)
  vim.fn.expand = function(param)
    if string.find(param, ":h:h") then
      return vim.fn.fnamemodify(filepath, ":h:h")
    elseif string.find(param, ":h") then
      return vim.fn.fnamemodify(filepath, ":h")
    else
      return filepath
    end
  end
end

---@param groupName string
---@param expectedResult boolean|nil
local function assertGroupInProject(groupName, expectedResult)
  local lines = vim.fn.readfile(projectRoot .. "XcodebuildNvimApp.xcodeproj/project.pbxproj")
  local found = false
  local expectedLines = {
    "path = " .. groupName .. ";",
    'sourceTree = "<group>";',
  }

  for i = 1, #lines do
    if
      string.find(lines[i], expectedLines[1], 1, true)
      and string.find(lines[i + 1], expectedLines[2], 1, true)
    then
      found = true
      break
    end
  end

  if expectedResult == nil then
    expectedResult = true
  end
  assert.are.equal(expectedResult, found)
end

---@param filepath string
---@param targets string[]|nil
local function assertFileInProject(filepath, targets)
  setFilePath(filepath)
  manager.show_current_file_targets()
  assert.are.same(targets or { "XcodebuildNvimApp" }, pickerReceivedItems)
end

local function mock()
  require("xcodebuild.helpers").validate_project = function()
    return true
  end

  util.shell("rm -rf specs/tmp")
  util.shell("cp -r specs/test_project specs/tmp")

  require("xcodebuild.project.config").settings.xcodeproj = projectRoot .. "XcodebuildNvimApp.xcodeproj"
  require("xcodebuild.core.config").options.logs.notify = function(_, _) end
  require("xcodebuild.core.config").options.project_manager.guess_target = true

  require("xcodebuild.ui.pickers").show = function(_, list, callback, _)
    pickerReceivedItems = list
    pickerShown = true

    if callback then
      callback({ list[1] })
      vim.bo.filetype = "TelescopePrompt"
      vim.api.nvim_exec_autocmds("BufWinLeave", {})
    end
  end

  pickerShown = false
  pickerReceivedItems = {}

  local originalVimCmd = vim.cmd
  vim.cmd = function(cmd)
    if not vim.startswith(cmd, "b") and not vim.startswith(cmd, "e") then
      originalVimCmd(cmd)
    end
  end

  vim.notify = function(_, _) end
end

-------------------------------------------------------------------------
-------------------------------------------------------------------------

describe("ensure", function()
  before_each(function()
    mock()
  end)

  after_each(function()
    util.shell("rm -rf specs/tmp")
  end)

  ----------------
  --- TARGETS ----
  ----------------

  describe("get_project_targets", function()
    it("THEN returns all targets", function()
      local targets = manager.get_project_targets()
      assert.are.same(targets, {
        "XcodebuildNvimApp",
        "XcodebuildNvimAppTests",
        "XcodebuildNvimAppUITests",
        "Helpers",
        "EmptyTarget",
      })
    end)
  end)

  describe("update_current_file_targets", function()
    before_each(function()
      setFilePath(projectRoot .. "XcodebuildNvimApp/Modules/Main/MainViewModel.swift")
      require("xcodebuild.ui.pickers").show = function(_, items, callback, _)
        pickerReceivedItems = items
        if callback then
          callback({ "XcodebuildNvimApp", "XcodebuildNvimAppTests" })
        end
      end
      manager.update_current_file_targets()
    end)

    it("THEN updates xcodeproj", function()
      assertFileInProject(
        projectRoot .. "XcodebuildNvimApp/Modules/Main/MainViewModel.swift",
        { "XcodebuildNvimApp", "XcodebuildNvimAppTests" }
      )
    end)
  end)

  describe("show_current_file_targets", function()
    before_each(function()
      setFilePath(projectRoot .. "XcodebuildNvimApp/Modules/Main/MainViewModel.swift")
      manager.show_current_file_targets()
    end)

    it("THEN shows current file targets", function()
      assert.are.same({ "XcodebuildNvimApp" }, pickerReceivedItems)
    end)
  end)

  describe("guess_target", function()
    describe("WHEN the group contains Swift files", function()
      local targets

      before_each(function()
        targets = manager.guess_target(projectRoot .. "XcodebuildNvimApp/Modules/Main")
      end)

      it("THEN returns a target", function()
        assert.are_same({ "XcodebuildNvimApp" }, targets)
      end)
    end)

    describe("WHEN the group does not exist", function()
      local targets

      before_each(function()
        setFilePath(projectRoot .. "XcodebuildNvimApp/Modules/Main/ContentView.swift")
        manager.add_file_to_targets(
          projectRoot .. "XcodebuildNvimApp/Modules/Main/ContentView.swift",
          { "XcodebuildNvimApp", "XcodebuildNvimAppTests" }
        )
        targets = manager.guess_target(projectRoot .. "XcodebuildNvimApp/Modules/SomeNewGroup")
      end)

      it("THEN returns targets for a file from the common existing group", function()
        assert.are_same({ "XcodebuildNvimApp", "XcodebuildNvimAppTests" }, targets)
      end)
    end)

    describe("WHEN the group does not contain Swift files", function()
      local targets

      before_each(function()
        setFilePath(projectRoot .. "XcodebuildNvimApp/XcodebuildNvimApp.swift")
        manager.add_file_to_targets(
          projectRoot .. "XcodebuildNvimApp/XcodebuildNvimApp.swift",
          { "XcodebuildNvimApp", "XcodebuildNvimAppTests" }
        )
        targets = manager.guess_target(projectRoot .. "XcodebuildNvimApp/Preview Content")
      end)

      it("THEN returns targets for a file from the parent group", function()
        assert.are_same({ "XcodebuildNvimApp", "XcodebuildNvimAppTests" }, targets)
      end)
    end)

    describe("WHEN the group is target root without Swift files", function()
      local targets

      before_each(function()
        targets = manager.guess_target(projectRoot .. "Helpers")
      end)

      it("THEN returns target for a file in a nested group", function()
        assert.are_same({ "Helpers" }, targets)
      end)
    end)

    describe("WHEN the group is project root", function()
      local targets

      before_each(function()
        targets = manager.guess_target(projectRoot)
      end)

      it("THEN returns empty list", function()
        assert.are_equal(0, #targets)
      end)
    end)

    describe("WHEN the target has no Swift files", function()
      local targets

      before_each(function()
        targets = manager.guess_target(projectRoot .. "EmptyTarget")
      end)

      it("THEN returns empty list", function()
        assert.are_equal(0, #targets)
      end)
    end)
  end)

  ----------------
  ----- FILES ----
  ----------------

  -- New file operations with guessing target

  describe("add_file", function()
    describe("WHEN guessing target is enabled", function()
      describe("AND group does not exist", function()
        local newFilePath = projectRoot .. "Helpers/Modules/NewModule/new_file2.swift"
        local callbackCalled = false

        before_each(function()
          manager.add_file(newFilePath, function()
            callbackCalled = true
          end, { createGroups = true })
        end)

        it("THEN the target is correctly guessed and added", function()
          assert.is_false(pickerShown)
          assert.is_true(callbackCalled)
          assertFileInProject(newFilePath, { "Helpers" })
          assertGroupInProject("NewModule")
        end)
      end)

      describe("AND guessing is not possible", function()
        local newFilePath = projectRoot .. "EmptyTarget/NewModule/new_file2.swift"
        local callbackCalled = false

        before_each(function()
          manager.add_file(newFilePath, function()
            callbackCalled = true
          end, { createGroups = true })
        end)

        it("THEN the target is set based on picker selection", function()
          assert.is_true(callbackCalled)
          assert.is_true(pickerShown)
          assert.are_same({
            "XcodebuildNvimApp",
            "XcodebuildNvimAppTests",
            "XcodebuildNvimAppUITests",
            "Helpers",
            "EmptyTarget",
          }, pickerReceivedItems)
          assertFileInProject(newFilePath, { "XcodebuildNvimApp" })
          assertGroupInProject("NewModule")
        end)
      end)
    end)

    describe("WHEN only one target is returned", function()
      local newFilePath = projectRoot .. "Helpers/NewModule/new_file2.swift"
      local callbackCalled = false
      local originalShell = util.shell

      before_each(function()
        util.shell = function(_)
          util.shell = originalShell
          return { "Failure", "Helpers" }
        end
        manager.add_file(newFilePath, function()
          callbackCalled = true
        end, { createGroups = true })
      end)

      it("THEN the target is set automatically", function()
        assert.is_false(pickerShown)
        assert.is_true(callbackCalled)
        assertFileInProject(newFilePath, { "Helpers" })
        assertGroupInProject("NewModule")
      end)
    end)

    describe("WHEN guessing target is disabled", function()
      local newFilePath = projectRoot .. "Helpers/Modules/NewModule/new_file2.swift"
      local callbackCalled = false

      before_each(function()
        require("xcodebuild.core.config").options.project_manager.guess_target = false
        setFilePath(newFilePath)
        manager.add_file(newFilePath, function()
          callbackCalled = true
        end, { createGroups = true })
      end)

      it("THEN the target is set based on picker selection", function()
        assert.is_true(pickerShown)
        assert.is_true(callbackCalled)
        assert.are_same({
          "XcodebuildNvimApp",
          "XcodebuildNvimAppTests",
          "XcodebuildNvimAppUITests",
          "Helpers",
          "EmptyTarget",
        }, pickerReceivedItems)
        assertFileInProject(newFilePath, { "XcodebuildNvimApp" })
        assertGroupInProject("NewModule")
      end)
    end)
  end)

  -- New file operations without guessing target

  describe("WHEN file does not exist", function()
    local newFilePath = projectRoot .. "XcodebuildNvimApp/Modules/NewModule/new_file.swift"

    describe("add_file_to_targets", function()
      before_each(function()
        setFilePath(newFilePath)
        manager.add_current_group()
        manager.add_file_to_targets(newFilePath, { "XcodebuildNvimApp", "XcodebuildNvimAppTests", "Helpers" })
      end)

      it("THEN adds file to targets", function()
        assertFileInProject(newFilePath, { "XcodebuildNvimApp", "XcodebuildNvimAppTests", "Helpers" })
      end)
    end)

    describe("create_new_file", function()
      before_each(function()
        vim.fn.input = function(_, _)
          return "new_file.swift"
        end

        local newFileGroupPath = vim.fn.fnamemodify(newFilePath, ":h")
        util.shell("mkdir -p '" .. newFileGroupPath .. "'")
        manager.create_new_file()
      end)

      it("THEN creates a new file on disk", function()
        assert.is_true(util.file_exists(newFilePath))
      end)

      it("THEN updates xcodeproj", function()
        assertFileInProject(newFilePath)
      end)
    end)

    describe("add_file", function()
      before_each(function()
        manager.add_file(newFilePath, nil, { createGroups = true })
      end)

      it("THEN updates xcodeproj", function()
        assertFileInProject(newFilePath)
      end)
    end)

    describe("add_file with nested dirs", function()
      local nestedFilePath = projectRoot .. "XcodebuildNvimApp/SomeDir/Nested/NewModule/File.swift"
      before_each(function()
        manager.add_file(nestedFilePath, nil, { createGroups = true })
      end)

      it("THEN creates intermediate groups", function()
        assertGroupInProject("SomeDir")
        assertGroupInProject("Nested")
        assertGroupInProject("NewModule")
      end)

      it("THEN updates xcodeproj", function()
        assertFileInProject(nestedFilePath)
      end)
    end)

    describe("add_current_file", function()
      before_each(function()
        setFilePath(newFilePath)
        manager.add_current_file()
      end)

      it("THEN updates xcodeproj", function()
        assertFileInProject(newFilePath)
      end)
    end)
  end)

  -- Existing file operations

  describe("WHEN file exists in project", function()
    local filepath = projectRoot .. "XcodebuildNvimApp/Modules/Main/MainViewModel.swift"

    describe("move_file", function()
      local movedGroupPath = projectRoot .. "XcodebuildNvimApp/Modules/MovedModule"
      local movedFilePath = projectRoot .. "XcodebuildNvimApp/Modules/MovedModule/moved_file.swift"

      before_each(function()
        manager.add_file_to_targets(filepath, { "XcodebuildNvimApp", "Helpers" })
        manager.add_group(movedGroupPath)
        manager.move_file(filepath, movedFilePath)
      end)

      it("THEN updates xcodeproj and keeps original targets", function()
        assertFileInProject(movedFilePath, { "XcodebuildNvimApp", "Helpers" })
      end)
    end)

    describe("rename_file", function()
      local changedFilePath = vim.fn.fnamemodify(filepath, ":h") .. "/HomeViewModel_changed.swift"

      before_each(function()
        manager.add_file_to_targets(filepath, { "XcodebuildNvimApp", "Helpers" })
        manager.rename_file(filepath, changedFilePath)
      end)

      it("THEN updates xcodeproj and keeps original targets", function()
        assertFileInProject(changedFilePath, { "XcodebuildNvimApp", "Helpers" })
      end)
    end)

    describe("rename_current_file", function()
      local changedFilePath = vim.fn.fnamemodify(filepath, ":h") .. "/HomeViewModel_changed.swift"

      before_each(function()
        vim.fn.input = function(_, _)
          return "HomeViewModel_changed.swift"
        end
        setFilePath(filepath)
        manager.add_file_to_targets(filepath, { "XcodebuildNvimApp", "Helpers" })
        manager.rename_current_file()
      end)

      it("THEN moves file on disk", function()
        assert.is_true(util.file_exists(changedFilePath))
        assert.is_false(util.file_exists(filepath))
      end)

      it("THEN updates xcodeproj and keeps original targets", function()
        assertFileInProject(changedFilePath, { "XcodebuildNvimApp", "Helpers" })
      end)
    end)

    describe("delete_file", function()
      before_each(function()
        manager.delete_file(filepath)
      end)

      it("THEN updates xcodeproj", function()
        assertFileInProject(filepath, {})
      end)
    end)

    describe("delete_current_file", function()
      before_each(function()
        vim.fn.input = function(_, _)
          return "y"
        end
        setFilePath(filepath)
        manager.delete_current_file()
      end)

      it("THEN deletes file from disk", function()
        assert.is_false(util.file_exists(filepath))
      end)

      it("THEN updates xcodeproj", function()
        assertFileInProject(filepath, {})
      end)
    end)
  end)

  ----------------
  ---- GROUPS ----
  ----------------

  -- New group operations

  describe("WHEN group does not exist", function()
    local newGroupPath = projectRoot .. "XcodebuildNvimApp/Modules/NewModule"

    describe("create_new_group", function()
      before_each(function()
        vim.fn.input = function(_, _)
          return "NewModule"
        end
        setFilePath(projectRoot .. "XcodebuildNvimApp/Modules/something.swift")
        manager.create_new_group()
      end)

      it("THEN creates a new group on disk", function()
        assert.is_true(util.dir_exists(newGroupPath))
      end)

      it("THEN updates xcodeproj", function()
        assertGroupInProject("NewModule")
      end)
    end)

    describe("add_group", function()
      before_each(function()
        manager.add_group(newGroupPath)
      end)

      it("THEN updates xcodeproj", function()
        assertGroupInProject("NewModule")
      end)
    end)
  end)

  -- Existing group operations

  describe("WHEN group exists", function()
    local groupPath = projectRoot .. "XcodebuildNvimApp/Modules/Main"

    describe("rename_current_group", function()
      local changedGroupPath = projectRoot .. "XcodebuildNvimApp/Modules/MainChanged"

      before_each(function()
        vim.fn.input = function(_, _)
          return "MainChanged"
        end
        setFilePath(groupPath .. "/something.swift")
        manager.rename_current_group()
      end)

      it("THEN renames group on disk", function()
        assert.is_true(util.dir_exists(changedGroupPath))
        assert.is_false(util.dir_exists(groupPath))
      end)

      it("THEN updates xcodeproj", function()
        assertGroupInProject("MainChanged")
        assertGroupInProject("Main", false)
      end)
    end)

    describe("move_or_rename_group WHEN path is not changed", function()
      local changedGroupPath = projectRoot .. "XcodebuildNvimApp/Modules/MainChanged"

      before_each(function()
        manager.move_or_rename_group(groupPath, changedGroupPath)
      end)

      it("THEN updates xcodeproj", function()
        assertGroupInProject("MainChanged")
        assertGroupInProject("Main", false)
      end)
    end)

    describe("move_or_rename_group WHEN path is changed", function()
      local changedGroupPath = projectRoot .. "XcodebuildNvimApp/NewPath/Modules/MainChanged"

      before_each(function()
        manager.add_group(vim.fn.fnamemodify(changedGroupPath, ":h"))
        manager.move_or_rename_group(groupPath, changedGroupPath)
      end)

      it("THEN updates xcodeproj", function()
        assertGroupInProject("Modules")
        assertGroupInProject("NewPath")
        assertGroupInProject("MainChanged")
      end)
    end)

    describe("delete_group", function()
      before_each(function()
        manager.delete_group(groupPath)
      end)

      it("THEN updates xcodeproj", function()
        assertGroupInProject("Main", false)
      end)
    end)

    describe("delete_current_group", function()
      before_each(function()
        vim.fn.input = function(_, _)
          return "y"
        end
        setFilePath(groupPath .. "/something.swift")
        manager.delete_current_group()
      end)

      it("THEN deletes group from disk", function()
        assert.is_false(util.dir_exists(groupPath))
      end)

      it("THEN updates xcodeproj", function()
        assertGroupInProject("Main", false)
      end)
    end)
  end)
end)
