function [output] = canonicalize(input, root)
    %%CANONICALIZE Converts a file path to its absolute, canonical form
    %   Still have edge cases, but this should handle most common scenarios.
    %
    %   Inputs:
    %       input - The input path string (can be relative or absolute)
    %       root - (optional) The root directory to resolve relative paths against. Defaults to pwd.
    %
    %   output = utils.path.canonicalize(fullfile(pwd, '..', 'somefile.txt'))

    arguments
        input {mustBeTextScalar}
        root {mustBeTextScalar} = pwd
    end

    [~, pth] = system(sprintf("echo %s", input));
    pth = strtrim(pth);
    if utils.path.isAbsolute(pth)
        output = pth;
    else
        output = fullfile(root, pth);
    end

    if isfile(output)
        % For files, we can use Java to fully resolve the path
        jFile=java.io.File(char(output));
        output=jFile.getCanonicalPath;
    elseif isfolder(output)
        % For folders, this trick seems to work
        output = cd(cd(output));
    end

    output = char(output);
end