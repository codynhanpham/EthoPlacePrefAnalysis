function cls = genotypeClass(genotype)
    %%GENOTYPECLASS Map a genotype token to a display class (case-insensitive)
    %   cls = graphics.genotypeClass(genotype)
    %
    %   Inputs:
    %       genotype - Genotype token (text scalar or array), e.g. 'WT', 'Het', 'Hom',
    %                  'KO', 'Hem', 'Knockout', 'Control', ...
    %
    %   Outputs:
    %       cls - Display class label(s): 'wt', 'het', 'hom', or 'other'.
    %             Matching is case-insensitive and whitespace-tolerant.
    %
    %   Class mapping (canonical display classes for graphics):
    %       wt    <- WT, Control, wildtype
    %       het   <- Het
    %       hom   <- Hom, KO, Hem, Knockout, homozygous
    %       other <- anything else
    %
    %   Note: this is a display-class helper only. Genotype normalization
    %   (variant -> canonical token) is governed by genotypes.info.yml via
    %   io.metadata.loadGenotypeInfo / io.metadata.canonicalGenotype.
    %
    %   See also: io.metadata.canonicalGenotype, io.metadata.loadGenotypeInfo

    arguments
        genotype
    end

    tokens = lower(strtrim(string(genotype)));
    cls = strings(size(tokens));
    cls(:) = "other";

    isWT = ismember(tokens, ["wt", "control", "wildtype"]);
    isHet = ismember(tokens, "het");
    isHom = ismember(tokens, ["hom", "ko", "hem", "knockout", "homozygous"]);

    cls(isWT) = "wt";
    cls(isHet) = "het";
    cls(isHom) = "hom";
end
