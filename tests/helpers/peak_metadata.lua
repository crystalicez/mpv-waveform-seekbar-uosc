return function(width, duration, db)
    local lines = {}
    width = assert(tonumber(width))
    duration = assert(tonumber(duration))
    db = db or -6.0206
    for index = 0, width - 1 do
        lines[#lines + 1] = string.format("frame:%d pts:%d pts_time:%.9g", index, index, duration * index / width)
        lines[#lines + 1] = "lavfi.astats.1.Peak_level=" .. tostring(db)
    end
    return table.concat(lines, "\n")
end
