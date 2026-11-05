function mustBeGenotypeInfoRules(x)
    %%MUSTBEGENOTYPEINFORULES Validate genotype info rules input
    %   Accepts:
    %       - A path to a genotypes.info.yml-formatted file (.yml/.yaml)
    %       - A pre-parsed YAML struct/cell (raw output of yaml.load)
    %       - A processed rules struct from io.metadata.loadGenotypeInfo()
    %
    %   Full schema validation is performed by io.metadata.loadGenotypeInfo;
    %   this validator only checks the input type/shape is plausible.

    if ischar(x) || (isstring(x) && isscalar(x))
        if ~isfile(x)
            error('GenotypesInfoRules path does not point to an existing file: %s', char(x));
        end
        [~, ~, ext] = fileparts(x);
        if ~ismember(lower(ext), {'.yml', '.yaml'})
            error('GenotypesInfoRules file must have a .yml or .yaml extension.');
        end
        return;
    end

    if isstruct(x)
        if ~isscalar(x)
            error('GenotypesInfoRules struct input must be scalar (a processed rules struct or one raw YAML entry).');
        end
        % Accept either a processed rules struct or a raw single strain entry.
        if isfield(x, 'byStrain') || isfield(x, 'strain')
            return;
        end
        error('GenotypesInfoRules struct must be a processed rules struct (with .byStrain) or raw YAML entry (with .strain).');
    end

    if iscell(x)
        if isempty(x)
            error('GenotypesInfoRules cell input (raw parsed YAML) must not be empty.');
        end
        return;
    end

    error(['GenotypesInfoRules must be a path to a genotypes.info.yml file, ' ...
        'a pre-parsed YAML struct/cell, or a processed rules struct from io.metadata.loadGenotypeInfo().']);
end
