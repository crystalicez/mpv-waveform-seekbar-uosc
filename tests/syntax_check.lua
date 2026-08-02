for index = 1, #arg do
    local chunk, err = loadfile(arg[index])
    assert(chunk, err)
end
print(string.format("PASS syntax_check %d files", #arg))
