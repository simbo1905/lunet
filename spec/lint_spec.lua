describe("C safety lint", function()
  it("passes on the current tree", function()
    local ok = os.execute("bin/lint_c_safety.sh >/dev/null")
    -- LuaJIT returns true on success.
    assert.is_true(ok)
  end)
end)
