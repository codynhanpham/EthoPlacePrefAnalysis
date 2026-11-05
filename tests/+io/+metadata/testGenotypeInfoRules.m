classdef testGenotypeInfoRules < matlab.unittest.TestCase
    % Tests for the genotypes.info.yml-driven normalization engine:
    %   io.metadata.loadGenotypeInfo, io.metadata.canonicalGenotype,
    %   io.metadata.canonicalSex, io.metadata.normalizeMetadataTable,
    %   io.metadata.genotypeCombo, validator.mustBeGenotypeInfoRules.

    methods (Test)
        function mecp2KoNormalizesToHem(testCase)
            rules = io.metadata.loadGenotypeInfo();
            [canon, status] = io.metadata.canonicalGenotype('KO', 'Mecp2', 'Male', rules);
            testCase.verifyEqual(canon, 'Hem');
            testCase.verifyEqual(status, 'normalized');
        end

        function mecp2KnockoutVariantIsCaseInsensitive(testCase)
            rules = io.metadata.loadGenotypeInfo();
            [canon, status] = io.metadata.canonicalGenotype('knockout', 'MECP2', 'male', rules);
            testCase.verifyEqual(canon, 'Hem');
            testCase.verifyEqual(status, 'normalized');
        end

        function shank3bKoIsCanonical(testCase)
            rules = io.metadata.loadGenotypeInfo();
            [canon, status] = io.metadata.canonicalGenotype('KO', 'Shank3B', 'Female', rules);
            testCase.verifyEqual(canon, 'KO');
            testCase.verifyEqual(status, 'canonical');
        end

        function cntnap2KoIsCanonical(testCase)
            rules = io.metadata.loadGenotypeInfo();
            [canon, status] = io.metadata.canonicalGenotype('ko', 'Cntnap2', 'Male', rules);
            testCase.verifyEqual(canon, 'KO');
            testCase.verifyEqual(status, 'canonical');
        end

        function undefinedStrainPassesThrough(testCase)
            rules = io.metadata.loadGenotypeInfo();
            [canon, status] = io.metadata.canonicalGenotype('WT', 'NoSuchStrain', 'Male', rules);
            testCase.verifyEqual(canon, 'WT');
            testCase.verifyEqual(status, 'undefined_strain');
        end

        function unknownGenotypeOnDefinedStrainPassesThrough(testCase)
            rules = io.metadata.loadGenotypeInfo();
            [canon, status] = io.metadata.canonicalGenotype('Weird', 'Mecp2', 'Male', rules);
            testCase.verifyEqual(canon, 'Weird');
            testCase.verifyEqual(status, 'unknown');
        end

        function sexRestrictedComboFlagsUnknown(testCase)
            % Mecp2 Hem is male-only; a female Hem is out-of-combo.
            rules = io.metadata.loadGenotypeInfo();
            [~, status] = io.metadata.canonicalGenotype('Hem', 'Mecp2', 'Female', rules);
            testCase.verifyEqual(status, 'unknown');
        end

        function canonicalSexVariants(testCase)
            testCase.verifyEqual(io.metadata.canonicalSex('m'), 'Male');
            testCase.verifyEqual(io.metadata.canonicalSex('MALE'), 'Male');
            testCase.verifyEqual(io.metadata.canonicalSex('f'), 'Female');
            testCase.verifyEqual(io.metadata.canonicalSex('Female'), 'Female');
            testCase.verifyEqual(io.metadata.canonicalSex('x'), 'x'); % passthrough
        end

        function normalizeMetadataTableCanonicalizesAndWarnsOnce(testCase)
            rules = io.metadata.loadGenotypeInfo();
            % Unique token per run so the session-level de-dup map inside
            % normalizeMetadataTable cannot collide across repeated test runs.
            weirdToken = ['Weird', char(datetime('now'))];
            T = table( ...
                {'Mecp2'; 'Mecp2'; 'Mecp2'}, ...
                {'Male'; 'Female'; 'Male'}, ...
                {'KO'; 'Het'; weirdToken}, ...
                'VariableNames', {'ANIMAL_STRAIN', 'ANIMAL_SEX', 'ANIMAL_GENOTYPE'});

            % First call: warns exactly once for the unknown genotype
            T2 = testCase.verifyWarning(@() io.metadata.normalizeMetadataTable(T, rules), ...
                'io:metadata:normalizeMetadataTable:UnknownGenotype');
            testCase.verifyEqual(string(T2.ANIMAL_GENOTYPE(1)), "Hem");
            testCase.verifyEqual(string(T2.ANIMAL_GENOTYPE(2)), "Het");
            testCase.verifyEqual(string(T2.ANIMAL_GENOTYPE(3)), string(weirdToken)); % passthrough
            testCase.verifyEqual(string(T2.ANIMAL_SEX(1)), "Male");
            testCase.verifyEqual(string(T2.ANIMAL_SEX(2)), "Female");

            % Second call with the same data: no repeated warnings (de-dup)
            testCase.verifyWarningFree(@() io.metadata.normalizeMetadataTable(T, rules));
        end

        function genotypeComboEmitsCanonicalLabels(testCase)
            ct = io.metadata.genotypeCombo();
            testCase.verifyTrue(any(ct.Strain == 'Mecp2' & ct.Genotype == 'Hem' & ct.Sex == 'Male'));
            testCase.verifyFalse(any(ct.Strain == 'Mecp2' & ct.Genotype == 'KO'));
            testCase.verifyTrue(any(ct.Strain == 'Shank3B' & ct.Genotype == 'KO'));
        end

        function rulesStructPassthrough(testCase)
            rules = io.metadata.loadGenotypeInfo();
            rules2 = io.metadata.loadGenotypeInfo(rules);
            testCase.verifyEqual(rules2.strainNames, rules.strainNames);
        end

        function rawYamlStructInputParses(testCase)
            % tests/+io/+metadata -> repo root is 3 levels up
            ymlPath = fullfile(fileparts(mfilename('fullpath')), '..', '..', '..', 'src', '+io', '+metadata', 'genotypes.info.yml');
            raw = yaml.load(fileread(ymlPath));
            rules = io.metadata.loadGenotypeInfo(raw);
            testCase.verifyTrue(numel(rules.byStrain) >= 6);
            testCase.verifyEqual(string(rules.RulesHash), string(io.metadata.loadGenotypeInfo(raw).RulesHash));
        end

        function badCanonicalInNormalizeErrors(testCase)
            % A normalize canonical not present in the strain's combos must hard-error.
            badRaw = struct( ...
                'strain', 'TestStrain', ...
                'combo', struct('male', {{'WT'}}, 'female', {{'WT'}}), ...
                'normalize', struct('KO', {{'Knockout'}}));
            testCase.verifyError(@() io.metadata.loadGenotypeInfo(badRaw), ...
                'io:metadata:loadGenotypeInfo:CanonicalNotInCombo');
        end

        function validatorRejectsBadInput(testCase)
            testCase.verifyError(@() validator.mustBeGenotypeInfoRules(123), ?MException); % numeric
            testCase.verifyError(@() validator.mustBeGenotypeInfoRules('nonexistent.yml'), ?MException);
        end
    end
end
