% Proc2PCI - Start script for the Proc2PCI application

function PlacePrefDataGUI()
    [~, oldPath] = LoadSessionPath();
    % Start the application
    % run(fullfile(fileparts(mfilename('fullpath')), "src", "PlacePrefDataGUI_main.mlapp"))

    % LoadSessionPath should already add /src to the path
    mainFcn = str2func("PlacePrefDataGUI_main");
    mainFcn('', oldPath);
end