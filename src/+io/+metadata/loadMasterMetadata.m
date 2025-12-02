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

    persistent MetaFilePathHash;
    persistent CachedMasterMetadata;
    currentHash = DataHash(filePath, 'SHA-256', 'file');
    if ~isempty(MetaFilePathHash) && strcmp(currentHash, MetaFilePathHash)
        masterMetadata = CachedMasterMetadata;
        return;
    end

    masterMetadata = readtable( ...
        filePath, ...
        Sheet=kwargs.SheetName ...
    );
    masterMetadata = rmmissing(masterMetadata, MinNumMissing=width(masterMetadata));

    [bool, missingHeaders] = io.metadata.isMasterMetadataTable(masterMetadata);
    if ~bool
        error('The provided file does not contain a valid master metadata table. Missing headers: {'' %s ''}', strjoin(missingHeaders, ''', '''));
    end

    MetaFilePathHash = currentHash;
    CachedMasterMetadata = masterMetadata;
end