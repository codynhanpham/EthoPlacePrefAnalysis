function rules = loadGenotypeInfo(genotypeInfoSource)
    %%LOADGENOTYPEINFO Load genotype combo + normalization rules from a genotypes.info.yml file
    %   rules = io.metadata.loadGenotypeInfo()
    %   rules = io.metadata.loadGenotypeInfo(genotypeInfoSource)
    %
    %   Inputs:
    %       genotypeInfoSource - (optional) One of:
    %           * Path to a genotypes.info.yml-formatted YAML file
    %             (default: the bundled +io/+metadata/genotypes.info.yml)
    %           * A pre-parsed YAML struct/cell (raw output of yaml.load)
    %           * A processed rules struct (passed through unchanged)
    %
    %   Outputs:
    %       rules - Struct with fields:
    %           .strainNames - string array of strain names as written in the file
    %           .byStrain    - struct array (one per strain) with fields:
    %               .strain             - strain name as written (char)
    %               .male               - cellstr of canonical male genotype labels (as written)
    %               .female             - cellstr of canonical female genotype labels (as written)
    %               .variantToCanonical - containers.Map: lower(variant token) -> canonical label (char)
    %           .RulesHash   - content fingerprint of the rules (file hash for path inputs)
    %
    %   The YAML schema (see genotypes.info.yml comments):
    %       - strain: STRAIN_NAME
    %         combo:
    %           female: [GENOTYPE, ...]   % canonical labels; may be empty
    %           male:   [GENOTYPE, ...]
    %         normalize:                  % optional
    %           - CANONICAL: [VARIANT, ...]
    %
    %   Schema rules enforced here (violations are hard errors):
    %       * every normalize CANONICAL must appear in at least one sex combo of that strain
    %       * a VARIANT must not collide with a different canonical combo label of that strain
    %       * a VARIANT must not map to two different canonicals within a strain
    %   All token matching downstream is case-insensitive.
    %
    %   See also: io.metadata.canonicalGenotype, io.metadata.canonicalSex, io.metadata.genotypeCombo

    arguments
        genotypeInfoSource {validator.mustBeGenotypeInfoRules} = fullfile(fileparts(mfilename('fullpath')), 'genotypes.info.yml')
    end

    persistent CachedHash CachedRules

    % Already-processed rules struct: pass through
    if isstruct(genotypeInfoSource) && isscalar(genotypeInfoSource) ...
            && isfield(genotypeInfoSource, 'byStrain') && isfield(genotypeInfoSource, 'strainNames')
        rules = genotypeInfoSource;
        return;
    end

    if ischar(genotypeInfoSource) || (isstring(genotypeInfoSource) && isscalar(genotypeInfoSource))
        yamlPath = char(genotypeInfoSource);
        currentHash = DataHash(yamlPath, 'SHA-256', 'file');
        if ~isempty(CachedHash) && strcmp(currentHash, CachedHash)
            rules = CachedRules;
            return;
        end
        raw = yaml.load(fileread(yamlPath));
        rules = parseGenotypeInfo(raw, yamlPath);
        rules.RulesHash = currentHash;
        CachedHash = currentHash;
        CachedRules = rules;
        return;
    end

    % Pre-parsed raw YAML (cell array / struct array of strain entries)
    rules = parseGenotypeInfo(genotypeInfoSource, '<pre-parsed struct>');
    rules.RulesHash = rulesContentHash(rules);
end


function rules = parseGenotypeInfo(raw, sourceLabel)
    if isstruct(raw)
        raw = num2cell(raw);
    end
    if ~iscell(raw) || isempty(raw)
        error('io:metadata:loadGenotypeInfo:EmptyRules', ...
            'Genotype info source %s did not yield any strain entries.', sourceLabel);
    end

    nStrains = numel(raw);
    byStrain = repmat(struct('strain', '', 'male', {{}}, 'female', {{}}, ...
        'variantToCanonical', containers.Map('KeyType', 'char', 'ValueType', 'char')), nStrains, 1);
    strainNames = strings(nStrains, 1);

    for i = 1:nStrains
        entry = raw{i};
        if ~isstruct(entry) || ~isfield(entry, 'strain')
            error('io:metadata:loadGenotypeInfo:MissingStrain', ...
                'Entry %d in %s is missing the required ''strain'' field.', i, sourceLabel);
        end
        strainName = char(strtrim(string(entry.strain)));
        strainNames(i) = strainName;

        if ~isfield(entry, 'combo') || ~isstruct(entry.combo)
            error('io:metadata:loadGenotypeInfo:MissingCombo', ...
                'Strain "%s" in %s is missing the required ''combo'' mapping.', strainName, sourceLabel);
        end
        maleCombo = {};
        femaleCombo = {};
        if isfield(entry.combo, 'male')
            maleCombo = toCharCell(entry.combo.male);
        end
        if isfield(entry.combo, 'female')
            femaleCombo = toCharCell(entry.combo.female);
        end

        comboAll = [maleCombo, femaleCombo];
        variantMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
        if isfield(entry, 'normalize') && ~isempty(entry.normalize)
            normList = entry.normalize;
            if isstruct(normList)
                normList = num2cell(normList);
            end
            if ~iscell(normList)
                error('io:metadata:loadGenotypeInfo:BadNormalize', ...
                    'Strain "%s" in %s: ''normalize'' must be a list of CANONICAL: [VARIANT, ...] mappings.', ...
                    strainName, sourceLabel);
            end
            for k = 1:numel(normList)
                mapping = normList{k};
                if ~isstruct(mapping) || ~isscalar(mapping)
                    error('io:metadata:loadGenotypeInfo:BadNormalize', ...
                        'Strain "%s" in %s: each ''normalize'' list item must be a single CANONICAL: [VARIANT, ...] mapping.', ...
                        strainName, sourceLabel);
                end
                mappingFields = fieldnames(mapping);
                if numel(mappingFields) ~= 1
                    error('io:metadata:loadGenotypeInfo:BadNormalize', ...
                        'Strain "%s" in %s: each ''normalize'' list item must have exactly one CANONICAL key, got %d.', ...
                        strainName, sourceLabel, numel(mappingFields));
                end
                canonical = mappingFields{1};
                if ~any(strcmpi(canonical, comboAll))
                    error('io:metadata:loadGenotypeInfo:CanonicalNotInCombo', ...
                        ['Strain "%s" in %s: normalize canonical "%s" is not one of the possible genotypes ', ...
                        'declared in that strain''s combo. Update the combo or fix the normalize entry.'], ...
                        strainName, sourceLabel, canonical);
                end
                variants = toCharCell(mapping.(canonical));
                for v = 1:numel(variants)
                    variant = variants{v};
                    if any(strcmpi(variant, comboAll)) && ~strcmpi(variant, canonical)
                        error('io:metadata:loadGenotypeInfo:VariantCollidesWithCombo', ...
                            ['Strain "%s" in %s: normalize variant "%s" collides with a different canonical ', ...
                            'combo label of the same strain. This mapping would be ambiguous.'], ...
                            strainName, sourceLabel, variant);
                    end
                    key = lower(strtrim(variant));
                    if isKey(variantMap, key) && ~strcmp(variantMap(key), canonical)
                        error('io:metadata:loadGenotypeInfo:ConflictingVariant', ...
                            'Strain "%s" in %s: variant "%s" maps to both "%s" and "%s".', ...
                            strainName, sourceLabel, variant, variantMap(key), canonical);
                    end
                    variantMap(key) = canonical;
                end
            end
        end

        byStrain(i).strain = strainName;
        byStrain(i).male = maleCombo;
        byStrain(i).female = femaleCombo;
        byStrain(i).variantToCanonical = variantMap;
    end

    rules = struct('strainNames', strainNames, 'byStrain', byStrain);
end


function h = rulesContentHash(rules)
    % Content fingerprint over plain-cell data (containers.Map is not DataHash-friendly).
    parts = cell(1, numel(rules.byStrain));
    for i = 1:numel(rules.byStrain)
        entry = rules.byStrain(i);
        vkeys = sort(keys(entry.variantToCanonical));
        vvals = cell(1, numel(vkeys));
        for v = 1:numel(vkeys)
            vvals{v} = entry.variantToCanonical(vkeys{v});
        end
        parts{i} = {entry.strain, entry.male, entry.female, vkeys, vvals};
    end
    h = DataHash(parts, 'SHA-256');
end


function out = toCharCell(x)
    % Coerce a YAML-loaded list/scalar/empty into a cellstr row vector of trimmed char.
    if isempty(x)
        out = {};
        return;
    end
    if ischar(x) || (isstring(x) && isscalar(x))
        s = strtrim(string(x));
        if strlength(s) == 0
            out = {};
        else
            out = {char(s)};
        end
        return;
    end
    if iscell(x) || isstring(x)
        flat = reshape(x, 1, []);
        out = cell(1, numel(flat));
        keep = true(1, numel(flat));
        for j = 1:numel(flat)
            item = flat{j};
            if iscell(x)
                s = strtrim(string(item));
            else
                s = strtrim(item);
            end
            if ismissing(s) || strlength(s) == 0
                keep(j) = false;
            else
                out{j} = char(s);
            end
        end
        out = out(keep);
        return;
    end
    error('io:metadata:loadGenotypeInfo:BadList', ...
        'Expected a string or list of strings in the genotype info file, got %s.', class(x));
end
