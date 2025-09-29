function comboTable = genotypeCombo(genotypeInfoYAML)
    %%GENOTYPECOMBO Create a table of all possible combinations of genotype metadata
    %   Required a YAML file with definitions of strains, sexes, and possible genotypes combinations
    %   If none are provided, defaults in +io/+metadata/genotypes.info.yml are used
    %
    %   USAGE:
    %       comboTable = io.metadata.genotypeCombo()
    %       comboTable = io.metadata.genotypeCombo(genotypeInfoYAML)
    %
    %   INPUTS:
    %       genotypeInfoYAML - (optional) path to a YAML file with genotype metadata
    %                          See +io/+metadata/genotypes.info.yml for format
    %
    %   OUTPUTS:
    %       comboTable - Table with all possible combinations of genotype metadata
    %                    Columns: 'Sex', 'Strain', 'Genotype'
    %
    %   See also: io.metadata.loadMasterMetadata, io.metadata.isMasterMetadataTable

    arguments
        genotypeInfoYAML {mustBeFile} = fullfile(fileparts(mfilename('fullpath')), 'genotypes.info.yml')
    end

    [~, ~, ext] = fileparts(genotypeInfoYAML);
    if ~ismember(ext, {'.yml', '.yaml'})
        error('genotypeInfoYAML must be a YAML file with .yml or .yaml extension');
    end

    genotypesInfo = yaml.load(fileread(genotypeInfoYAML));

    strains = cellfun(@(s) string(s.strain), genotypesInfo);
    combos = cellfun(@(s) s.combo, genotypesInfo);

    comboTable = table('Size', [0, 3], ...
        'VariableTypes', {'categorical', 'categorical', 'categorical'}, ...
        'VariableNames', {'Strain', 'Sex', 'Genotype'});

    for i = 1:length(strains)
        strain = strains(i);
        strain = char(strain);
        strainCombos = combos(i);
        
        % Fields in the combo struct: male/female
        fields = fieldnames(strainCombos);
        for j = 1:length(fields)
            sex = fields{j};
            sex = char(sex);
            genotypes = strainCombos.(sex);
            for k = 1:length(genotypes)
                genotype = genotypes{k};
                genotype = char(genotype);
                sex = [upper(sex(1)), sex(2:end)]; % Uppercase first letter for output
                comboTable = [
                    comboTable; 
                    {
                        categorical(cellstr(strain)), ...
                        categorical(cellstr(sex)), ...
                        categorical(cellstr(genotype))...
                    }
                ]; %#ok<AGROW>
            end
        end
    end

    % Sort the table: Genotype < Sex < Strain
    comboTable = sortrows(comboTable, {'Strain', 'Sex', 'Genotype'});

end