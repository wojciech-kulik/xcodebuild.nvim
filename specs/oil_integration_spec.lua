local assert = require("luassert")
local oil = require("xcodebuild.integrations.oil-nvim")
local cwd = vim.fn.getcwd()

local function load_case(number)
  local inputPath = cwd .. "/specs/oil_test_data/oil_actions_" .. number .. ".json"
  local inputJson = vim.fn.readfile(inputPath)
  local inputTable = vim.fn.json_decode(inputJson)

  local outputPath = cwd .. "/specs/oil_test_data/oil_actions_" .. number .. "_out.json"
  local outputJson = vim.fn.readfile(outputPath)
  local outputTable = vim.fn.json_decode(outputJson)

  return inputTable, outputTable
end

describe("ENSURE normalizeOilActions", function()
  describe("WHEN files are created", function()
    it("THEN all related directory create actions are removed AND other actions are kept", function()
      local actions, output = load_case(1)
      oil.__normalizeOilActions(actions)
      assert.are.same(output, actions)
    end)
  end)

  describe("WHEN file is created", function()
    it("THEN all related directory create actions are removed", function()
      local actions, output = load_case(2)
      oil.__normalizeOilActions(actions)
      assert.are.same(output, actions)
    end)
  end)

  describe("WHEN file is created", function()
    it("THEN create empty directory actions is not removed", function()
      local actions, output = load_case(3)
      oil.__normalizeOilActions(actions)
      assert.are.same(output, actions)
    end)
  end)

  describe("WHEN empty dir is created", function()
    it("THEN the action is not removed", function()
      local actions, output = load_case(4)
      oil.__normalizeOilActions(actions)
      assert.are.same(output, actions)
    end)
  end)

  describe("WHEN delete operations are performed", function()
    it("THEN they don't affect create actions", function()
      local actions, output = load_case(5)
      oil.__normalizeOilActions(actions)
      assert.are.same(output, actions)
    end)
  end)

  describe("WHEN two files are being created at the same location", function()
    it(
      "THEN create directory actions should be removed AND both create file actions should be kept",
      function()
        local actions, output = load_case(6)
        oil.__normalizeOilActions(actions)
        assert.are.same(output, actions)
      end
    )
  end)
end)
