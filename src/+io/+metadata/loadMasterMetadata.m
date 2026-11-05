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
    %       'GenotypesInfoRules' - A path to a genotypes.info.yml-formatted file, a pre-parsed
    %           YAML struct, or a rules struct from io.metadata.loadGenotypeInfo (default:
    %           the bundled +io/+metadata/genotypes.info.yml). Used to canonicalize the
    %           ANIMAL_GENOTYPE (strain/sex-aware) and ANIMAL_SEX columns at ingestion.
    %           Genotypes outside a defined strain's declared combos/variants are kept as-is
    %           and warned about once per unique combination per session.
    %
    %
    %   Outputs:
    %       masterMetadata - A structured array containing the metadata

    arguments
        filePath {mustBeFile}
        kwargs.SheetName {mustBeTextScalar} = 'Master Metadata'
        kwargs.GenotypesInfoRules {validator.mustBeGenotypeInfoRules} = io.metadata.loadGenotypeInfo()
    end

    rules = io.metadata.loadGenotypeInfo(kwargs.GenotypesInfoRules);

    persistent MetaFilePathHash;
    persistent CachedMasterMetadata;
    currentHash = [DataHash(filePath, 'SHA-256', 'file'), '|', rules.RulesHash];
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

    % Canonicalize genotype/sex tokens at ingestion (strain/sex-aware; see genotypes.info.yml)
    masterMetadata = io.metadata.normalizeMetadataTable(masterMetadata, rules);

    MetaFilePathHash = currentHash;
    CachedMasterMetadata = masterMetadata;
end