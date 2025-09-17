function mustBeFileTableOrEmpty(filePath)
    % The input must be an existing file path, a MATLAB table, or empty

    if istable(filePath) || isempty(filePath)
        return;
    end

    if ~validator.istext(filePath)
        error("Input must be a file path (string or char), a MATLAB table, or empty.");
    end

    filePath = char(filePath); % Convert to char for isfile check

    if ~isempty(filePath) && ~isfile(filePath)
        error("File '%s' does not exist.", filePath);
    end
end
