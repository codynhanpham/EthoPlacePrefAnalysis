function mustBeFileOrEmpty(filePath)
    if ~isempty(filePath) && ~isfile(filePath)
        error("File '%s' does not exist.", filePath);
    end
end
