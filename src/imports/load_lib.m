%% load_lib - Function
% This script file will be triggered once on main program startup.
% It looks for subfolders in the /lib folder and adds them to the MATLAB session path.
% Subfolders provided in the /lib/.ignore file will be ignored from loading.

function load_lib()

thismfileDir = fileparts(mfilename('fullpath'));
libParentDir = fullfile(thismfileDir, '..', '..', 'lib');
libDirs = dir(libParentDir);
libDirs = libDirs(~ismember({libDirs.name}, {'.', '..'}));
libDirs = libDirs(arrayfun(@(x) x.isdir, libDirs));

% Read ignore patterns from .ignore file
ignorefile = fullfile(libParentDir, '.ignore');
if ~isfile(ignorefile)
    ignorePatterns = {};
else
    ignorePatterns = readlines(ignorefile);
end

% Trim whitespace, remove empty lines, and remove comments
ignorePatterns = strtrim(ignorePatterns);
ignorePatterns = ignorePatterns(~cellfun(@isempty, ignorePatterns));
ignorePatterns = ignorePatterns(~startsWith(ignorePatterns, '#'));

% Make into dir paths
ignorePatterns = cellfun(@(x) fullfile(libParentDir, x), ignorePatterns, 'UniformOutput', false);
ignorePatterns = ignorePatterns(logical(cellfun(@(x) exist(x, 'dir'), ignorePatterns)));


libDirs = {libDirs.name}; % Grab the names from the struct array
for i = 1:numel(libDirs)
    libDir = fullfile(libParentDir, libDirs{i});
    
    allpaths = genpath(libDir);
    allpaths = split(allpaths, pathsep);
    allpaths = allpaths(~cellfun(@isempty, allpaths)); % Remove empty strings

    % Remove from allpaths any paths that starts with a pattern in ignorePatterns
    matchMatrix = startsWith(allpaths(:), ignorePatterns(:)');
    allpaths = allpaths(~any(matchMatrix, 2));

    if isempty(allpaths)
        continue
    end

    addpath(allpaths{:});
end

end