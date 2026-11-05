function [canonical, status] = canonicalGenotype(genotype, strain, sex, rules)
    %%CANONICALGENOTYPE Resolve a raw genotype token to its canonical label per genotypes.info rules
    %   [canonical, status] = io.metadata.canonicalGenotype(genotype, strain)
    %   [canonical, status] = io.metadata.canonicalGenotype(genotype, strain, sex, rules)
    %
    %   Inputs:
    %       genotype - Raw genotype token (text scalar), e.g. 'KO', 'Hom', 'knockout'
    %       strain   - Strain name (text scalar); matched case-insensitively against the rules
    %       sex      - (optional) Sex token (text scalar). When provided, the resolved canonical
    %                  label is additionally checked against that sex's combo for the strain.
    %       rules    - (optional) Rules struct from io.metadata.loadGenotypeInfo.
    %                  Defaults to the bundled genotypes.info.yml.
    %
    %   Outputs:
    %       canonical - Canonical genotype label (char). For 'normalized' this is the combo
    %                   label as written in the info file; for 'canonical' the combo label in
    %                   its file-written case; for 'unknown'/'undefined_strain' the trimmed
    %                   input token (pass-through).
    %       status    - One of:
    %                   'canonical'        - token matched a combo label of the strain
    %                   'normalized'       - token matched a normalize variant of the strain
    %                   'unknown'          - strain is defined but the token (or, when sex is
    %                                        given, the resolved canonical for that sex) is not
    %                                        a declared combo/variant; token passed through
    %                   'undefined_strain' - strain is not in the rules; no normalization,
    %                                        token passed through
    %
    %   All matching is case-insensitive and whitespace-tolerant.
    %
    %   See also: io.metadata.loadGenotypeInfo, io.metadata.canonicalSex

    arguments
        genotype {mustBeTextScalar}
        strain {mustBeTextScalar}
        sex {mustBeTextScalar} = ''
        rules (1, 1) struct = io.metadata.loadGenotypeInfo()
    end

    token = strtrim(char(genotype));
    strainName = strtrim(char(strain));

    idx = find(strcmpi({rules.byStrain.strain}, strainName), 1);
    if isempty(idx)
        canonical = token;
        status = 'undefined_strain';
        return;
    end

    entry = rules.byStrain(idx);
    comboAll = [entry.male, entry.female];

    hit = find(strcmpi(comboAll, token), 1);
    if ~isempty(hit)
        canonical = comboAll{hit};
        status = 'canonical';
    elseif isKey(entry.variantToCanonical, lower(token))
        canonical = entry.variantToCanonical(lower(token));
        status = 'normalized';
    else
        canonical = token;
        status = 'unknown';
    end

    % When a sex is given, verify the resolved canonical is a declared combo
    % for that strain+sex; otherwise flag as unknown (normalization stands,
    % but callers should warn).
    sexToken = strtrim(char(sex));
    if ~isempty(sexToken) && ~strcmp(status, 'unknown')
        switch lower(io.metadata.canonicalSex(sexToken))
            case 'male'
                sexCombo = entry.male;
            case 'female'
                sexCombo = entry.female;
            otherwise
                sexCombo = comboAll; % unrecognized sex: fall back to union of both combos
        end
        if ~any(strcmpi(sexCombo, canonical))
            status = 'unknown';
        end
    end
end
