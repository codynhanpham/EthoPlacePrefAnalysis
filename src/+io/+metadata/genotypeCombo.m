function comboTable = genotypeCombo(genotypeInfoSource)
    %%GENOTYPECOMBO Create a table of all possible combinations of genotype metadata
    %   Required a YAML file with definitions of strains, sexes, and possible genotypes combinations
    %   If none are provided, defaults in +io/+metadata/genotypes.info.yml are used
    %
    %   USAGE:
    %       comboTable = io.metadata.genotypeCombo()
    %       comboTable = io.metadata.genotypeCombo(genotypeInfoSource)
    %
    %   INPUTS:
    %       genotypeInfoSource - (optional) A path to a genotypes.info.yml-formatted YAML file,
    %                          a pre-parsed YAML struct, or a rules struct from
    %                          io.metadata.loadGenotypeInfo. See +io/+metadata/genotypes.info.yml
    %                          for the file format.
    %
    %   OUTPUTS:
    %       comboTable - Table with all possible combinations of genotype metadata
    %                    Columns: 'Sex', 'Strain', 'Genotype'
    %
    %   See also: io.metadata.loadGenotypeInfo, io.metadata.loadMasterMetadata, io.metadata.isMasterMetadataTable

    arguments
        genotypeInfoSource {validator.mustBeGenotypeInfoRules} = fullfile(fileparts(mfilename('fullpath')), 'genotypes.info.yml')
    end

    rules = io.metadata.loadGenotypeInfo(genotypeInfoSource);

    comboTable = table('Size', [0, 3], ...
        'VariableTypes', {'categorical', 'categorical', 'categorical'}, ...
        'VariableNames', {'Strain', 'Sex', 'Genotype'});

    for i = 1:numel(rules.byStrain)
        entry = rules.byStrain(i);
        for sexCell = {'male', 'female'}
            sex = sexCell{1};
            genotypes = entry.(sex);
            sexLabel = [upper(sex(1)), sex(2:end)]; % Uppercase first letter for output
            for k = 1:numel(genotypes)
                genotype = genotypes{k};
                comboTable = [
                    comboTable;
                    {
                        categorical(cellstr(entry.strain)), ...
                        categorical(cellstr(sexLabel)), ...
                        categorical(cellstr(genotype))...
                    }
                ]; %#ok<AGROW>
            end
        end
    end

    % Sort the table: Genotype < Sex < Strain
    comboTable = sortrows(comboTable, {'Strain', 'Sex', 'Genotype'});

end