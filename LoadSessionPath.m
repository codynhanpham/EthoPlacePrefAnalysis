% This script adds the required paths to MATLAB for this session before starting the main mlapp file

function [newpath, oldpath] = LoadSessionPath()
    oldpath = path;

    % Load the components first
    % Components should be standalone and should not depend on other components or libraries
    % If some dependencies are required, they should be copied to the components' private folders
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), 'components')));

    % Main app folder (no subfolders)
    addpath(fullfile(fileparts(mfilename('fullpath')), 'src'));
    newpath = path;
end