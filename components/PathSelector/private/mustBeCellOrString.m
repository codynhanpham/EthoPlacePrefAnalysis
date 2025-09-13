function mustBeCellOrString(paths)
    if ~iscell(paths) && ~isstring(paths)
        error("Input must be a cell array of character vectors or a string array.");
    end
    if iscell(paths) && ~all(cellfun(@ischar, paths))
        error("All elements in the cell array must be character vectors.");
    end
end