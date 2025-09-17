function mustBeFileOrTable(filePath)
    % The input must be an existing file path or a MATLAB table
    if isempty(filePath)
        error("Input must be a file path (string or char) or a MATLAB table.");
    end
    
    if istable(filePath)
        return;
    end

    if ~validator.istext(filePath)
        error("Input must be a file path (string or char) or a MATLAB table.");
    end

    filePath = char(filePath); % Convert to char for isfile check

    if isempty(filePath)
        error("Input must be a file path (string or char) or a MATLAB table.");
    end

    if ~isfile(filePath)
        error("File '%s' does not exist.", filePath);
    end
end
