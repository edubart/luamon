LUAEXE=lua
ROCKSPEC=rocks/dumper-0.1.0-1.rockspec

test:
	lua test.lua

test-all:
	$(MAKE) test
	$(MAKE) LUAINC=/usr/include/luajit-2.1 LUAEXE=luajit test
	$(MAKE) LUAINC=/usr/include/lua5.1 LUAEXE=lua5.1 test

test-rocks:
	luarocks make --lua-version=5.3 --local $(ROCKSPEC)
	luarocks make --lua-version=5.1 --local $(ROCKSPEC)
	lua5.1 test.lua
	lua5.3 test.lua
	luajit test.lua

upload-rocks:
	luarocks upload --api-key=$(LUAROCKS_APIKEY) $(ROCKSPEC)

.PHONY: test test-all test-rocks upload-rocks
