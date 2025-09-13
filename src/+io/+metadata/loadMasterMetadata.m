function [masterMetadata] = loadMasterMetadata(filePath, kwargs)
    %LOADMASTERMETADATA Load the master metadata from an Excel (.xlsx) file
    %   This function reads an Excel file containing metadata information
    %   and returns it as a structured array.
    %
    %   Inputs:
    %       filePath - The path to the Excel file
    %
    %   Name-Value Pair Arguments:
    %       'SheetName' - The name of the sheet to read (default: 'Master Metadata')
    %
    %
    %   Outputs:
    %       masterMetadata - A structured array containing the metadata

    arguments
        filePath {mustBeFile}
        kwargs.SheetName {mustBeTextScalar} = 'Master Metadata'
    end

    masterMetadata = readtable( ...
        filePath, ...
        Sheet=kwargs.SheetName ...
    );
    masterMetadata = rmmissing(masterMetadata, MinNumMissing=width(masterMetadata));
end