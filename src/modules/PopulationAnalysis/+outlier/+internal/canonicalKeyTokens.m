function [geno, sex] = canonicalKeyTokens(geno, sex, strain)
    %CANONICALKEYTOKENS Canonicalize genotype/sex tokens for composite subject keys
    %
    %   [geno, sex] = outlier.internal.canonicalKeyTokens(geno, sex, strain)
    %
    %   Used by outlier.internal.animalSubjectKey and
    %   outlier.internal.subjectKeysFromTable so that the same animal recorded
    %   with variant tokens (e.g. 'KO' vs 'Hom', 'm' vs 'Male') maps to the
    %   same composite key.
    %
    %   Behavior:
    %       * Strain defined in genotypes.info.yml: genotype resolved via
    %         io.metadata.canonicalGenotype (variant -> canonical, e.g. Mecp2
    %         'KO' -> 'Hem'); sex via io.metadata.canonicalSex.
    %       * Strain NOT defined: no normalization; genotype falls back to
    %         lower(strtrim) identity so case-only drift still matches; sex
    %         still canonicalized (m -> Male).
    %       * Silent: no warnings are emitted here (ingestion-time
    %         io.metadata.normalizeMetadataTable owns user-facing warnings).
    %
    %   See also: io.metadata.canonicalGenotype, io.metadata.canonicalSex,
    %             io.metadata.loadGenotypeInfo

    geno = strtrim(char(string(geno)));
    sex = strtrim(char(string(sex)));
    strain = strtrim(char(string(strain)));

    if ~isempty(sex)
        sex = io.metadata.canonicalSex(sex);
    end

    if isempty(geno) || isempty(strain)
        return;
    end

    rules = io.metadata.loadGenotypeInfo();
    idx = find(strcmpi({rules.byStrain.strain}, strain), 1);
    if isempty(idx)
        % Undefined strain: case-insensitive identity fallback (no normalization)
        geno = lower(geno);
        return;
    end

    geno = io.metadata.canonicalGenotype(geno, strain, sex, rules);
end
