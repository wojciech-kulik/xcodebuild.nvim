---@mod xcodebuild.integrations.quick Quick Test Framework Integration
---@brief [[
---This module is responsible for parsing tests written using `Quick` framework.
---
---It provides functions to get a list of `Quick` tests and their locations.
---
---Note: it requires the Swift parser to be installed (using `nvim-treesitter`).
---
---See: https://github.com/Quick/Quick
---
---@brief ]]

local M = {}

local ts = vim.treesitter

---Cached result of the Swift parser check.
---@type boolean|nil
local cachedSwiftParserResult = nil

---@class QuickTest
---@field id string test id (matching xcodebuild test name)
---@field row number 1-based row number

---@class TestTreeNode
---@field id string node type
---@field testId string|nil test id (matching xcodebuild test name)
---@field name string group name
---@field row number 0-based row number
---@field endRow number 0-based row number
---@field parent TestTreeNode|nil
---@field children TestTreeNode[]

---@private
---@class TestQueryMatch
---@field id string node type
---@field name string group name
---@field row number 0-based row number
---@field endRow number 0-based row number

---Returns a list of captured nodes with two main types:
---`quick.context` and `quick.it`.
---@param bufnr number
---@return TestQueryMatch[][]
local function parse_test_file(bufnr)
  local result = {}
  local tree = ts.get_parser(bufnr, "swift"):parse()
  if not tree then
    return result
  end

  local root = tree[1]:root()

  local quickQueries = ts.query.parse(
    "swift",
    [[
  ((call_expression
    (simple_identifier) @quick-func
    (call_suffix
      (value_arguments
        (value_argument
          value: (line_string_literal
            text: (line_str_text) @quick.context
            (#any-of? @quick-func "describe" "fdescribe" "xdescribe" "context" "fcontext" "xcontext" "when")
  )))))) @quick.context.definition

  ((call_expression
    (simple_identifier) @quick-func
    (call_suffix
      (value_arguments
        (value_argument
          value: (line_string_literal
            text: (line_str_text) @quick.it
            (#any-of? @quick-func "it" "fit" "xit" "then")
  )))))) @quick.it.definition
]]
  )

  if vim.fn.has("nvim-0.11") == 1 then
    for _, match, _ in quickQueries:iter_matches(root, bufnr) do
      local capturedNodes = {}

      for id, nodes in pairs(match) do
        local capture = quickQueries.captures[id]

        if capture ~= "quick-func" then
          for _, currentMatch in ipairs(nodes) do
            local startRow, _, endRow, _ = currentMatch:range()
            table.insert(capturedNodes, {
              id = capture,
              name = not capture:match("definition") and ts.get_node_text(currentMatch, bufnr) or nil,
              row = startRow,
              endRow = endRow,
            })
          end
        end
      end

      table.insert(result, capturedNodes)
    end
  else
    for _, match in quickQueries:iter_matches(root, bufnr) do
      local capturedNodes = {}

      for i, capture in ipairs(quickQueries.captures) do
        local currentMatch = match[i]

        if currentMatch and capture ~= "quick-func" then
          ---@diagnostic disable-next-line: undefined-field
          local startRow, _, endRow, _ = currentMatch:range()
          table.insert(capturedNodes, {
            id = capture,
            name = not capture:match("definition") and ts.get_node_text(currentMatch, bufnr) or nil,
            row = startRow,
            endRow = endRow,
          })
        end
      end

      table.insert(result, capturedNodes)
    end
  end

  return result
end

---Returns a full test id by concatenating all parent names and
---replacing non-alphanumeric characters with underscores.
---
---The result should match the test name printed by xcodebuild.
---@param node TestTreeNode
---@return string
local function get_test_id(node)
  assert(node.id == "quick.it", "Incorrect node type")

  local components = {}
  local current = node

  local function normalize(str)
    local result = str:gsub("([^%w])", "_")
    return result
  end

  while current and current.id ~= "root" do
    table.insert(components, normalize(current.name))
    current = current.parent
  end

  return table.concat(vim.fn.reverse(components), "__")
end

---Returns a tree structure of tests and a list of tests
---based on the flat tree structure received from tree-sitter queries.
---@param flatTree TestQueryMatch[][]
---@return { tree: TestTreeNode[], tests: table<string,QuickTest[]> }
local function make_tree(flatTree)
  ---@type TestTreeNode
  local root = { id = "root", name = "", row = 0, endRow = 0, parent = nil, children = {} }
  local tree = root

  ---@type QuickTest[]
  local tests = {}

  ---@type TestTreeNode|nil
  local parent = root
  local updateParent = false

  for _, match in ipairs(flatTree) do
    ---@type TestTreeNode
    local newNode = {
      id = match[1].id,
      name = match[1].name,
      row = match[1].row,
      endRow = match[2].endRow,
      parent = parent,
      children = {},
    }

    if updateParent then
      while parent and parent.id ~= "root" do
        if parent.row <= newNode.row and parent.endRow >= newNode.endRow then
          break
        end

        parent = parent.parent
      end

      newNode.parent = parent
      updateParent = false
    end

    assert(parent, "Parent is nil")

    if newNode.id == "quick.it" then
      newNode.testId = get_test_id(newNode)
      table.insert(parent.children, newNode)
      tests[newNode.testId] = { id = newNode.testId, row = newNode.row + 1 }
      updateParent = true
    else
      table.insert(parent.children, newNode)
      parent = newNode
    end
  end

  return {
    tree = tree,
    tests = tests,
  }
end

---Builds a tree of tests based on the given buffer.
---
---The result is a tree structure where each node represents a group of tests.
---
---The first node is always the root node, it doesn't represent any test group.
---Iterate through the `children` property to get the top-level test groups.
---
---@param bufnr number
---@return TestTreeNode|nil
function M.build_quick_test_tree(bufnr)
  if not M.is_swift_parser_installed() then
    return nil
  end

  return make_tree(parse_test_file(bufnr)).tree
end

---Returns a list of tests and their locations.
---
---The result is a table where keys are test ids and values are `QuickTest` objects.
---
---Each test represents a single test case (e.g. `it` block).
---
---@param bufnr number
---@return table<string,QuickTest>|nil
function M.find_quick_tests(bufnr)
  if not M.is_swift_parser_installed() then
    return nil
  end

  return make_tree(parse_test_file(bufnr)).tests
end

---Returns whether the given buffer contains Quick tests.
---
---It checks if the buffer contains a subclass of `QuickSpec` or
---if there is `import Quick`.
---@param bufnr number
---@return boolean
function M.contains_quick_tests(bufnr)
  if not M.is_swift_parser_installed() then
    return false
  end

  local tree = ts.get_parser(bufnr, "swift"):parse()
  if not tree then
    return false
  end

  local root = tree[1]:root()

  local testClassQuery = ts.query.parse(
    "swift",
    [[
(class_declaration
  name: (type_identifier) @test-class
  (inheritance_specifier
    inherits_from: (user_type
      (type_identifier) @test-class-type
  (#eq? @test-class-type "QuickSpec"))))
]]
  )

  local importQuery = ts.query.parse(
    "swift",
    [[
(import_declaration
  (identifier) @quick-import (#eq? @quick-import "Quick"))
]]
  )

  for _, match in testClassQuery:iter_matches(root, bufnr) do
    if match[2] then
      return true
    end
  end

  for _, match in importQuery:iter_matches(root, bufnr) do
    if match[1] then
      return true
    end
  end

  return false
end

---Returns whether the Swift parser is installed.
---
---It caches the result for future calls.
---@return boolean
function M.is_swift_parser_installed()
  if cachedSwiftParserResult ~= nil then
    return cachedSwiftParserResult
  end

  local success, _ = pcall(require, "nvim-treesitter")
  if not success then
    return false
  end

  local parsers = vim.api.nvim_get_runtime_file("parser/*.so", true)

  local result = false
  for _, parser in ipairs(parsers) do
    local filename = vim.fn.fnamemodify(parser, ":t")
    if filename == "swift.so" then
      result = true
      break
    end
  end

  cachedSwiftParserResult = result

  return result
end

---Returns whether the Quick integration is enabled.
---@return boolean
function M.is_enabled()
  return require("xcodebuild.core.config").options.integrations.quick.enabled
    and M.is_swift_parser_installed()
end

return M
