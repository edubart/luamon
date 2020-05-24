ROCKSPEC=rocks/luamon-*.rockspec

test-rocks:
	luarocks make --lua-version=5.3 --local $(ROCKSPEC)
	luarocks make --lua-version=5.1 --local $(ROCKSPEC)

upload-rocks:
	luarocks upload --api-key=$(LUAROCKS_APIKEY) $(ROCKSPEC)

.PHONY: test test-all test-rocks upload-rocks
