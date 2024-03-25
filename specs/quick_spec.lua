---@diagnostic disable: duplicate-set-field

local assert = require("luassert")
local quick = require("xcodebuild.integrations.quick")
local cwd = vim.fn.getcwd()
local recordSnapshot = false

local originalGetNode = vim.treesitter.get_node_text
local originalQueryParse = vim.treesitter.query.parse

local function mock(id)
  local testsContent = vim.fn.readfile(cwd .. "/specs/quick_test_data/quick_test_" .. id .. ".swift")
  local text = table.concat(testsContent, "\n")

  vim.treesitter.get_parser = function(_, _)
    local parser = vim.treesitter.get_string_parser(text, "swift")
    return parser
  end

  vim.treesitter.query.parse = function(lang, query)
    local result = originalQueryParse(lang, query)
    assert(result, "Query parse failed")

    local originalIter = result.iter_matches
    result.iter_matches = function(obj, node, _, start, stop, opts)
      return originalIter(obj, node, text, start, stop, opts)
    end

    return result
  end

  vim.treesitter.get_node_text = function(root, _)
    return originalGetNode(root, text)
  end
end

local function assertSnapshot(id, actual)
  if recordSnapshot then
    vim.fn.writefile(
      vim.split(vim.fn.json_encode(actual), "\n"),
      cwd .. "/specs/quick_test_data/quick_test_" .. id .. "_out.json"
    )
    assert(false, "Snapshot recorded")
    return
  end

  local outputPath = cwd .. "/specs/quick_test_data/quick_test_" .. id .. "_out.json"
  local outputJson = vim.fn.readfile(outputPath)
  local outputTable = vim.fn.json_decode(outputJson)

  assert.are.same(outputTable, actual)
end

local function assertTable(id, actual)
  if recordSnapshot then
    vim.fn.writefile(
      vim.split(vim.inspect(actual), "\n"),
      cwd .. "/specs/quick_test_data/quick_test_" .. id .. "_out.json"
    )
    assert(false, "Snapshot recorded")
    return
  end

  local outputPath = cwd .. "/specs/quick_test_data/quick_test_" .. id .. "_out.json"
  local outputTable = vim.fn.readfile(outputPath)

  assert.are.same(outputTable, vim.split(vim.inspect(actual), "\n"))
end

describe("ENSURE", function()
  describe("is_swift_parser_installed", function()
    it("returns true", function()
      local result = quick.is_swift_parser_installed()
      assert.is_true(result)
    end)
  end)

  describe("contains_quick_tests", function()
    describe("WHEN test file contains import Quick", function()
      before_each(function()
        mock(2)
      end)

      it("THEN returns true", function()
        local result = quick.contains_quick_tests(0)
        assert.is_true(result)
      end)
    end)

    describe("WHEN test file contains QuickSpec subclass", function()
      before_each(function()
        mock(3)
      end)

      it("THEN returns true", function()
        local result = quick.contains_quick_tests(0)
        assert.is_true(result)
      end)
    end)

    describe("WHEN test file contains XCTests", function()
      before_each(function()
        mock(4)
      end)

      it("THEN returns false", function()
        local result = quick.contains_quick_tests(0)
        assert.is_false(result)
      end)
    end)
  end)

  describe("find_quick_tests", function()
    before_each(function()
      mock(1)
    end)

    it("returns correctly parsed tests", function()
      local result = quick.find_quick_tests(0)
      assertSnapshot(1, result)
    end)
  end)

  describe("build_quick_test_tree", function()
    before_each(function()
      mock(5)
    end)

    it("returns quick test tree", function()
      local result = quick.build_quick_test_tree(0)
      assertTable(5, result)
    end)
  end)
end)
