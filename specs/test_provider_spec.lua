---@diagnostic disable: duplicate-set-field

local assert = require("luassert")
local provider = require("xcodebuild.tests.provider")

local busted = require("plenary.busted")
local before_each = busted.before_each
local after_each = busted.after_each
local it = busted.it
local describe = busted.describe

describe("xcodebuild.tests.provider.find_tests", function()
  local original_get_lines
  local original_get_cursor

  local mock_buffer = "" -- tests can assign a mock buffer here
  local mock_cursor = { 1, 0 } -- tests can simulate cursor position here

  before_each(function()
    original_get_lines = vim.api.nvim_buf_get_lines
    original_get_cursor = vim.api.nvim_win_get_cursor
    vim.api.nvim_win_get_cursor = function(_)
      return mock_cursor
    end

    vim.api.nvim_buf_get_lines = function(_, _, _, _)
      local lines = {}
      for line in mock_buffer:gmatch("([^\n]+)") do
        table.insert(lines, line)
      end
      return lines
    end
  end)

  after_each(function()
    vim.api.nvim_buf_get_lines = original_get_lines
    vim.api.nvim_win_get_cursor = original_get_cursor
  end)

  describe("WHEN selecting current test in an XCTest file", function()
    before_each(function()
      mock_buffer = [[
        class MyTests: XCTestCase {
          func testOne() {
              XCTAssert(true)
          }

          func testTwo() {
            XCTAssert(false)
          }
        }
      ]]
    end)

    it("THEN the first test can be identified", function()
      mock_cursor = { 3, 0 }

      local class, tests = provider.find_tests({ currentTest = true })
      assert.are.same(class, "MyTests")
      assert.are.same(tests, { { class = "MyTests", name = "testOne" } })
    end)

    it("THEN the last test can be identified", function()
      mock_cursor = { 7, 0 }

      local class, tests = provider.find_tests({ currentTest = true })
      assert.are.same(class, "MyTests")
      assert.are.same(tests, { { class = "MyTests", name = "testTwo" } })
    end)
  end)

  describe("WHEN selecting current test in a Swift Testing file", function()
    before_each(function()
      mock_buffer = [[
				struct TestSuite {
					@Test func itPasses() {
						#expect(true)
					}

					@Test 
					func itFails() {
						#expect(false)
					}
				}
			]]
    end)

    it("THEN tests are identified when @Test annotation is on same line", function()
      mock_cursor = { 3, 0 }

      local class, tests = provider.find_tests({ currentTest = true })
      assert.are.same(class, "TestSuite")
      assert.are.same(tests, { { class = "TestSuite", name = "itPasses" } })
    end)

    it("THEN tests are identified when @Test annotation is on previous line", function()
      mock_cursor = { 7, 0 }

      local class, tests = provider.find_tests({ currentTest = true })
      assert.are.same(class, "TestSuite")
      assert.are.same(tests, { { class = "TestSuite", name = "itFails" } })
    end)
  end)
end)
