ROCKSPEC=rocks/luamon-*.rockspec

install:
	luarocks make --local $(ROCKSPEC)

upload-rocks:
	luarocks upload --api-key=$(LUAROCKS_APIKEY) $(ROCKSPEC)

.PHONY: test test-all test-rocks upload-rocks
