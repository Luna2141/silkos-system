-- test_init.lua
package.path = "./?.lua;./?/init.lua;;" .. package.path

local loom = require("loom.init")

print("--- testing bind ---")
loom.run({ "bind", "--yes" })

print("--- testing unknown verb ---")
loom.run({ "bogus" })
